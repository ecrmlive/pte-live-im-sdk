import webSocket from '@ohos.net.webSocket'
import util from '@ohos.util'
import {
  RoomSeqTracker,
  eventTypeFromFrame,
  parseLivePayload,
  readEnvelope,
  type PteIMLiveCatchUpSource,
  type PteIMLiveEventEnvelope,
} from './RoomSeqTracker'

type WireObject = Record<string, Object>
export type PteIMSceneKind = 'show' | 'voice' | 'shop' | 'sports'

export class PteIMSceneCredentials {
  wsUrl: string = ''
  sdkAppId: string = ''
  userId: string = ''
  userSig: string = ''
  expireAt?: number
}

export class PteIMSceneEnterOptions {
  scene: PteIMSceneKind = 'show'
  roomId: string = ''
  extend?: string
  catchUp?: PteIMLiveCatchUpSource
  enterTimeoutMs?: number
}

export class PteIMSceneEntered {
  scene: PteIMSceneKind = 'show'
  roomId: string = ''
  groupName: string = ''
  requestId: string = ''
}

export class PteIMSceneUserSigRenewal {
  userSig: string = ''
  expireAt?: number
}

export class PteIMSceneEnterFailed {
  scene: PteIMSceneKind = 'show'
  roomId: string = ''
  message: string = ''
}

export interface PteIMSceneListener {
  onConnectionChanged?: (connected: boolean) => void
  onEntered?: (info: PteIMSceneEntered) => void
  onEnterFailed?: (info: PteIMSceneEnterFailed) => void
  onEvent?: (eventType: string, payload: WireObject, envelope: PteIMLiveEventEnvelope) => void
  onError?: (message: string) => void
}

class PteIMSceneActiveSession {
  scene: PteIMSceneKind = 'show'
  roomId: string = ''
  extend?: string
  catchUp?: PteIMLiveCatchUpSource
}

class PteIMScenePendingEnter {
  requestId: string = ''
  scene: PteIMSceneKind = 'show'
  roomId: string = ''
  timer: number = -1
  resolve: () => void = () => {}
  reject: (error: Error) => void = () => {}
}

/** Independent scene WSS client (show / voice / shop / sports). Does not share chat socket. */
export class PteIMSceneClient {
  private credentials: PteIMSceneCredentials
  private socket: webSocket.WebSocket | null = null
  private stopped: boolean = true
  private handshaken: boolean = false
  private reconnectTimer: number = -1
  private reconnectAttempt: number = 0
  private readonly listeners: PteIMSceneListener[] = []
  private tracker: RoomSeqTracker = new RoomSeqTracker(0)
  private active: PteIMSceneActiveSession | null = null
  private pendingEnter: PteIMScenePendingEnter | null = null
  private catchUpBusy: boolean = false

  constructor(credentials: PteIMSceneCredentials) {
    if (credentials.wsUrl.length === 0 || credentials.sdkAppId.length === 0 ||
      credentials.userId.length === 0 || credentials.userSig.length === 0) {
      throw new Error('PTE IM Scene 凭证不完整')
    }
    this.credentials = credentials
  }

