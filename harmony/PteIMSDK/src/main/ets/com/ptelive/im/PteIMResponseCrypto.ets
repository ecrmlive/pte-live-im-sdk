import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import util from '@ohos.util'

/**
 * Native OpenHarmony implementation of the api-im response envelope. It uses
 * only CryptoArchitectureKit: ECC256 (NIST P-256), HMAC-SHA-256 and AES-GCM.
 * Keys are one-request ephemeral keys and are never persisted.
 */
export class PteIMResponseRequestKey {
  pair: cryptoFramework.KeyPair
  publicKey: string

  constructor(pair: cryptoFramework.KeyPair, publicKey: string) {
    this.pair = pair
    this.publicKey = publicKey
  }
}

export class PteIMResponseCrypto {
  private static readonly apiAAD: string = 'pte-live-api-response-v1'
  // ASN.1 SubjectPublicKeyInfo prefix for a secp256r1 uncompressed point.
  private static readonly p256SPKIPrefix: Uint8Array = new Uint8Array([48, 89, 48, 19, 6, 7, 42, 134, 72, 206, 61, 2, 1, 6, 8, 42, 134, 72, 206, 61, 3, 1, 7, 3, 66, 0])

  static async createRequestKey(): Promise<PteIMResponseRequestKey> {
    const pair = await cryptoFramework.createAsyKeyGenerator('ECC256').generateKeyPair()
    const encoded = pair.pubKey.getEncoded().data
    if (encoded.length < 65) throw new Error('invalid P-256 public key')
    const raw = encoded.slice(encoded.length - 65)
    if (raw[0] !== 4) throw new Error('P-256 public key must be uncompressed')
    return new PteIMResponseRequestKey(pair, PteIMResponseCrypto.base64URL(raw))
  }

