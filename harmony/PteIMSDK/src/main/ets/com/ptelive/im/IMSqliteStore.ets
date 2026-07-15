import { relationalStore } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { PteIMConversation, PteIMMessage, PteIMSendState } from './IMModels'

interface PteIMStoreConfig extends relationalStore.StoreConfig {}

export class PteIMStoredMessage {
  payload: string
  serverMsgId: string
  serverSeq: number
  createdAt: number
  state: PteIMSendState

  constructor(payload: string, serverMsgId: string, serverSeq: number, createdAt: number, state: PteIMSendState) {
    this.payload = payload
    this.serverMsgId = serverMsgId
    this.serverSeq = serverSeq
    this.createdAt = createdAt
    this.state = state
  }
}

export class PteIMStoredConversation {
  conversationId: string
  stored: PteIMStoredMessage

  constructor(conversationId: string, stored: PteIMStoredMessage) {
    this.conversationId = conversationId
    this.stored = stored
  }
}

/** Account-isolated relational-store cache. It keeps only metadata and JSON payloads, never UserSig. */
export class PteIMSqliteStore {
  private store: relationalStore.RdbStore

  private constructor(store: relationalStore.RdbStore) { this.store = store }

  static async open(context: Context, storeName: string): Promise<PteIMSqliteStore> {
    const config: PteIMStoreConfig = {
      name: storeName,
      securityLevel: relationalStore.SecurityLevel.S1,
      encrypt: true,
    }
    const store = await relationalStore.getRdbStore(context, config)
    const value = new PteIMSqliteStore(store)
    await value.migrate()
    return value
  }

