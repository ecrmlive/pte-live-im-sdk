# SDK local storage encryption

This document describes the SDK's **at-rest cache protection**, the api-im encrypted-response transport, and the E2EE wire contract. It does not place any service credential in the app.

## Native SDKs

| SDK | Protection | Key location |
| --- | --- | --- |
| Android | AES-256-GCM encrypts persisted message JSON, offline-outbox JSON, and the sync cursor. | Android Keystore, non-exportable per account/cache namespace key. |
| iOS | Core Data values use AES-256-GCM and file protection `complete`. | Keychain, `AfterFirstUnlockThisDeviceOnly`, per account/cache namespace key. |
| HarmonyOS | The relational store is opened with `encrypt: true` and security level `S1`. | HarmonyOS relational-store encryption service. |

Platform stores keep the minimum query metadata in clear text: cache namespace hash, conversation ID, client/server message IDs, message type, timestamps, send state, retry time, and sequence numbers. This allows local paging, de-duplication, and reliable retry without decrypting every row. Do not treat this as a full-database-metadata-hiding scheme.

Android and iOS transparently migrate pre-existing plaintext and `pte1:` records to `pte2:` on store open. `pte2:` is AES-GCM with additional authenticated data bound to the account/cache namespace, so a ciphertext cannot be transplanted to another account cache. A Keychain/Keystore reset makes prior encrypted cache unavailable by design; after the host clears that local cache, a server sync recreates it.

## Native cache encryption/decryption loop

```text
login namespace → obtain per-cache key → open store and migrate old rows
     ↓
serialize message / outbox / cursor → AES-256-GCM encrypt (`pte2:`) → platform store
     ↓
platform store → verify AES-GCM tag and cache namespace → decrypt → SDK message model
```

Authentication-tag verification happens before JSON is decoded or a queued message is sent. A changed, truncated, or account-transplanted `pte2:` value fails decryption rather than being treated as valid cache data. If an OS security-store reset makes the key unavailable, the host must clear the affected **local SDK cache** and run a server sync again; a UserSig, COS credential, or server-side secret is never used as a replacement encryption key.

Android and iOS provide an explicit recovery API for this case. Stop the client first, call `clearLocalCache(loginConfig)` on the bootstrap object, then log in and call `syncNow()`. It deletes only the selected SDK account cache and its corresponding local Keystore/Keychain cache key; it does not affect system files, other app data, UserSig values, or server messages.

## UTS: H5 and mini-program

H5/Web and WeChat mini-program do not share an SDK-controlled hardware-backed key store. Therefore the UTS SDK does **not** persist messages, offline outbox data, or sync cursors by default. This avoids a silent plaintext cache.

For the UTS E2EE implementation, H5 uses browser cryptographic randomness and WeChat uses `wx.getRandomValues`; neither path falls back to `Math.random()` or reuses a consumed random buffer. The pinned build-time `@noble/ciphers`, `@noble/curves`, and `@noble/hashes` dependencies provide P-256, AES-GCM, and HMAC-SHA-256. Their versions and licenses are recorded in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

To opt in to durable UTS storage, set `localStorageCipher` in `PteIMBaseConfig`. It must synchronously encrypt and decrypt strings, and its key must be supplied at runtime rather than saved in `uni` storage or bundled source. The SDK prefixes stored values with `pte1:` and rejects legacy plaintext cache values.

```uts
const im = createPteIMSDK({
  apiDomain: 'https://api.example.com',
  imDomain: 'wss://im.example.com/ws',
  cosDomain: 'https://cdn.example.com',
  localStorageCipher: {
    encrypt: (plaintext) => hostEncrypt(plaintext),
    decrypt: (ciphertext) => hostDecrypt(ciphertext),
  },
})
```

The host is responsible for supplying a reviewed cryptographic implementation and safely deriving/holding its key. JavaScript encryption cannot protect against an active same-origin/XSS attacker that can access the running key.

## Browser Web SDK (`@pte-live/im-web-sdk`)

The standalone browser Core uses the same `@noble/*` P-256 / AES-GCM / HMAC-SHA-256 stack as UTS (versions in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)). It persists only the E2EE device identity (private key + `device_id`) in IndexedDB, wrapped by a non-extractable AES-GCM key in the same origin. It does **not** persist chat message bodies, outbox rows, or sync cursors. If IndexedDB is unavailable (for example private browsing), identity persistence is skipped and the session remains usable for that tab.

Like UTS, browser JavaScript cannot defend against an active same-origin/XSS attacker that can read keys in memory. Do not embed UserSig signing secrets, COS credentials, or long-lived refresh tokens in the web bundle.

Live-room helpers under `@pte-live/im-web-sdk/live` are pure sequence/dedupe utilities and store nothing durable.

## api-im encrypted responses

The `/v1/im/*` API and E2EE device APIs use a one-response P-256/A256GCM envelope. The SDK creates a fresh P-256 request key for every request and sends its 65-byte uncompressed public key (base64url without padding) in `X-Pte-Response-Public-Key`. It decrypts the response with:

```text
sharedSecret = P-256 ECDH(clientEphemeralPrivate, serverEphemeralPublic)
responseKey  = HMAC-SHA-256(salt, sharedSecret || "pte-live-api-response-v1")
AAD          = "pte-live-api-response-v1"
```

The encrypted response object contains `version`, `algorithm: "P-256/A256GCM"`, `ephemeral_public_key`, `salt` (32 bytes), `nonce` (12 bytes), and `ciphertext` (AES-GCM ciphertext with tag). COS PUT credential responses are intentionally not wrapped by this envelope: they use the `api-im` media endpoint's `{ code: 0, data }` response contract.

## E2EE message envelope

Android and iOS generate one persistent P-256 device identity per SDK account namespace. The private material is protected by Android Keystore/Keychain; its public key is registered at `POST /api/v1/chat/e2ee/device/register`. Before each outgoing message, the SDK fetches the active recipient devices and audit-key policy, creates a random AES-256 content key, and sends only the following `e2ee` object in the WebSocket payload:

```json
{
  "version": 1,
  "algorithm": "P-256/A256GCM",
  "ciphertext": "base64url(AES-GCM(content JSON))",
  "nonce": "base64url(12 bytes)",
  "recipients": [{
    "user_id": 10001,
    "device_id": "device UUID",
    "ephemeral_public_key": "base64url(P-256)",
    "wrapped_key": "base64url(AES-GCM(content key))",
    "nonce": "base64url(12 bytes)"
  }]
}
```

Content encryption uses AAD `pte-live-im-message-v1`. For every recipient (and, when enabled, the mandatory audit key), an ephemeral ECDH secret derives the wrapping key as `HMAC-SHA-256(wrapNonce, sharedSecret || "pte-live-im-audit-wrap-v1")`; the content key is AES-GCM encrypted using that same label as AAD. The SDK decrypts an incoming envelope only when it finds the local registered `device_id`. It never puts content keys, device private keys, COS SecretId/SecretKey, or UserSig-generation secrets on the wire or in the public repository.

This implementation deliberately fails a send if the service requires an audit recipient but does not supply a supported audit key. For an encrypted receive, it fails when the local device is not one of the encrypted recipients; old server history without an `e2ee` field remains readable only for migration compatibility and must not be used to silently downgrade newly sent messages.

Never embed COS SecretId, SecretKey, private keys, UserSig-generation secrets, or a durable UTS encryption key in a public repository or app bundle.
