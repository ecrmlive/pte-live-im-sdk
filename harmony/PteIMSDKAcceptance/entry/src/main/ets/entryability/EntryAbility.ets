import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import http from '@ohos.net.http'
import {
  PteIMBaseConfig,
  PteIMLanguage,
  PteIMListener,
  PteIMLoginConfig,
  PteIMMessage,
  PteIMSDK,
  PteIMSceneClient,
  PteIMSceneCredentials,
  PteIMSceneEnterOptions,
  PteIMThemeMode,
  PteIMResponseCrypto,
} from '@ptelive/pte-im-sdk'

type WireObject = Record<string, Object>

class Credential {
  sdkAppId: number = 0
  userId: string = ''
  userSig: string = ''
  expireAt: number = 0
}

class ChatProbe extends PteIMListener {
  connected: boolean = false
  acked: boolean = false
  receivedText: string = ''
  errors: string[] = []

  onConnectionChanged(connected: boolean): void { this.connected = connected }
  onMessage(message: PteIMMessage): void { this.receivedText = message.text }
  onMessageStateChanged(_clientMsgId: string, state: string): void { if (state === 'sent') this.acked = true }
  onError(error: Error): void { this.errors.push(error.message) }
}

/** Minimal SDK-only test harness. It creates ordinary test-server identities
 * at runtime and never imports, navigates to, or reuses the Demo application. */
class AcceptanceRunner {
  private apiDomain: string = 'https://api-im.qxkejiwl.top'
  // Set by CI / local harness before launch; never commit a real secret.
  private sdkAppId: string = ''
  private appSecret: string = ''

  async run(context: Context): Promise<void> {
    let sender: PteIMSDK | null = null
    let receiver: PteIMSDK | null = null
    try {
      const senderCredential = await this.issueUserSig('98000003', 'harmony-sdk-chat-sender')
      const receiverCredential = await this.issueUserSig('98000004', 'harmony-sdk-chat-receiver')
      sender = await this.login(context, senderCredential)
      receiver = await this.login(context, receiverCredential)
      const senderProbe = new ChatProbe()
      const receiverProbe = new ChatProbe()
      sender.addListener(senderProbe)
      receiver.addListener(receiverProbe)
      sender.start()
      receiver.start()

      this.phase('chat-connect')
      await this.waitFor(() => sender !== null && receiver !== null && sender.isConnected() && receiver.isConnected(), 'chat WSS connect')
      this.phase('chat-e2ee')
      const conversation = await sender.openSingleConversation(98000004)
      const text = `harmony-sdk-e2e-${Date.now()}`
      await sender.sendText(conversation.id.toString(), text)
      await this.waitFor(
        () => senderProbe.acked && receiverProbe.receivedText === text,
        `E2EE chat ACK and receive (acked=${senderProbe.acked}, received=${receiverProbe.receivedText === text}, senderErrors=${senderProbe.errors.join('|')}, receiverErrors=${receiverProbe.errors.join('|')})`,
      )
      this.assert(senderProbe.errors.length === 0 && receiverProbe.errors.length === 0, `chat listener error: ${senderProbe.errors.join('|')} ${receiverProbe.errors.join('|')}`)

      this.phase('social')
      await sender.follow(98000004, 'sdk-e2e')
      const follows = await sender.fetchFollows('', 100)
      this.assert(follows.list.some((item) => item.userId === '98000004'), 'social follow contract failed')
      await sender.unfollow(98000004)
      this.phase('commerce')
      const capabilities = await sender.commerce.capabilities()
      this.assert(this.boolValue(capabilities, 'gifts') && this.boolValue(capabilities, 'backpack') && this.boolValue(capabilities, 'orders'), 'commerce capabilities contract failed')
      await sender.commerce.gifts(); await sender.commerce.wallet(); await sender.commerce.backpack(); await sender.commerce.orders()

      for (const scene of ['show', 'voice', 'shop']) {
        this.phase(`scene-${scene}`)
        const client = await this.enterScene(sender, senderCredential, scene, `sdk-e2e-${scene}`)
        client.disconnect()
      }
      this.phase('scene-sports')
      const sportsCredential = await this.issueUserSig('98000003', 'harmony-sdk-sports', 20001)
      const sports = await this.enterScene(sender, sportsCredential, 'sports', 'sports-live-910001')
      sports.disconnect()
      console.info('PTE_IM_SDK_ACCEPTANCE:PASS')
    } catch (error) {
      console.error(`PTE_IM_SDK_ACCEPTANCE:FAIL ${String(error)}`)
    } finally {
      if (sender !== null) sender.stop()
      if (receiver !== null) receiver.stop()
    }
  }