  addListener(listener: PteIMSceneListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener)
    if (this.socket !== null && this.handshaken) listener.onConnectionChanged?.(true)
  }

  removeListener(listener: PteIMSceneListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) this.listeners.splice(index, 1)
  }

  getLastRoomSeq(): number {
    return this.tracker.getLastRoomSeq()
  }

  isConnected(): boolean {
    return this.socket !== null && this.handshaken
  }

  renewUserSig(credentials: PteIMSceneUserSigRenewal): void {
    if (credentials.userSig.length === 0) throw new Error('PTE IM UserSig 不能为空')
    this.credentials.userSig = credentials.userSig
    this.credentials.expireAt = credentials.expireAt
  }

  async connect(): Promise<void> {
    this.stopped = false
    if (this.socket !== null && this.handshaken) return
    await this.openSocket()
  }

  async enter(options: PteIMSceneEnterOptions): Promise<PteIMSceneEntered> {
    assertSceneRoomId(options.scene, options.roomId)
    const active = new PteIMSceneActiveSession()
    active.scene = options.scene
    active.roomId = options.roomId.trim()
    active.extend = options.extend
    active.catchUp = options.catchUp
    this.active = active
    await this.connect()
    if (options.catchUp !== undefined) {
      await this.tracker.catchUp(options.catchUp, (eventType: string, payload: WireObject) => this.emitEvent(eventType, payload))
    }
    const timeoutMs = options.enterTimeoutMs !== undefined ? options.enterTimeoutMs : 15000
    return await this.sendEnter(timeoutMs)
  }

  leave(): void {
    const active = this.active
    if (active !== null && this.socket !== null && this.handshaken) {
      this.sendRaw({
        'action': 'scene.leave',
        'request_id': sceneRequestId(),
        'scene': active.scene,
        'room_id': active.roomId,
      })
    }
    this.active = null
    this.clearPendingEnter('已离房')
  }

  disconnect(): void {
    this.stopped = true
    this.active = null
    this.clearPendingEnter('已断开')
    if (this.reconnectTimer >= 0) clearTimeout(this.reconnectTimer)
    this.reconnectTimer = -1
    const socket = this.socket
    this.socket = null
    this.handshaken = false
    if (socket !== null) {
      try { socket.close() } catch (_error) { /* ignore */ }
    }
    this.notifyConnection(false)
  }

  private openSocket(): Promise<void> {
    if (this.socket !== null && this.handshaken) return Promise.resolve()
    return new Promise((resolve, reject) => {
      if (this.socket !== null) {
        try { this.socket.close() } catch (_error) { /* ignore */ }
        this.socket = null
      }
      this.handshaken = false
      const socket = webSocket.createWebSocket()
      this.socket = socket
      let settled = false
      const timer = setTimeout(() => {
        if (settled) return
        settled = true
        reject(new Error('Scene WSS 握手超时'))
        try { socket.close() } catch (_error) { /* ignore */ }
      }, 15000)
      socket.on('open', () => { /* wait for handshake code=0 */ })
      socket.on('message', (_error: Error | null, value: string | ArrayBuffer) => {
        const raw = typeof value === 'string' ? value : util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(value))
        void this.handleFrame(raw, () => {
          if (settled) return
          settled = true
          clearTimeout(timer)
          resolve()
        })
      })
      socket.on('error', (error: Error) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        this.emitError('Scene WSS 连接异常')
        reject(error instanceof Error ? error : new Error('Scene WSS 连接异常'))
      })
      socket.on('close', () => {
        if (this.socket !== socket) return
        this.socket = null
        this.handshaken = false
        this.notifyConnection(false)
        this.scheduleReconnect()
      })
      socket.connect(this.webSocketURL(), (error: Error) => {
        if (error) {
          if (settled) return
          settled = true
          clearTimeout(timer)
          this.emitError(error.message)
          reject(error)
        }
      })
    })
  }

  private async handleFrame(raw: string, onHandshake?: () => void): Promise<void> {
    let frame: WireObject
    try {
      frame = JSON.parse(raw) as WireObject
    } catch (_error) {
      this.emitError('Scene 帧解析失败')
      return
    }

    const code = frame['code']
    if (!this.handshaken && Number(code) === 0 && frame['data'] !== undefined) {
      this.handshaken = true
      this.reconnectAttempt = 0
      this.notifyConnection(true)
      onHandshake?.()
      return
    }

    const dataRaw = frame['data']
    let data: WireObject | null = null
    if (typeof dataRaw === 'string') {
      try { data = JSON.parse(dataRaw) as WireObject } catch (_error) { data = null }
    } else {
      data = asRecord(dataRaw)
    }

    const msg = stringOf(frame['msg'])
    const dataType = data !== null ? stringOf(data['type']) : ''
    if (dataType === 'scene.ack' || msg.indexOf('scene') >= 0) {
      const ok = data !== null && (data['ok'] === true || data['ok'] === 'true')
      const requestId = data !== null ? stringOf(data['request_id'] ?? data['requestId']) : ''
      const scene = (data !== null ? stringOf(data['scene']) : '') || (this.active !== null ? this.active.scene : 'show') as PteIMSceneKind
      const roomId = (data !== null ? stringOf(data['room_id'] ?? data['roomId']) : '') ||
        (this.active !== null ? this.active.roomId : '')
      if (this.pendingEnter !== null &&
        (this.pendingEnter.requestId.length === 0 || requestId.length === 0 || requestId === this.pendingEnter.requestId)) {
        const pending = this.pendingEnter
        this.pendingEnter = null
        if (pending.timer >= 0) clearTimeout(pending.timer)
        if (ok) {
          const groupName = (data !== null ? stringOf(data['group_name'] ?? data['groupName']) : '') ||
            groupNameForScene(scene, roomId)
          const entered = new PteIMSceneEntered()
          entered.scene = scene
          entered.roomId = roomId
          entered.groupName = groupName
          entered.requestId = pending.requestId
          this.listeners.forEach((listener: PteIMSceneListener) => listener.onEntered?.(entered))
          pending.resolve()
        } else {
          const message = msg.length > 0 ? msg : 'scene.enter 失败'
          const failed = new PteIMSceneEnterFailed()
          failed.scene = scene
          failed.roomId = roomId
          failed.message = message
          this.listeners.forEach((listener: PteIMSceneListener) => listener.onEnterFailed?.(failed))
          pending.reject(new Error(message))
        }
      }
      return
    }

    const parsed = eventTypeFromFrame(frame)
    if (parsed.eventType === undefined || parsed.eventType.length === 0 || parsed.payload === undefined) return
    if (this.tracker.needsCatchUp(parsed.payload)) {
      const catchUp = this.active?.catchUp
      if (catchUp !== undefined && !this.catchUpBusy) {
        this.catchUpBusy = true
        try {
          await this.tracker.catchUp(catchUp, (eventType: string, row: WireObject) => this.emitEvent(eventType, row))
        } catch (error) {
          this.emitError(error instanceof Error ? error.message : 'Scene 补漏失败')
        } finally {
          this.catchUpBusy = false
        }
      }
      return
    }
    if (this.tracker.accept(parsed.payload)) this.emitEvent(parsed.eventType, parsed.payload)
  }

  private sendEnter(timeoutMs: number): Promise<PteIMSceneEntered> {
    const active = this.active
    if (active === null) return Promise.reject(new Error('未设置进房参数'))
    if (this.socket === null || !this.handshaken) return Promise.reject(new Error('Scene 未连接'))
    const requestId = sceneRequestId()
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pendingEnter === null || this.pendingEnter.requestId !== requestId) return
        this.pendingEnter = null
        const message = 'scene.enter 超时'
        const failed = new PteIMSceneEnterFailed()
        failed.scene = active.scene
        failed.roomId = active.roomId
        failed.message = message
        this.listeners.forEach((listener: PteIMSceneListener) => listener.onEnterFailed?.(failed))
        reject(new Error(message))
      }, timeoutMs)
      const pending = new PteIMScenePendingEnter()
      pending.requestId = requestId
      pending.scene = active.scene
      pending.roomId = active.roomId
      pending.timer = timer
      pending.resolve = () => {
        const entered = new PteIMSceneEntered()
        entered.scene = active.scene
        entered.roomId = active.roomId
        entered.groupName = groupNameForScene(active.scene, active.roomId)
        entered.requestId = requestId
        resolve(entered)
      }
      pending.reject = reject
      this.pendingEnter = pending
      const body: WireObject = {
        'action': 'scene.enter',
        'request_id': requestId,
        'scene': active.scene,
        'room_id': active.roomId,
      }
      if (active.extend !== undefined && active.extend.length > 0) body['extend'] = active.extend
      this.sendRaw(body)
    })
  }

  private sendRaw(body: WireObject): void {
    if (this.socket === null || !this.handshaken) return
    this.socket.send(JSON.stringify(body), (error: Error) => {
      if (error !== null && error !== undefined) this.emitError(error.message)
    })
  }

  private scheduleReconnect(): void {
    if (this.stopped || this.reconnectTimer >= 0) return
    const delay = Math.min(1000 * Math.pow(2, Math.min(this.reconnectAttempt, 5)), 30000)
    this.reconnectAttempt += 1
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1
      void this.rejoin()
    }, delay)
  }

  private async rejoin(): Promise<void> {
    if (this.stopped) return
    try {
      await this.openSocket()
      if (this.active !== null) {
        if (this.active.catchUp !== undefined) {
          await this.tracker.catchUp(this.active.catchUp,
            (eventType: string, payload: WireObject) => this.emitEvent(eventType, payload))
        }
        await this.sendEnter(15000)
      }
    } catch (error) {
      this.emitError(error instanceof Error ? error.message : 'Scene 重连失败')
      this.scheduleReconnect()
    }
  }

  private clearPendingEnter(message: string): void {
    if (this.pendingEnter === null) return
    if (this.pendingEnter.timer >= 0) clearTimeout(this.pendingEnter.timer)
    const pending = this.pendingEnter
    this.pendingEnter = null
    pending.reject(new Error(message))
  }

  private emitEvent(eventType: string, payload: WireObject): void {
    const envelope = readEnvelope(payload)
    this.listeners.forEach((listener: PteIMSceneListener) => listener.onEvent?.(eventType, payload, envelope))
  }

  private notifyConnection(connected: boolean): void {
    this.listeners.forEach((listener: PteIMSceneListener) => listener.onConnectionChanged?.(connected))
  }

  private emitError(message: string): void {
    this.listeners.forEach((listener: PteIMSceneListener) => listener.onError?.(message))
  }

  private webSocketURL(): string {
    const separator = this.credentials.wsUrl.indexOf('?') >= 0 ? '&' : '?'
    return this.credentials.wsUrl + separator +
      'sdkAppID=' + encodeURIComponent(this.credentials.sdkAppId) +
      '&identifier=' + encodeURIComponent(this.credentials.userId) +
      '&userSig=' + encodeURIComponent(this.credentials.userSig)
  }
}

export function groupNameForScene(scene: PteIMSceneKind, roomId: string): string {
  if (scene === 'shop') return `live:${roomId}`
  if (scene === 'sports') return `sports:${roomId}`
  return `${scene}:${roomId}`
}

export function assertSceneRoomId(scene: PteIMSceneKind, roomId: string): void {
  const id = roomId.trim()
  if (id.length === 0) throw new Error('roomId 不能为空')
  if (scene === 'sports' && !/^sports-live-\d+$/.test(id)) {
    throw new Error('体育房间 roomId 必须为 sports-live-{数字id}')
  }
}

function stringOf(value: Object | null | undefined): string {
  if (value === null || value === undefined) return ''
  return value.toString()
}

function asRecord(value: Object | null | undefined): WireObject | null {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return null
  return value as WireObject
}

function sceneRequestId(): string {
  return `${Date.now()}-${Math.random()}`
}

export { parseLivePayload, readEnvelope, eventTypeFromFrame, RoomSeqTracker }
export type { PteIMLiveCatchUpSource, PteIMLiveEventEnvelope }