  private async migrate(): Promise<void> {
    await this.store.executeSql('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
    await this.store.executeSql('CREATE TABLE IF NOT EXISTS sync_state (id INTEGER PRIMARY KEY CHECK (id = 1), cursor TEXT NOT NULL DEFAULT \'\')')
    await this.store.executeSql('INSERT OR IGNORE INTO sync_state(id,cursor) VALUES(1,\'\')')
    await this.store.executeSql('CREATE TABLE IF NOT EXISTS messages (client_msg_id TEXT PRIMARY KEY, server_msg_id TEXT, conversation_id TEXT NOT NULL, server_seq INTEGER, created_at INTEGER NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL)')
    await this.store.executeSql('CREATE TABLE IF NOT EXISTS outbox (client_msg_id TEXT PRIMARY KEY, retry_count INTEGER NOT NULL DEFAULT 0, next_retry_at INTEGER NOT NULL DEFAULT 0)')
    await this.store.executeSql('CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at)')
    await this.store.executeSql('INSERT OR REPLACE INTO meta(key,value) VALUES(\'db_schema_version\',\'1\')')
  }

  async cursor(): Promise<string> {
    const rows = await this.store.querySql('SELECT cursor FROM sync_state WHERE id=1')
    try { return rows.goToFirstRow() ? rows.getString(rows.getColumnIndex('cursor')) : '' } finally { rows.close() }
  }

  /** Encrypted account-local metadata, used for the device E2EE keypair only. */
  async metaValue(key: string): Promise<string> {
    const rows = await this.store.querySql('SELECT value FROM meta WHERE key=?', [key])
    try { return rows.goToFirstRow() ? rows.getString(rows.getColumnIndex('value')) : '' } finally { rows.close() }
  }

  async setMeta(key: string, value: string): Promise<void> {
    await this.store.executeSql('INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)', [key, value])
  }

  async enqueue(message: PteIMMessage): Promise<void> {
    await this.upsert(message, message.state)
    await this.store.executeSql('INSERT OR REPLACE INTO outbox(client_msg_id,retry_count,next_retry_at) VALUES(?,0,0)', [message.clientMsgId])
  }

  async replaceQueued(message: PteIMMessage): Promise<void> { await this.upsert(message, message.state) }

  async markSent(clientMsgId: string, serverMsgId: string, serverSeq: number): Promise<void> {
    await this.store.executeSql('UPDATE messages SET server_msg_id=?,server_seq=?,state=? WHERE client_msg_id=?', [serverMsgId, serverSeq, PteIMSendState.SENT, clientMsgId])
    await this.store.executeSql('DELETE FROM outbox WHERE client_msg_id=?', [clientMsgId])
  }

  async markFailed(clientMsgId: string): Promise<void> {
    await this.store.executeSql('UPDATE messages SET state=? WHERE client_msg_id=?', [PteIMSendState.FAILED, clientMsgId])
    await this.store.executeSql('DELETE FROM outbox WHERE client_msg_id=?', [clientMsgId])
  }

  async apply(messages: PteIMMessage[], cursor: string): Promise<void> {
    for (let index = 0; index < messages.length; index++) await this.upsert(messages[index], PteIMSendState.SENT)
    await this.store.executeSql('UPDATE sync_state SET cursor=? WHERE id=1', [cursor])
  }

  async dueOutbox(now: number): Promise<PteIMStoredMessage[]> {
    return await this.readStored('SELECT m.payload,m.server_msg_id,m.server_seq,m.created_at,m.state FROM outbox o INNER JOIN messages m ON o.client_msg_id=m.client_msg_id WHERE o.next_retry_at<=? ORDER BY o.next_retry_at LIMIT 100', [now])
  }

  async recordOutboxAttempt(clientMsgId: string, now: number): Promise<void> {
    const result = await this.store.querySql('SELECT retry_count FROM outbox WHERE client_msg_id=?', [clientMsgId])
    let retryCount = 0
    try { if (!result.goToFirstRow()) return; retryCount = result.getLong(result.getColumnIndex('retry_count')) } finally { result.close() }
    const delay = 1000 * Math.pow(2, Math.min(Math.max(retryCount, 0), 5))
    await this.store.executeSql('UPDATE outbox SET retry_count=?,next_retry_at=? WHERE client_msg_id=?', [retryCount + 1, now + delay, clientMsgId])
  }

  async nextOutboxRetryAt(): Promise<number> {
    const rows = await this.store.querySql('SELECT MIN(next_retry_at) AS at FROM outbox')
    try { return rows.goToFirstRow() && !rows.isColumnNull(rows.getColumnIndex('at')) ? rows.getLong(rows.getColumnIndex('at')) : 0 } finally { rows.close() }
  }

  async localMessages(conversationId: string, beforeCreatedAt: number = 0, limit: number = 50): Promise<PteIMStoredMessage[]> {
    const safeLimit = Math.min(Math.max(limit, 1), 200)
    if (beforeCreatedAt > 0) return await this.readStored(`SELECT payload,server_msg_id,server_seq,created_at,state FROM messages WHERE conversation_id=? AND created_at<? ORDER BY created_at DESC LIMIT ${safeLimit}`, [conversationId, beforeCreatedAt])
    return await this.readStored(`SELECT payload,server_msg_id,server_seq,created_at,state FROM messages WHERE conversation_id=? ORDER BY created_at DESC LIMIT ${safeLimit}`, [conversationId])
  }

  async localConversations(limit: number = 100): Promise<PteIMStoredConversation[]> {
    const safeLimit = Math.min(Math.max(limit, 1), 200)
    const rows = await this.store.querySql(`SELECT m.conversation_id,m.payload,m.server_msg_id,m.server_seq,m.created_at,m.state FROM messages m WHERE m.rowid=(SELECT newest.rowid FROM messages newest WHERE newest.conversation_id=m.conversation_id ORDER BY newest.created_at DESC LIMIT 1) ORDER BY m.created_at DESC LIMIT ${safeLimit}`)
    const values: PteIMStoredConversation[] = []
    try {
      while (rows.goToNextRow()) values.push(new PteIMStoredConversation(rows.getString(rows.getColumnIndex('conversation_id')), this.rowToStored(rows)))
    } finally { rows.close() }
    return values
  }

  private async upsert(message: PteIMMessage, state: PteIMSendState): Promise<void> {
    const payload = JSON.stringify(message.toWire())
    await this.store.executeSql('INSERT OR REPLACE INTO messages(client_msg_id,server_msg_id,conversation_id,server_seq,created_at,payload,state) VALUES(?,?,?,?,?,?,?)', [message.clientMsgId, message.serverMsgId, message.conversationId, message.serverSeq, message.createdAt, payload, state])
  }

  private async readStored(sql: string, args: (string | number)[]): Promise<PteIMStoredMessage[]> {
    const rows = await this.store.querySql(sql, args)
    const values: PteIMStoredMessage[] = []
    try { while (rows.goToNextRow()) values.push(this.rowToStored(rows)) } finally { rows.close() }
    return values
  }

  private rowToStored(row: relationalStore.ResultSet): PteIMStoredMessage {
    return new PteIMStoredMessage(row.getString(row.getColumnIndex('payload')), row.isColumnNull(row.getColumnIndex('server_msg_id')) ? '' : row.getString(row.getColumnIndex('server_msg_id')), row.isColumnNull(row.getColumnIndex('server_seq')) ? 0 : row.getLong(row.getColumnIndex('server_seq')), row.getLong(row.getColumnIndex('created_at')), row.getString(row.getColumnIndex('state')) as PteIMSendState)
  }
}