  private async login(context: Context, credential: Credential): Promise<PteIMSDK> {
    // Public api/wss/cos/commerce defaults; override constructor args when needed.
    const base = new PteIMBaseConfig()
    base.themeMode = PteIMThemeMode.SYSTEM
    base.language = PteIMLanguage.EN_US
    return await PteIMSDK.configure(context, base).login(new PteIMLoginConfig(credential.sdkAppId, credential.userId, credential.userSig, credential.expireAt), false)
  }

  private async enterScene(sdk: PteIMSDK, credential: Credential, scene: string, roomId: string): Promise<PteIMSceneClient> {
    const credentials = new PteIMSceneCredentials()
    credentials.sdkAppId = credential.sdkAppId.toString()
    credentials.userId = credential.userId
    credentials.userSig = credential.userSig
    credentials.expireAt = credential.expireAt
    const client = sdk.createSceneClient(credentials)
    const options = new PteIMSceneEnterOptions()
    options.scene = scene as 'show' | 'voice' | 'shop' | 'sports'
    options.roomId = roomId
    const entered = await client.enter(options)
    this.assert(entered.scene === options.scene && entered.roomId === roomId, `${scene} scene enter contract failed`)
    return client
  }

  private async issueUserSig(userId: string, deviceId: string, appId: number = 10001): Promise<Credential> {
    const sdkAppId = this.sdkAppId.trim().length > 0 ? this.sdkAppId.trim() : (1400000000 + appId).toString()
    this.assert(this.appSecret.trim().length > 0, 'AcceptanceRunner.appSecret (PTE_IM_TEST_APP_SECRET) is required for login UserSig issuance')
    const request = http.createHttp()
    try {
      const responseKey = await PteIMResponseCrypto.createRequestKey()
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'app_id': sdkAppId,
        'app_secret': this.appSecret.trim(),
        'X-Pte-Response-Public-Key': responseKey.publicKey,
      }
      const body: WireObject = { 'user_id': userId, 'identifier': userId, 'user_type': 'user', 'device_id': deviceId, 'platform': 'harmony', 'expire': 3600 }
      const response = await request.request(`${this.apiDomain}/api/v1/im/usersig`, { method: http.RequestMethod.POST, header: headers, extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000 })
      this.assert(response.responseCode === 200, `UserSig HTTP ${response.responseCode}`)
      const root = await PteIMResponseCrypto.decryptResponse(JSON.parse(response.result.toString()) as WireObject, responseKey)
      this.assert(this.numberValue(root, 'code') === 1, 'UserSig response rejected')
      const data = root['data'] as WireObject
      const credential = new Credential()
      credential.sdkAppId = this.numberValue(data, 'sdk_app_id')
      credential.userId = this.stringValue(data, 'user_id')
      credential.userSig = this.stringValue(data, 'user_sig')
      credential.expireAt = this.numberValue(data, 'expire_at')
      this.assert(credential.sdkAppId > 0 && credential.userId.length > 0 && credential.userSig.length > 0 && credential.expireAt > 0, 'UserSig payload invalid')
      return credential
    } finally { request.destroy() }
  }

  private async waitFor(condition: () => boolean, label: string, timeoutMs: number = 30000): Promise<void> {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
      if (condition()) return
      await new Promise<void>((resolve) => setTimeout(resolve, 100))
    }
    this.assert(condition(), `${label} timed out`)
  }

  private assert(condition: boolean, message: string): void { if (!condition) throw new Error(message) }
  private phase(name: string): void { console.info(`PTE_IM_SDK_ACCEPTANCE:PHASE ${name}`) }
  private stringValue(value: WireObject, key: string): string { const item = value[key]; return item === undefined || item === null ? '' : item.toString() }
  private numberValue(value: WireObject, key: string): number { return Number(this.stringValue(value, key)) }
  private boolValue(value: WireObject, key: string): boolean { return this.stringValue(value, key) === 'true' }
}

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    void new AcceptanceRunner().run(this.context)
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index')
  }
}
