import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import util from '@ohos.util'
import { PteIMLoginConfig, PteIMMessage } from './IMModels'
import { PteIMRdbStore } from './PteIMRdbStore'
import { PteIMResponseCrypto } from './PteIMResponseCrypto'

type WireObject = Record<string, Object>
type PteIME2EERequest = (path: string, body: WireObject) => Promise<Object>

interface PteIME2EERegistration extends WireObject { app_id: number; user_id: number; device_id: string; public_key: string; algorithm: string }
interface PteIME2EEDeviceListRequest extends WireObject { app_id: number; user_id: number; conversation_id: number }
interface PteIME2EEUserRecipient extends WireObject { user_id: number; device_id: string }
interface PteIME2EEAuditRecipient extends WireObject { key_id: string }
interface PteIME2EEEnvelope extends WireObject { version: number; algorithm: string; ciphertext: string; nonce: string; recipients: Object[] }

class PteIME2EEIdentity {
  pair: cryptoFramework.KeyPair
  deviceId: string

  constructor(pair: cryptoFramework.KeyPair, deviceId: string) {
    this.pair = pair
    this.deviceId = deviceId
  }
}

/**
 * P-256/A256GCM message envelopes for HarmonyOS. The identity's private
 * material stays in the encrypted account database; only the public point is
 * sent to api-im. UserSig is never persisted by this class.
 */
export class PteIME2EE {
  private static readonly algorithm: string = 'P-256/A256GCM'
  private static readonly messageAAD: string = 'pte-live-im-message-v1'
  private static readonly wrapAAD: string = 'pte-live-im-audit-wrap-v1'
  private identityValue: PteIME2EEIdentity | null = null
  private login: PteIMLoginConfig
  private store: PteIMRdbStore

  constructor(login: PteIMLoginConfig, store: PteIMRdbStore) { this.login = login; this.store = store }

  async register(request: PteIME2EERequest): Promise<void> {
    try {
      const identity = await this.identity()
      const publicKey = PteIMResponseCrypto.rawPublicKey(identity.pair)
      const body: PteIME2EERegistration = {
        app_id: this.login.sdkAppId, user_id: Number(this.login.userId), device_id: identity.deviceId,
        public_key: PteIMResponseCrypto.base64URL(publicKey), algorithm: PteIME2EE.algorithm,
      }
      await request('/api/v1/chat/e2ee/device/register', body)
    } catch (error) { throw new Error(`PteIM E2EE device registration failed: ${String(error)}`) }
  }

