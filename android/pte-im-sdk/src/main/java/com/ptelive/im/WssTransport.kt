package com.ptelive.im

import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.URI
import java.security.MessageDigest
import java.security.SecureRandom
import android.util.Base64
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

internal interface WssListener {
  fun onOpen()
  fun onText(text: String)
  fun onClosed()
  fun onFailure(error: Throwable)
}

/** Minimal dependency-free RFC 6455 WSS transport for text protocol frames. */
internal class WssTransport(private val endpoint: String, private val listener: WssListener) {
  private val writeLock = Any()
  @Volatile private var socket: SSLSocket? = null
  @Volatile private var output: DataOutputStream? = null

  fun connect() = Thread({
    try {
      val uri = URI(endpoint)
      val port = if (uri.port == -1) 443 else uri.port
      val connection = (SSLSocketFactory.getDefault() as SSLSocketFactory)
        .createSocket(uri.host, port) as SSLSocket
      socket = connection
      connection.startHandshake()
      val input = DataInputStream(connection.inputStream)
      val writer = DataOutputStream(connection.outputStream)
      output = writer
      handshake(uri, input, writer)
      listener.onOpen()
      readFrames(input)
    } catch (error: Throwable) {
      if (socket != null) listener.onFailure(error)
    } finally {
      output = null
      socket?.close()
      socket = null
      listener.onClosed()
    }
  }, "PteIMSDK-WSS").start()

  fun sendText(text: String) = sendFrame(0x1, text.toByteArray(Charsets.UTF_8))

  fun close() {
    runCatching { sendFrame(0x8, byteArrayOf()) }
    socket?.close()
  }

  private fun handshake(uri: URI, input: DataInputStream, writer: DataOutputStream) {
    val nonce = ByteArray(16).also(SecureRandom()::nextBytes)
    val key = Base64.encodeToString(nonce, Base64.NO_WRAP)
    val path = (uri.rawPath?.ifBlank { "/" } ?: "/") + (uri.rawQuery?.let { "?$it" } ?: "")
    val host = if (uri.port == -1 || uri.port == 443) uri.host else "${uri.host}:${uri.port}"
    writer.write(("GET $path HTTP/1.1\r\nHost: $host\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
      "Sec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 13\r\n\r\n").toByteArray(Charsets.US_ASCII))
    writer.flush()
    val status = input.readAsciiLine()
    check(status.contains(" 101 ")) { "WSS upgrade failed: $status" }
    val headers = mutableMapOf<String, String>()
    while (true) {
      val line = input.readAsciiLine()
      if (line.isEmpty()) break
      val separator = line.indexOf(':')
      if (separator > 0) headers[line.substring(0, separator).lowercase()] = line.substring(separator + 1).trim()
    }
    val expected = Base64.encodeToString(
      MessageDigest.getInstance("SHA-1").digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray()), Base64.NO_WRAP,
    )
    check(headers["sec-websocket-accept"] == expected) { "WSS server returned an invalid accept key" }
  }

  private fun readFrames(input: DataInputStream) {
    while (socket != null && !socket!!.isClosed) {
      val first = input.readUnsignedByte()
      val fin = first and 0x80 != 0
      val opcode = first and 0x0f
      check(fin) { "fragmented WSS frames are not supported by protocol v1" }
      val second = input.readUnsignedByte()
      val masked = second and 0x80 != 0
      var length = (second and 0x7f).toLong()
      if (length == 126L) length = input.readUnsignedShort().toLong()
      if (length == 127L) length = input.readLong()
      check(length in 0..2_097_152) { "WSS frame exceeds 2 MiB" }
      val mask = if (masked) ByteArray(4).also(input::readFully) else null
      val payload = ByteArray(length.toInt()).also(input::readFully)
      mask?.let { key -> payload.indices.forEach { payload[it] = (payload[it].toInt() xor key[it % 4].toInt()).toByte() } }
      when (opcode) {
        0x1 -> listener.onText(payload.toString(Charsets.UTF_8))
        0x8 -> return
        0x9 -> sendFrame(0xA, payload)
      }
    }
  }

  private fun sendFrame(opcode: Int, payload: ByteArray) = synchronized(writeLock) {
    val writer = output ?: error("WSS is not connected")
    writer.writeByte(0x80 or opcode)
    val length = payload.size
    when {
      length < 126 -> writer.writeByte(0x80 or length)
      length <= 0xffff -> { writer.writeByte(0x80 or 126); writer.writeShort(length) }
      else -> { writer.writeByte(0x80 or 127); writer.writeLong(length.toLong()) }
    }
    val key = ByteArray(4).also(SecureRandom()::nextBytes)
    writer.write(key)
    payload.indices.forEach { writer.writeByte(payload[it].toInt() xor key[it % 4].toInt()) }
    writer.flush()
  }
}

private fun DataInputStream.readAsciiLine(): String {
  val bytes = ArrayList<Byte>()
  while (true) {
    val value = readUnsignedByte()
    if (value == 10) break
    if (value != 13) bytes += value.toByte()
    check(bytes.size < 8192) { "WSS header line is too long" }
  }
  return bytes.toByteArray().toString(Charsets.US_ASCII)
}
