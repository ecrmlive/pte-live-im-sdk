import {
  eventTypeFromFrame,
  parseLivePayload,
  readEnvelope,
  RoomSeqTracker,
  type LiveCatchUpSource,
  type LiveEventEnvelope,
} from './tracker.ts'
import { assertSceneRoomId, groupNameForScene, type PteIMSceneKind } from './types.ts'

export interface PteIMSceneCredentials {
  wsUrl: string
  sdkAppId: string
  userId: string
  userSig: string
  expireAt?: number
}

export interface PteIMSceneEnterOptions {
  scene: PteIMSceneKind
  roomId: string
  /** JSON string for shop role/nickName; optional elsewhere. */
  extend?: string
  catchUp?: LiveCatchUpSource
  /** Milliseconds to wait for scene.ack. Default 15000. */
  enterTimeoutMs?: number
}

export interface PteIMSceneEntered {
  scene: PteIMSceneKind
  roomId: string
  groupName: string
  requestId: string
}

export interface PteIMSceneListener {
  onConnectionChanged?: (connected: boolean) => void
  onEntered?: (info: PteIMSceneEntered) => void
  onEnterFailed?: (info: { scene: PteIMSceneKind; roomId: string; message: string }) => void
  onEvent?: (eventType: string, payload: Record<string, unknown>, envelope: LiveEventEnvelope) => void
  onError?: (message: string) => void
}

/**
 * Independent scene WSS client (show / voice / shop / sports).
 * Does not share a socket with chat; host supplies room-scoped UserSig and catch-up HTTP.
 */
export class PteIMSceneClient {
  private credentials: PteIMSceneCredentials
  private socket: WebSocket | null = null
  private stopped = true
  private handshaken = false
  private reconnectTimer: number | null = null
  private reconnectAttempt = 0
  private listeners = new Set<PteIMSceneListener>()
  private tracker = new RoomSeqTracker(0)
  /** roomSeq is scoped to a room; never carry a watermark into another room. */
  private trackerRoomKey: string | null = null
  private active: { scene: PteIMSceneKind; roomId: string; extend?: string; catchUp?: LiveCatchUpSource } | null = null
  private pendingEnter: {
    requestId: string
    scene: PteIMSceneKind
    roomId: string
    timer: number
    resolve: () => void
    reject: (error: Error) => void
  } | null = null
  private catchUpBusy = false

  constructor(credentials: PteIMSceneCredentials) {
    if (!credentials.wsUrl || !credentials.sdkAppId || !credentials.userId || !credentials.userSig) {
      throw new Error('PTE IM Scene 凭证不完整')
    }
    this.credentials = { ...credentials }
  }

  addListener(listener: PteIMSceneListener) {
    this.listeners.add(listener)
    if (this.socket?.readyState === WebSocket.OPEN) listener.onConnectionChanged?.(true)
  }

  removeListener(listener: PteIMSceneListener) {
    this.listeners.delete(listener)
  }

  getLastRoomSeq() {
    return this.tracker.getLastRoomSeq()
  }

  isConnected() {
    return this.socket?.readyState === WebSocket.OPEN
  }

  renewUserSig(credentials: Pick<PteIMSceneCredentials, 'userSig' | 'expireAt'>) {
    if (!credentials.userSig) throw new Error('PTE IM UserSig 不能为空')
    this.credentials.userSig = credentials.userSig
    this.credentials.expireAt = credentials.expireAt
  }

  async connect() {
    this.stopped = false
    if (this.socket?.readyState === WebSocket.OPEN && this.handshaken) return
    await this.openSocket()
  }

  async enter(options: PteIMSceneEnterOptions): Promise<PteIMSceneEntered> {
    assertSceneRoomId(options.scene, options.roomId)
    const roomId = String(options.roomId).trim()
    const roomKey = `${options.scene}:${roomId}`
    if (this.trackerRoomKey !== roomKey) {
      this.tracker = new RoomSeqTracker(0)
      this.trackerRoomKey = roomKey
    }
    this.active = {
      scene: options.scene,
      roomId,
      extend: options.extend,
      catchUp: options.catchUp,
    }
    await this.connect()
    if (options.catchUp) {
      await this.tracker.catchUp(options.catchUp, (eventType, payload) => this.emitEvent(eventType, payload))
    }
    return this.sendEnter(options.enterTimeoutMs ?? 15_000)
  }

