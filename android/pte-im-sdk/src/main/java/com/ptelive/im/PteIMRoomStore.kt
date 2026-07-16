package com.ptelive.im

import android.content.ContentValues
import android.content.Context
import androidx.room.Database
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import org.json.JSONObject
import java.security.MessageDigest

private const val PTE_IM_CONFLICT_REPLACE = 5

@Entity(tableName = "pte_im_room_anchor")
internal data class PteIMRoomAnchor(@PrimaryKey val id: Int = 1)

@Database(entities = [PteIMRoomAnchor::class], version = 1, exportSchema = false)
internal abstract class PteIMRoomDatabase : RoomDatabase()

/** Room-backed encrypted account cache. Only this class owns local persistence. */
internal class PteIMRoomStore(context: Context, storeKey: String) {
  private val cipher = PteIMLocalCipher(storeKey)
  private val database = Room.databaseBuilder(
    context.applicationContext,
    PteIMRoomDatabase::class.java,
    "pte_live_im_${storeKey.sha256()}.room",
  ).setJournalMode(RoomDatabase.JournalMode.WRITE_AHEAD_LOGGING).build()
  private val db: SupportSQLiteDatabase get() = database.openHelper.writableDatabase

  init {
    db.transaction {
      execSQL("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
      execSQL("CREATE TABLE IF NOT EXISTS sync_state (id INTEGER PRIMARY KEY CHECK (id = 1), cursor TEXT NOT NULL DEFAULT '')")
      execSQL("INSERT OR IGNORE INTO sync_state(id, cursor) VALUES (1, '')")
      execSQL("CREATE TABLE IF NOT EXISTS remote_conversations (id INTEGER PRIMARY KEY, updated_at INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL)")
      execSQL("CREATE TABLE IF NOT EXISTS messages (client_msg_id TEXT PRIMARY KEY, server_msg_id TEXT, conversation_id TEXT NOT NULL, server_seq INTEGER, type TEXT NOT NULL, created_at INTEGER NOT NULL, state TEXT NOT NULL, payload TEXT NOT NULL)")
      execSQL("CREATE TABLE IF NOT EXISTS outbox (client_msg_id TEXT PRIMARY KEY, retry_count INTEGER NOT NULL DEFAULT 0, next_retry_at INTEGER NOT NULL DEFAULT 0)")
      execSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_server_id ON messages(server_msg_id) WHERE server_msg_id IS NOT NULL")
      execSQL("CREATE INDEX IF NOT EXISTS idx_messages_conversation_seq ON messages(conversation_id, server_seq)")
      execSQL("CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_at ON messages(conversation_id, created_at)")
      execSQL("CREATE INDEX IF NOT EXISTS idx_remote_conversations_updated_at ON remote_conversations(updated_at DESC, id DESC)")
    }
  }

  fun enqueue(message: PteIMMessage) = db.transaction {
    insertMessage(this, message)
    insert("outbox", PTE_IM_CONFLICT_REPLACE, ContentValues().apply { put("client_msg_id", message.clientMsgId) })
  }

  fun markSent(clientMsgId: String, serverMsgId: String?, serverSeq: Long?) = db.transaction {
    val values = ContentValues().apply {
      put("server_msg_id", serverMsgId)
      put("server_seq", serverSeq)
      put("state", PteIMSendState.SENT.name)
    }
    update("messages", PTE_IM_CONFLICT_REPLACE, values, "client_msg_id = ?", arrayOf(clientMsgId))
    delete("outbox", "client_msg_id = ?", arrayOf(clientMsgId))
  }

  fun replaceQueued(message: PteIMMessage) = db.transaction { insertMessage(this, message) }

  fun markFailed(clientMsgId: String) = db.transaction {
    update("messages", PTE_IM_CONFLICT_REPLACE, ContentValues().apply { put("state", PteIMSendState.FAILED.name) }, "client_msg_id = ?", arrayOf(clientMsgId))
    delete("outbox", "client_msg_id = ?", arrayOf(clientMsgId))
  }

  fun applyDelta(nextCursor: String, messages: List<PteIMMessage>) = db.transaction {
    messages.forEach { insertMessage(this, it.copy(state = PteIMSendState.SENT)) }
    update("sync_state", PTE_IM_CONFLICT_REPLACE, ContentValues().apply { put("cursor", cipher.encrypt(nextCursor)) }, "id = 1", null)
  }

  fun cursor(): String = db.query("SELECT cursor FROM sync_state WHERE id = 1").use {
    if (it.moveToFirst()) cipher.decrypt(it.getString(0)) else ""
  }
  fun stateCursor(): String = db.query("SELECT value FROM meta WHERE key = 'state_sync_cursor'").use { if (it.moveToFirst()) cipher.decrypt(it.getString(0)) else "" }
  fun setStateCursor(value: String) { db.insert("meta", PTE_IM_CONFLICT_REPLACE, ContentValues().apply { put("key", "state_sync_cursor"); put("value", cipher.encrypt(value)) }) }
  fun conversationCursor(): String = db.query("SELECT value FROM meta WHERE key = 'conversation_sync_cursor'").use { if (it.moveToFirst()) cipher.decrypt(it.getString(0)) else "" }

  /** Atomically merges one cursor page from the server-authoritative conversation list. */
  fun applyRemoteConversations(items: List<PteIMRemoteConversation>, nextCursor: String) = db.transaction {
    items.forEach { conversation ->
      insert("remote_conversations", PTE_IM_CONFLICT_REPLACE, ContentValues().apply {
        put("id", conversation.id)
        put("updated_at", conversation.lastMessageAt)
        put("payload", cipher.encrypt(conversation.toJson().toString()))
      })
    }
    insert("meta", PTE_IM_CONFLICT_REPLACE, ContentValues().apply {
      put("key", "conversation_sync_cursor")
      put("value", cipher.encrypt(nextCursor))
    })
  }

  fun localRemoteConversations(limit: Int): List<StoredRemoteConversation> {
    require(limit in 1..200) { "limit must be between 1 and 200" }
    return db.query("SELECT payload FROM remote_conversations ORDER BY updated_at DESC, id DESC LIMIT $limit").use { rows -> buildList { while (rows.moveToNext()) add(StoredRemoteConversation(cipher.decrypt(rows.getString(0)))) } }
  }

  fun localMessages(conversationId: String, beforeCreatedAt: Long?, limit: Int): List<StoredMessage> {
    require(limit in 1..200) { "limit must be between 1 and 200" }
    val selection = if (beforeCreatedAt == null) "conversation_id = ?" else "conversation_id = ? AND created_at < ?"
    val args = if (beforeCreatedAt == null) arrayOf(conversationId) else arrayOf(conversationId, beforeCreatedAt.toString())
    return db.query(
      "SELECT payload, server_msg_id, server_seq, created_at, state FROM messages WHERE $selection ORDER BY created_at DESC LIMIT $limit",
      args,
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(StoredMessage(cipher.decrypt(cursor.getString(0)), cursor.getStringOrNull(1), cursor.getLongOrNull(2), cursor.getLong(3), cursor.getString(4))) } }
  }

