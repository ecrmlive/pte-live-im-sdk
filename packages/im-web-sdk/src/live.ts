/**
 * Live-room event helpers (sports.* / shop.*).
 * Canonical protocol: pte-live-im/docs/LIVE_EVENT_PROTOCOL.md
 */

export type LiveEventPriority = 'l1_chat' | 'state' | 'money'

export interface LiveEventEnvelope {
  eventId?: string
  roomSeq?: number
  serverTs?: number
  priority?: LiveEventPriority | string
}

export interface LiveRoomEventRow {
  eventId: string
  eventType: string
  roomSeq: number
  payload: Record<string, unknown>
}

export interface LiveCatchUpPage {
  currentRoomSeq: number
  events: LiveRoomEventRow[]
}

export interface LiveCatchUpSource {
  getCurrentRoomSeq: () => Promise<number>
  fetchEventsAfter: (afterSeq: number, limit?: number) => Promise<LiveCatchUpPage>
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined
  return value as Record<string, unknown>
}

export function parseLivePayload(raw: unknown): Record<string, unknown> | undefined {
  if (typeof raw === 'string') {
    const trimmed = raw.trim()
    if (!trimmed) return undefined
    try {
      return asRecord(JSON.parse(trimmed))
    } catch {
      return undefined
    }
  }
  return asRecord(raw)
}

export function readEnvelope(payload: Record<string, unknown>): LiveEventEnvelope {
  const eventId = typeof payload.eventId === 'string'
    ? payload.eventId
    : typeof payload.event_id === 'string'
      ? payload.event_id
      : undefined
  const roomSeqRaw = payload.roomSeq ?? payload.room_seq
  const roomSeq = typeof roomSeqRaw === 'number'
    ? roomSeqRaw
    : typeof roomSeqRaw === 'string' && roomSeqRaw.trim()
      ? Number(roomSeqRaw)
      : undefined
  const serverTsRaw = payload.serverTs ?? payload.server_ts
  const serverTs = typeof serverTsRaw === 'number'
    ? serverTsRaw
    : typeof serverTsRaw === 'string' && serverTsRaw.trim()
      ? Number(serverTsRaw)
      : undefined
  const priority = typeof payload.priority === 'string' ? payload.priority : undefined
  return { eventId, roomSeq, serverTs, priority }
}

/**
 * Track roomSeq + eventId dedupe for live WSS / catch-up.
 */
export class LiveRoomSeqTracker {
  private lastRoomSeq: number
  private readonly seen = new Set<string>()

  constructor(initialLastRoomSeq = 0) {
    this.lastRoomSeq = initialLastRoomSeq
  }

  getLastRoomSeq() {
    return this.lastRoomSeq
  }

  /** Returns false if duplicate or stale. */
  accept(payload: Record<string, unknown>): boolean {
    const { eventId, roomSeq } = readEnvelope(payload)
    if (eventId && this.seen.has(eventId)) return false
    if (typeof roomSeq === 'number' && roomSeq > 0 && roomSeq <= this.lastRoomSeq) {
      if (eventId) this.seen.add(eventId)
      return false
    }
    if (eventId) {
      this.seen.add(eventId)
      if (this.seen.size > 2000) {
        const drop = [...this.seen].slice(0, 500)
        for (const id of drop) this.seen.delete(id)
      }
    }
    if (typeof roomSeq === 'number' && roomSeq > this.lastRoomSeq) {
      this.lastRoomSeq = roomSeq
    }
    return true
  }

  needsCatchUp(payload: Record<string, unknown>): boolean {
    const { roomSeq } = readEnvelope(payload)
    return typeof roomSeq === 'number' && roomSeq > this.lastRoomSeq + 1
  }

  /**
   * Align watermark / apply gap events before scene.enter or after a seq gap.
   * Fresh enter (last=0): seed from currentRoomSeq without replaying full history.
   */
  async catchUp(
    source: LiveCatchUpSource,
    apply: (eventType: string, payload: Record<string, unknown>) => void,
  ): Promise<void> {
    const current = await source.getCurrentRoomSeq()
    if (this.lastRoomSeq <= 0 && current > 0) {
      this.lastRoomSeq = current
      return
    }
    let after = this.lastRoomSeq
    for (let page = 0; page < 20; page += 1) {
      const { currentRoomSeq, events } = await source.fetchEventsAfter(after, 100)
      for (const row of events) {
        const payload = parseLivePayload(row.payload) ?? {}
        if (!payload.eventId && row.eventId) payload.eventId = row.eventId
        if (!payload.roomSeq && row.roomSeq) payload.roomSeq = row.roomSeq
        if (this.accept(payload)) apply(row.eventType, payload)
        if (row.roomSeq > after) after = row.roomSeq
      }
      if (events.length < 100) {
        if (currentRoomSeq > this.lastRoomSeq) this.lastRoomSeq = currentRoomSeq
        break
      }
    }
  }
}

/** Extract eventType from a PTE group / scene frame. */
export function eventTypeFromFrame(frame: { data?: unknown; msg?: unknown }): {
  eventType?: string
  payload?: Record<string, unknown>
} {
  let envelope: unknown = frame.data
  if (typeof frame.data === 'string') {
    try {
      envelope = JSON.parse(frame.data)
    } catch {
      return {}
    }
  }
  const root = asRecord(envelope)
  if (!root) return {}
  const scene = asRecord(root.scene)
  const payload = parseLivePayload(scene?.payload)
  const eventType = typeof root.event_type === 'string'
    ? root.event_type
    : typeof root.eventType === 'string'
      ? root.eventType
      : typeof frame.msg === 'string'
        ? frame.msg
        : undefined
  return { eventType, payload }
}