  async leave() {
    const active = this.active
    if (active && this.socket?.readyState === WebSocket.OPEN) {
      this.sendRaw({
        action: 'scene.leave',
        request_id: crypto.randomUUID(),
        scene: active.scene,
        room_id: active.roomId,
      })
    }
    this.active = null
    this.clearPendingEnter('已离房')
  }

  disconnect() {
    this.stopped = true
    this.active = null
    this.clearPendingEnter('已断开')
    if (this.reconnectTimer !== null) window.clearTimeout(this.reconnectTimer)
    this.reconnectTimer = null
    const socket = this.socket
    this.socket = null
    this.handshaken = false
    if (socket) socket.close()
    this.notifyConnection(false)
  }

  private openSocket(): Promise<void> {
    if (this.socket?.readyState === WebSocket.OPEN && this.handshaken) return Promise.resolve()
    return new Promise((resolve, reject) => {
      if (this.socket) {
        try { this.socket.close() } catch { /* ignore */ }
        this.socket = null
      }
      this.handshaken = false
      const url = new URL(this.credentials.wsUrl)
      url.searchParams.set('sdkAppID', this.credentials.sdkAppId)
      url.searchParams.set('identifier', this.credentials.userId)
      url.searchParams.set('userSig', this.credentials.userSig)
      const socket = new WebSocket(url.toString())
      this.socket = socket
      const timer = window.setTimeout(() => {
        reject(new Error('Scene WSS 握手超时'))
        try { socket.close() } catch { /* ignore */ }
      }, 15_000)
      socket.onopen = () => {
        /* wait for handshake frame code=0 before resolve */
      }
      socket.onmessage = (event) => {
        void this.handleFrame(String(event.data), () => {
          window.clearTimeout(timer)
          resolve()
        })
      }
      socket.onerror = () => {
        window.clearTimeout(timer)
        this.emitError('Scene WSS 连接异常')
        reject(new Error('Scene WSS 连接异常'))
      }
      socket.onclose = () => {
        if (this.socket !== socket) return
        this.socket = null
        this.handshaken = false
        this.notifyConnection(false)
        this.scheduleReconnect()
      }
    })
  }

  private async handleFrame(raw: string, onHandshake?: () => void) {
    let frame: Record<string, unknown>
    try {
      frame = JSON.parse(raw) as Record<string, unknown>
    } catch {
      this.emitError('Scene 帧解析失败')
      return
    }

    if (!this.handshaken && Number(frame.code) === 0 && frame.data) {
      this.handshaken = true
      this.reconnectAttempt = 0
      this.notifyConnection(true)
      onHandshake?.()
      return
    }

    const dataRaw = frame.data
    let data: Record<string, unknown> | undefined
    if (typeof dataRaw === 'string') {
      try { data = JSON.parse(dataRaw) as Record<string, unknown> } catch { data = undefined }
    } else if (dataRaw && typeof dataRaw === 'object' && !Array.isArray(dataRaw)) {
      data = dataRaw as Record<string, unknown>
    }

    // `scene.*` is also the social-room event namespace. Treat only an
    // explicit acknowledgement as an enter response, otherwise live events
    // such as `scene.user.enter` are silently swallowed.
    if (data?.type === 'scene.ack' || stringOf(frame.msg) === 'scene.ack') {
      const ok = data?.ok === true || data?.ok === 'true'
      const requestId = stringOf(data?.request_id ?? data?.requestId)
      const scene = (stringOf(data?.scene) || this.active?.scene || 'show') as PteIMSceneKind
      const roomId = stringOf(data?.room_id ?? data?.roomId) || this.active?.roomId || ''
      if (this.pendingEnter && (!this.pendingEnter.requestId || !requestId || requestId === this.pendingEnter.requestId)) {
        const pending = this.pendingEnter
        this.pendingEnter = null
        window.clearTimeout(pending.timer)
        if (ok) {
          const groupName = stringOf(data?.group_name ?? data?.groupName) || groupNameForScene(scene, roomId)
          this.listeners.forEach((l) => l.onEntered?.({ scene, roomId, groupName, requestId: pending.requestId }))
          pending.resolve()
        } else {
          const message = stringOf(frame.msg) || 'scene.enter 失败'
          this.listeners.forEach((l) => l.onEnterFailed?.({ scene, roomId, message }))
          pending.reject(new Error(message))
        }
      }
      return
    }

    const { eventType, payload } = eventTypeFromFrame(frame)
    if (!eventType || !payload) return
    if (this.tracker.needsCatchUp(payload)) {
      const catchUp = this.active?.catchUp
      if (catchUp && !this.catchUpBusy) {
        this.catchUpBusy = true
        try {
          await this.tracker.catchUp(catchUp, (type, row) => this.emitEvent(type, row))
        } catch (error) {
          this.emitError(error instanceof Error ? error.message : 'Scene 补漏失败')
        } finally {
          this.catchUpBusy = false
        }
      }
      return
    }
    if (this.tracker.accept(payload)) this.emitEvent(eventType, payload)
  }

