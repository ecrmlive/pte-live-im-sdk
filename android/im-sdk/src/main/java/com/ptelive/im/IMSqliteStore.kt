package com.ptelive.im

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.security.MessageDigest

internal class PteIMSqliteStore(context: Context, storeKey: String) : SQLiteOpenHelper(
  context,
  "pte_live_im_${storeKey.sha256()}.db",
  null,
  1,
) {
  override fun onCreate(db: SQLiteDatabase) {
    db.execSQL("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.execSQL("INSERT INTO meta(key, value) VALUES ('db_schema_version', '1')")
    db.execSQL("CREATE TABLE sync_state (id INTEGER PRIMARY KEY CHECK (id = 1), cursor TEXT NOT NULL DEFAULT '')")
    db.execSQL("INSERT INTO sync_state(id, cursor) VALUES (1, '')")
    db.execSQL("CREATE TABLE conversations (id TEXT PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL)")
    db.execSQL("CREATE TABLE messages (client_msg_id TEXT PRIMARY KEY, server_msg_id TEXT, conversation_id TEXT NOT NULL, server_seq INTEGER, type TEXT NOT NULL, created_at INTEGER NOT NULL, state TEXT NOT NULL, payload TEXT NOT NULL)")
    db.execSQL("CREATE UNIQUE INDEX idx_messages_server_id ON messages(server_msg_id) WHERE server_msg_id IS NOT NULL")
    db.execSQL("CREATE INDEX idx_messages_conversation_seq ON messages(conversation_id, server_seq)")
    db.execSQL("CREATE TABLE outbox (client_msg_id TEXT PRIMARY KEY, retry_count INTEGER NOT NULL DEFAULT 0, next_retry_at INTEGER NOT NULL DEFAULT 0)")
  }

  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    // All future migrations must be additive and transactional; never delete user data here.
  }

  fun enqueue(message: PteIMMessage) = writableDatabase.transaction {
    insertMessage(this, message)
    insert("outbox", null, ContentValues().apply { put("client_msg_id", message.clientMsgId) })
  }

  fun markSent(clientMsgId: String, serverMsgId: String?, serverSeq: Long?) = writableDatabase.transaction {
    val values = ContentValues().apply {
      put("server_msg_id", serverMsgId)
      put("server_seq", serverSeq)
      put("state", PteIMSendState.SENT.name)
    }
    update("messages", values, "client_msg_id = ?", arrayOf(clientMsgId))
    delete("outbox", "client_msg_id = ?", arrayOf(clientMsgId))
  }

  fun replaceQueued(message: PteIMMessage) = writableDatabase.transaction { insertMessage(this, message) }

  fun markFailed(clientMsgId: String) = writableDatabase.transaction {
    update("messages", ContentValues().apply { put("state", PteIMSendState.FAILED.name) }, "client_msg_id = ?", arrayOf(clientMsgId))
    delete("outbox", "client_msg_id = ?", arrayOf(clientMsgId))
  }

  fun applyDelta(nextCursor: String, messages: List<PteIMMessage>) = writableDatabase.transaction {
    messages.forEach { insertMessage(this, it.copy(state = PteIMSendState.SENT)) }
    update("sync_state", ContentValues().apply { put("cursor", nextCursor) }, "id = 1", null)
  }

  fun cursor(): String = readableDatabase.rawQuery("SELECT cursor FROM sync_state WHERE id = 1", null).use {
    if (it.moveToFirst()) it.getString(0) else ""
  }

  fun localMessages(conversationId: String, beforeCreatedAt: Long?, limit: Int): List<StoredMessage> {
    require(limit in 1..200) { "limit must be between 1 and 200" }
    val selection = if (beforeCreatedAt == null) "conversation_id = ?" else "conversation_id = ? AND created_at < ?"
    val args = if (beforeCreatedAt == null) arrayOf(conversationId) else arrayOf(conversationId, beforeCreatedAt.toString())
    return readableDatabase.rawQuery(
      "SELECT payload, server_msg_id, server_seq, created_at, state FROM messages WHERE $selection ORDER BY created_at DESC LIMIT $limit",
      args,
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(StoredMessage(cursor.getString(0), cursor.getStringOrNull(1), cursor.getLongOrNull(2), cursor.getLong(3), cursor.getString(4))) } }
  }

  fun localConversations(limit: Int): List<StoredConversation> {
    require(limit in 1..200) { "limit must be between 1 and 200" }
    return readableDatabase.rawQuery(
      "SELECT conversation_id, MAX(created_at), (SELECT payload FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1), (SELECT server_msg_id FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1), (SELECT server_seq FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1), (SELECT state FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1) FROM messages GROUP BY conversation_id ORDER BY MAX(created_at) DESC LIMIT $limit",
      null,
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(StoredConversation(cursor.getString(0), cursor.getLong(1), StoredMessage(cursor.getString(2), cursor.getStringOrNull(3), cursor.getLongOrNull(4), cursor.getLong(1), cursor.getString(5)))) } }
  }

  /** Returns retryable messages whose persisted backoff has elapsed. */
  fun dueOutbox(now: Long, limit: Int = 100): List<StoredMessage> {
    require(limit in 1..200) { "limit must be between 1 and 200" }
    return readableDatabase.rawQuery(
      "SELECT m.payload, m.server_msg_id, m.server_seq, m.created_at, m.state FROM outbox o JOIN messages m ON m.client_msg_id = o.client_msg_id WHERE o.next_retry_at <= ? ORDER BY o.next_retry_at ASC LIMIT $limit",
      arrayOf(now.toString()),
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(StoredMessage(cursor.getString(0), cursor.getStringOrNull(1), cursor.getLongOrNull(2), cursor.getLong(3), cursor.getString(4))) } }
  }

  /** Records one send attempt and returns its next persisted retry time. */
  fun recordOutboxAttempt(clientMsgId: String, now: Long): Long? = writableDatabase.transactionResult {
    val retryCount = rawQuery("SELECT retry_count FROM outbox WHERE client_msg_id = ?", arrayOf(clientMsgId)).use { cursor ->
      if (cursor.moveToFirst()) cursor.getInt(0) else return@transactionResult null
    }
    val nextRetryAt = now + retryDelayMs(retryCount)
    update("outbox", ContentValues().apply {
      put("retry_count", retryCount + 1)
      put("next_retry_at", nextRetryAt)
    }, "client_msg_id = ?", arrayOf(clientMsgId))
    nextRetryAt
  }

  fun nextOutboxRetryAt(): Long? = readableDatabase.rawQuery("SELECT MIN(next_retry_at) FROM outbox", null).use { cursor ->
    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
  }

  private fun insertMessage(db: SQLiteDatabase, message: PteIMMessage) {
    db.insertWithOnConflict("messages", null, ContentValues().apply {
      put("client_msg_id", message.clientMsgId)
      put("server_msg_id", message.serverMsgId)
      put("conversation_id", message.conversationId)
      put("server_seq", message.serverSeq)
      put("type", message.type.name)
      put("created_at", message.createdAt)
      put("state", message.state.name)
      put("payload", message.toWireJson().toString())
    }, SQLiteDatabase.CONFLICT_REPLACE)
  }
}

internal data class StoredMessage(
  val payload: String,
  val serverMsgId: String?,
  val serverSeq: Long?,
  val createdAt: Long,
  val state: String,
)
internal data class StoredConversation(val conversationId: String, val updatedAt: Long, val lastMessage: StoredMessage)

private inline fun SQLiteDatabase.transaction(block: SQLiteDatabase.() -> Unit) {
  beginTransaction()
  try { block(); setTransactionSuccessful() } finally { endTransaction() }
}

private inline fun <T> SQLiteDatabase.transactionResult(block: SQLiteDatabase.() -> T): T {
  beginTransaction()
  return try { block().also { setTransactionSuccessful() } } finally { endTransaction() }
}

private fun retryDelayMs(retryCount: Int): Long = 1_000L shl retryCount.coerceIn(0, 5)

private fun String.sha256(): String = MessageDigest.getInstance("SHA-256")
  .digest(toByteArray()).joinToString("") { "%02x".format(it) }

private fun android.database.Cursor.getStringOrNull(index: Int): String? = if (isNull(index)) null else getString(index)
private fun android.database.Cursor.getLongOrNull(index: Int): Long? = if (isNull(index)) null else getLong(index)