  async encrypt(message: PteIMMessage, request: PteIME2EERequest): Promise<WireObject> {
    try {
      const recipientRequest: PteIME2EEDeviceListRequest = {
        app_id: this.login.sdkAppId, user_id: Number(this.login.userId), conversation_id: Number(message.conversationId),
      }
      const recipientsValue = await request('/api/v1/chat/e2ee/device/list', recipientRequest)
      const auditValue = await request('/api/v1/chat/e2ee/audit-key', {})
      const recipients = recipientsValue as Object[]
      const audit = auditValue as WireObject
      if (!Array.isArray(recipients) || audit === null || audit === undefined) throw new Error('invalid E2EE device response')

      const contentKey = await PteIMResponseCrypto.randomBytes(32)
      const contentNonce = await PteIMResponseCrypto.randomBytes(12)
      const contentSymKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: contentKey })
      const wire = message.toWire()
      const ciphertext = await PteIMResponseCrypto.aesGcmEncrypt(contentSymKey, contentNonce,
        util.TextEncoder.create('utf-8').encodeInto(JSON.stringify(wire.content)), PteIME2EE.messageAAD)
      const packedRecipients: Object[] = []
      for (let index = 0; index < recipients.length; index++) {
        const device = recipients[index] as WireObject
        const recipient: PteIME2EEUserRecipient = {
          user_id: Number(this.stringValue(device, 'user_id')), device_id: this.stringValue(device, 'device_id'),
        }
        packedRecipients.push(await this.wrap(contentKey, this.stringValue(device, 'public_key'), recipient))
      }
      const output: PteIME2EEEnvelope = {
        version: 1, algorithm: PteIME2EE.algorithm, ciphertext: PteIMResponseCrypto.base64URL(ciphertext),
        nonce: PteIMResponseCrypto.base64URL(contentNonce), recipients: packedRecipients,
      }
      if (this.boolValue(audit, 'enabled')) {
        if (this.stringValue(audit, 'algorithm') !== PteIME2EE.algorithm || this.stringValue(audit, 'key_id').length === 0 || this.stringValue(audit, 'public_key').length === 0) throw new Error('unsupported E2EE audit key')
        const auditTarget: PteIME2EEAuditRecipient = { key_id: this.stringValue(audit, 'key_id') }
        const auditRecipient: Object[] = [await this.wrap(contentKey, this.stringValue(audit, 'public_key'), auditTarget)]
        output['audit_recipients'] = auditRecipient
      } else if (this.boolValue(audit, 'required')) {
        throw new Error('E2EE audit recipient is required')
      }
      return output
    } catch (error) { throw new Error(`PteIM E2EE message encryption failed: ${String(error)}`) }
  }

  async decrypt(envelope: WireObject): Promise<WireObject> {
    try {
      if (this.numberValue(envelope, 'version') !== 1 || this.stringValue(envelope, 'algorithm') !== PteIME2EE.algorithm) throw new Error('unsupported E2EE message envelope')
      const identity = await this.identity()
      const entries = envelope['recipients'] as Object[]
      if (!Array.isArray(entries)) throw new Error('E2EE recipients are missing')
      let recipient: WireObject | null = null
      for (let index = 0; index < entries.length; index++) {
        const value = entries[index] as WireObject
        if (this.stringValue(value, 'device_id') === identity.deviceId) { recipient = value; break }
      }
      if (recipient === null) throw new Error('this device is not an E2EE recipient')
      const wrapNonce = PteIMResponseCrypto.base64URLDecode(this.stringValue(recipient, 'nonce'))
      const peer = await PteIMResponseCrypto.publicKeyFromRaw(PteIMResponseCrypto.base64URLDecode(this.stringValue(recipient, 'ephemeral_public_key')))
      const shared = (await cryptoFramework.createKeyAgreement('ECC256').generateSecret(identity.pair.priKey, peer)).data
      const wrapKey = await PteIMResponseCrypto.deriveKey(shared, wrapNonce, PteIME2EE.wrapAAD)
      const contentKey = await PteIMResponseCrypto.aesGcmDecrypt(wrapKey, wrapNonce,
        PteIMResponseCrypto.base64URLDecode(this.stringValue(recipient, 'wrapped_key')), PteIME2EE.wrapAAD)
      if (contentKey.length !== 32) throw new Error('invalid E2EE content key')
      const messageNonce = PteIMResponseCrypto.base64URLDecode(this.stringValue(envelope, 'nonce'))
      const messageKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: contentKey })
      const clear = await PteIMResponseCrypto.aesGcmDecrypt(messageKey, messageNonce,
        PteIMResponseCrypto.base64URLDecode(this.stringValue(envelope, 'ciphertext')), PteIME2EE.messageAAD)
      return JSON.parse(util.TextDecoder.create('utf-8').decodeToString(clear)) as WireObject
    } catch (error) { throw new Error(`PteIM E2EE message decryption failed: ${String(error)}`) }
  }

  /** An E2EE envelope addressed to a removed device is valid history, but it
   * cannot be decrypted by this newly created local identity. */
  async canDecrypt(envelope: WireObject): Promise<boolean> {
    if (this.numberValue(envelope, 'version') !== 1 || this.stringValue(envelope, 'algorithm') !== PteIME2EE.algorithm) throw new Error('unsupported E2EE message envelope')
    const entries = envelope['recipients'] as Object[]
    if (!Array.isArray(entries)) throw new Error('E2EE recipients are missing')
    const identity = await this.identity()
    for (let index = 0; index < entries.length; index++) {
      if (this.stringValue(entries[index] as WireObject, 'device_id') === identity.deviceId) return true
    }
    return false
  }

  private async wrap(contentKey: Uint8Array, encodedPublicKey: string, recipient: WireObject): Promise<WireObject> {
    try {
      const remote = await PteIMResponseCrypto.publicKeyFromRaw(PteIMResponseCrypto.base64URLDecode(encodedPublicKey))
      const ephemeral = await cryptoFramework.createAsyKeyGenerator('ECC256').generateKeyPair()
      const shared = (await cryptoFramework.createKeyAgreement('ECC256').generateSecret(ephemeral.priKey, remote)).data
      const nonce = await PteIMResponseCrypto.randomBytes(12)
      const key = await PteIMResponseCrypto.deriveKey(shared, nonce, PteIME2EE.wrapAAD)
      const ciphertext = await PteIMResponseCrypto.aesGcmEncrypt(key, nonce, contentKey, PteIME2EE.wrapAAD)
      recipient['ephemeral_public_key'] = PteIMResponseCrypto.base64URL(PteIMResponseCrypto.rawPublicKey(ephemeral))
      recipient['wrapped_key'] = PteIMResponseCrypto.base64URL(ciphertext)
      recipient['nonce'] = PteIMResponseCrypto.base64URL(nonce)
      return recipient
    } catch (error) { throw new Error(`PteIM E2EE recipient key wrapping failed: ${String(error)}`) }
  }

  private async identity(): Promise<PteIME2EEIdentity> {
    try {
      if (this.identityValue !== null) return this.identityValue
      const publicKey = await this.store.metaValue('e2ee_public_key')
      const privateKey = await this.store.metaValue('e2ee_private_key')
      const deviceId = await this.store.metaValue('e2ee_device_id')
      if (publicKey.length > 0 && privateKey.length > 0 && deviceId.length > 0) {
        const pair = await cryptoFramework.createAsyKeyGenerator('ECC256').convertKey({ data: PteIMResponseCrypto.base64URLDecode(publicKey) }, { data: PteIMResponseCrypto.base64URLDecode(privateKey) })
        this.identityValue = new PteIME2EEIdentity(pair, deviceId)
        return this.identityValue
      }
      const pair = await cryptoFramework.createAsyKeyGenerator('ECC256').generateKeyPair()
      const createdId = util.generateRandomUUID()
      await this.store.setMeta('e2ee_public_key', PteIMResponseCrypto.base64URL(pair.pubKey.getEncoded().data))
      await this.store.setMeta('e2ee_private_key', PteIMResponseCrypto.base64URL(pair.priKey.getEncoded().data))
      await this.store.setMeta('e2ee_device_id', createdId)
      this.identityValue = new PteIME2EEIdentity(pair, createdId)
      return this.identityValue
    } catch (error) { throw new Error(`PteIM E2EE identity initialization failed: ${String(error)}`) }
  }

  private stringValue(value: WireObject, key: string): string { const item = value[key]; return item === undefined || item === null ? '' : item.toString() }
  private numberValue(value: WireObject, key: string): number { return Number(this.stringValue(value, key)) }
  private boolValue(value: WireObject, key: string): boolean { return this.stringValue(value, key) === 'true' }
}