  fun localConversations(limit: Int): List<StoredConversation> {
    require(limit in 1..200) { "limit must be between 1 and 200" }
    return db.query("SELECT conversation_id, MAX(created_at), (SELECT payload FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1), (SELECT server_msg_id FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1), (SELECT server_seq FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1), (SELECT state FROM messages latest WHERE latest.conversation_id = messages.conversation_id ORDER BY created_at DESC LIMIT 1) FROM messages GROUP BY conversation_id ORDER BY MAX(created_at) DESC LIMIT $limit").use { cursor -> buildList { while (cursor.moveToNext()) add(StoredConversation(cursor.getString(0), cursor.getLong(1), StoredMessage(cipher.decrypt(cursor.getString(2)), cursor.getStringOrNull(3), cursor.getLongOrNull(4), cursor.getLong(1), cursor.getString(5)))) } }
  }

  /** Returns retryable messages whose persisted backoff has elapsed. */
  fun dueOutbox(now: Long, limit: Int = 100): List<StoredMessage> {
    require(limit in 1..200) { "limit must be between 1 and 200" }
    return db.query(
      "SELECT m.payload, m.server_msg_id, m.server_seq, m.created_at, m.state FROM outbox o JOIN messages m ON m.client_msg_id = o.client_msg_id WHERE o.next_retry_at <= ? ORDER BY o.next_retry_at ASC LIMIT $limit",
      arrayOf(now.toString()),
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(StoredMessage(cipher.decrypt(cursor.getString(0)), cursor.getStringOrNull(1), cursor.getLongOrNull(2), cursor.getLong(3), cursor.getString(4))) } }
  }

  /** Records one send attempt and returns its next persisted retry time. */
  fun recordOutboxAttempt(clientMsgId: String, now: Long): Long? = db.transactionResult {
    val retryCount = query("SELECT retry_count FROM outbox WHERE client_msg_id = ?", arrayOf(clientMsgId)).use { cursor ->
      if (cursor.moveToFirst()) cursor.getInt(0) else return@transactionResult null
    }
    val nextRetryAt = now + retryDelayMs(retryCount)
    update("outbox", PTE_IM_CONFLICT_REPLACE, ContentValues().apply {
      put("retry_count", retryCount + 1)
      put("next_retry_at", nextRetryAt)
    }, "client_msg_id = ?", arrayOf(clientMsgId))
    nextRetryAt
  }

  fun nextOutboxRetryAt(): Long? = db.query("SELECT MIN(next_retry_at) FROM outbox").use { cursor ->
    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
  }

  private fun insertMessage(db: SupportSQLiteDatabase, message: PteIMMessage) {
    db.insert("messages", PTE_IM_CONFLICT_REPLACE, ContentValues().apply {
      put("client_msg_id", message.clientMsgId)
      put("server_msg_id", message.serverMsgId)
      put("conversation_id", message.conversationId)
      put("server_seq", message.serverSeq)
      put("type", message.type.name)
      put("created_at", message.createdAt)
      put("state", message.state.name)
      put("payload", cipher.encrypt(message.toWireJson().toString()))
    })
  }

  companion object {
    /** Explicit recovery for an unavailable Keystore key or irrecoverably corrupted local cache. */
    fun clear(context: Context, storeKey: String) {
      context.applicationContext.deleteDatabase("pte_live_im_${storeKey.sha256()}.room")
      PteIMLocalCipher.removeKey(storeKey)
    }
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
internal data class StoredRemoteConversation(val payload: String)

private inline fun SupportSQLiteDatabase.transaction(block: SupportSQLiteDatabase.() -> Unit) {
  beginTransaction()
  try { block(); setTransactionSuccessful() } finally { endTransaction() }
}

private inline fun <T> SupportSQLiteDatabase.transactionResult(block: SupportSQLiteDatabase.() -> T): T {
  beginTransaction()
  return try { block().also { setTransactionSuccessful() } } finally { endTransaction() }
}

private fun retryDelayMs(retryCount: Int): Long = 1_000L shl retryCount.coerceIn(0, 5)

private fun String.sha256(): String = MessageDigest.getInstance("SHA-256")
  .digest(toByteArray()).joinToString("") { "%02x".format(it) }

private fun android.database.Cursor.getStringOrNull(index: Int): String? = if (isNull(index)) null else getString(index)
private fun android.database.Cursor.getLongOrNull(index: Int): Long? = if (isNull(index)) null else getLong(index)

private fun PteIMRemoteConversation.toJson(): JSONObject = JSONObject().apply {
  put("id", id); put("type", type); put("title", title); put("avatar", avatar)
  put("last_message_seq", lastMessageSeq); put("last_message_snapshot", lastMessageSnapshot)
  put("last_message_at", lastMessageAt); put("unread_count", unreadCount)
}