  static async decryptResponse(root: Record<string, Object>, requestKey: PteIMResponseRequestKey): Promise<Record<string, Object>> {
    if (PteIMResponseCrypto.numberValue(root, 'version') !== 1 || PteIMResponseCrypto.stringValue(root, 'algorithm') !== 'P-256/A256GCM') throw new Error('unsupported API response encryption')
    const serverPublic = PteIMResponseCrypto.base64URLDecode(PteIMResponseCrypto.stringValue(root, 'ephemeral_public_key'))
    const salt = PteIMResponseCrypto.base64URLDecode(PteIMResponseCrypto.stringValue(root, 'salt'))
    const nonce = PteIMResponseCrypto.base64URLDecode(PteIMResponseCrypto.stringValue(root, 'nonce'))
    const ciphertextAndTag = PteIMResponseCrypto.base64URLDecode(PteIMResponseCrypto.stringValue(root, 'ciphertext'))
    if (serverPublic.length !== 65 || salt.length !== 32 || nonce.length !== 12 || ciphertextAndTag.length <= 16) throw new Error('invalid API response encryption envelope')
    const peer = await PteIMResponseCrypto.publicKeyFromRaw(serverPublic)
    const secret = (await cryptoFramework.createKeyAgreement('ECC256').generateSecret(requestKey.pair.priKey, peer)).data
    const aesKey = await PteIMResponseCrypto.deriveKey(secret, salt, PteIMResponseCrypto.apiAAD)
    const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7')
    const contentLength = ciphertextAndTag.length - 16
    const parameters: cryptoFramework.GcmParamsSpec = {
      algName: 'AES256|GCM|PKCS7', iv: { data: nonce }, aad: { data: PteIMResponseCrypto.utf8(PteIMResponseCrypto.apiAAD) }, authTag: { data: ciphertextAndTag.slice(contentLength) },
    }
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, aesKey, parameters)
    const clear = (await cipher.doFinal({ data: ciphertextAndTag.slice(0, contentLength) })).data
    return JSON.parse(util.TextDecoder.create('utf-8').decode(clear)) as Record<string, Object>
  }

  static async deriveKey(secret: Uint8Array, salt: Uint8Array, label: string): Promise<cryptoFramework.SymKey> {
    const macKey = await cryptoFramework.createSymKeyGenerator('HMAC|SHA256').convertKey({ data: salt })
    const mac = cryptoFramework.createMac('SHA256')
    await mac.init(macKey)
    await mac.update({ data: PteIMResponseCrypto.join(secret, PteIMResponseCrypto.utf8(label)) })
    const material = (await mac.doFinal()).data
    return await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: material })
  }

  static async aesGcmEncrypt(key: cryptoFramework.SymKey, nonce: Uint8Array, plaintext: Uint8Array, aad: string): Promise<Uint8Array> {
    const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7')
    const parameters: cryptoFramework.GcmParamsSpec = {
      algName: 'AES256|GCM|PKCS7', iv: { data: nonce }, aad: { data: PteIMResponseCrypto.utf8(aad) }, authTag: { data: new Uint8Array(0) },
    }
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, parameters)
    const encrypted = (await cipher.doFinal({ data: plaintext })).data
    return encrypted
  }

  static async aesGcmDecrypt(key: cryptoFramework.SymKey, nonce: Uint8Array, ciphertextAndTag: Uint8Array, aad: string): Promise<Uint8Array> {
    if (ciphertextAndTag.length <= 16) throw new Error('AES-GCM ciphertext is invalid')
    const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7')
    const contentLength = ciphertextAndTag.length - 16
    const parameters: cryptoFramework.GcmParamsSpec = {
      algName: 'AES256|GCM|PKCS7', iv: { data: nonce }, aad: { data: PteIMResponseCrypto.utf8(aad) }, authTag: { data: ciphertextAndTag.slice(contentLength) },
    }
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, parameters)
    return (await cipher.doFinal({ data: ciphertextAndTag.slice(0, contentLength) })).data
  }

  static async randomBytes(size: number): Promise<Uint8Array> {
    return (await cryptoFramework.createRandom().generateRandom(size)).data
  }

  static rawPublicKey(pair: cryptoFramework.KeyPair): Uint8Array {
    const encoded = pair.pubKey.getEncoded().data
    if (encoded.length < 65) throw new Error('invalid P-256 public key')
    const raw = encoded.slice(encoded.length - 65)
    if (raw[0] !== 4) throw new Error('P-256 public key must be uncompressed')
    return raw
  }

  static async publicKeyFromRaw(raw: Uint8Array): Promise<cryptoFramework.PubKey> {
    if (raw.length !== 65 || raw[0] !== 4) throw new Error('invalid P-256 public key')
    const der = PteIMResponseCrypto.join(PteIMResponseCrypto.p256SPKIPrefix, raw)
    return (await cryptoFramework.createAsyKeyGenerator('ECC256').convertKey({ data: der }, null)).pubKey
  }

  static base64URL(value: Uint8Array): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    let output = ''
    for (let index = 0; index < value.length; index += 3) {
      const a = value[index]; const b = index + 1 < value.length ? value[index + 1] : -1; const c = index + 2 < value.length ? value[index + 2] : -1
      output += chars.charAt(a >> 2) + chars.charAt(((a & 3) << 4) | (b < 0 ? 0 : b >> 4))
      if (b >= 0) output += chars.charAt(((b & 15) << 2) | (c < 0 ? 0 : c >> 6))
      if (c >= 0) output += chars.charAt(c & 63)
    }
    return output
  }

  static base64URLDecode(value: string): Uint8Array {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    const bytes: number[] = []
    for (let index = 0; index < value.length; index += 4) {
      const a = chars.indexOf(value[index]); const b = chars.indexOf(value[index + 1]); const c = index + 2 < value.length ? chars.indexOf(value[index + 2]) : -1; const d = index + 3 < value.length ? chars.indexOf(value[index + 3]) : -1
      if (a < 0 || b < 0 || c < -1 || d < -1) throw new Error('invalid base64url')
      bytes.push((a << 2) | (b >> 4)); if (c >= 0) bytes.push(((b & 15) << 4) | (c >> 2)); if (d >= 0) bytes.push(((c & 3) << 6) | d)
    }
    return new Uint8Array(bytes)
  }

  static utf8(value: string): Uint8Array { return util.TextEncoder.create('utf-8').encodeInto(value) }
  static join(first: Uint8Array, second: Uint8Array): Uint8Array { const output = new Uint8Array(first.length + second.length); output.set(first); output.set(second, first.length); return output }
  private static stringValue(value: Record<string, Object>, key: string): string { const item = value[key]; return item === undefined || item === null ? '' : item.toString() }
  private static numberValue(value: Record<string, Object>, key: string): number { const item = value[key]; return item === undefined || item === null ? 0 : Number(item.toString()) }
}