  private sendEnter(timeoutMs: number): Promise<PteIMSceneEntered> {
    const active = this.active
    if (!active) return Promise.reject(new Error('未设置进房参数'))
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN || !this.handshaken) {
      return Promise.reject(new Error('Scene 未连接'))
    }
    const requestId = crypto.randomUUID()
    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => {
        if (this.pendingEnter?.requestId === requestId) {
          this.pendingEnter = null
          const message = 'scene.enter 超时'
          this.listeners.forEach((l) => l.onEnterFailed?.({ scene: active.scene, roomId: active.roomId, message }))
          reject(new Error(message))
        }
      }, timeoutMs)
      this.pendingEnter = {
        requestId,
        scene: active.scene,
        roomId: active.roomId,
        timer,
        resolve: () => resolve({
          scene: active.scene,
          roomId: active.roomId,
          groupName: groupNameForScene(active.scene, active.roomId),
          requestId,
        }),
        reject,
      }
      const body: Record<string, unknown> = {
        action: 'scene.enter',
        request_id: requestId,
        scene: active.scene,
        room_id: active.roomId,
      }
      if (active.extend) body.extend = active.extend
      this.sendRaw(body)
    })
  }

  private sendRaw(body: Record<string, unknown>) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return
    this.socket.send(JSON.stringify(body))
  }

  private scheduleReconnect() {
    if (this.stopped || this.reconnectTimer !== null) return
    const delay = Math.min(1000 * 2 ** Math.min(this.reconnectAttempt, 5), 30_000)
    this.reconnectAttempt += 1
    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectTimer = null
      void this.rejoin()
    }, delay)
  }

  private async rejoin() {
    if (this.stopped) return
    try {
      await this.openSocket()
      if (this.active) {
        if (this.active.catchUp) {
          await this.tracker.catchUp(this.active.catchUp, (eventType, payload) => this.emitEvent(eventType, payload))
        }
        await this.sendEnter(15_000)
      }
    } catch (error) {
      this.emitError(error instanceof Error ? error.message : 'Scene 重连失败')
      this.scheduleReconnect()
    }
  }

  private clearPendingEnter(message: string) {
    if (!this.pendingEnter) return
    window.clearTimeout(this.pendingEnter.timer)
    const pending = this.pendingEnter
    this.pendingEnter = null
    pending.reject(new Error(message))
  }

  private emitEvent(eventType: string, payload: Record<string, unknown>) {
    const envelope = readEnvelope(payload)
    this.listeners.forEach((l) => l.onEvent?.(eventType, payload, envelope))
  }

  private notifyConnection(connected: boolean) {
    this.listeners.forEach((l) => l.onConnectionChanged?.(connected))
  }

  private emitError(message: string) {
    this.listeners.forEach((l) => l.onError?.(message))
  }
}

function stringOf(value: unknown) {
  return value == null ? '' : String(value)
}

export type { LiveCatchUpSource, LiveEventEnvelope }
export { parseLivePayload, readEnvelope, eventTypeFromFrame, RoomSeqTracker }
