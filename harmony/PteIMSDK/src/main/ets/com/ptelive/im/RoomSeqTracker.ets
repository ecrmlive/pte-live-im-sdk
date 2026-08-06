type WireObject = Record<string, Object>

export interface PteIMLiveEventEnvelope {
  eventId?: string
  roomSeq?: number
  serverTs?: number
  priority?: string
}

export interface PteIMLiveRoomEventRow {
  eventId: string
  eventType: string
  roomSeq: number
  payload: WireObject
}

export interface PteIMLiveCatchUpPage {
  currentRoomSeq: number
  events: PteIMLiveRoomEventRow[]
}

export interface PteIMLiveCatchUpSource {
  getCurrentRoomSeq(): Promise<number>
  fetchEventsAfter(afterSeq: number, limit?: number): Promise<PteIMLiveCatchUpPage>
}

/** Explicit ArkTS class avoids untyped/object-literal return values in frame parsing. */
export class PteIMFrameEvent {
  eventType?: string
  payload?: WireObject
}

function asRecord(value: Object | null | undefined): WireObject | null {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return null
  return value as WireObject
}

export function parseLivePayload(raw: Object | string | null | undefined): WireObject | null {
  if (typeof raw === 'string') {
    const trimmed = raw.trim()
    if (trimmed.length === 0) return null
    try {
      return asRecord(JSON.parse(trimmed) as Object)
    } catch (_error) {
      return null
    }
  }
  return asRecord(raw)
}

export function readEnvelope(payload: WireObject): PteIMLiveEventEnvelope {
  const eventIdRaw = payload['eventId'] ?? payload['event_id']
  const eventId = eventIdRaw === undefined || eventIdRaw === null ? undefined : eventIdRaw.toString()
  const roomSeqRaw = payload['roomSeq'] ?? payload['room_seq']
  let roomSeq: number | undefined = undefined
  if (typeof roomSeqRaw === 'number') roomSeq = roomSeqRaw
  else if (roomSeqRaw !== undefined && roomSeqRaw !== null && roomSeqRaw.toString().trim().length > 0) {
    roomSeq = Number(roomSeqRaw.toString())
  }
  const serverTsRaw = payload['serverTs'] ?? payload['server_ts']
  let serverTs: number | undefined = undefined
  if (typeof serverTsRaw === 'number') serverTs = serverTsRaw
  else if (serverTsRaw !== undefined && serverTsRaw !== null && serverTsRaw.toString().trim().length > 0) {
    serverTs = Number(serverTsRaw.toString())
  }
  const priorityRaw = payload['priority']
  const priority = priorityRaw === undefined || priorityRaw === null ? undefined : priorityRaw.toString()
  return { eventId, roomSeq, serverTs, priority }
}

/** Tracks roomSeq watermark and eventId dedupe for scene WSS / catch-up. */
export class RoomSeqTracker {
  private lastRoomSeq: number
  private readonly seen: Set<string> = new Set<string>()

  constructor(initialLastRoomSeq: number = 0) {
    this.lastRoomSeq = initialLastRoomSeq
  }

  getLastRoomSeq(): number {
    return this.lastRoomSeq
  }

  /** Returns false when the payload is duplicate or stale. */
  accept(payload: WireObject): boolean {
    const envelope = readEnvelope(payload)
    if (envelope.eventId !== undefined && envelope.eventId.length > 0 && this.seen.has(envelope.eventId)) return false
    if (envelope.roomSeq !== undefined && envelope.roomSeq > 0 && envelope.roomSeq <= this.lastRoomSeq) {
      if (envelope.eventId !== undefined && envelope.eventId.length > 0) this.seen.add(envelope.eventId)
      return false
    }
    if (envelope.eventId !== undefined && envelope.eventId.length > 0) {
      this.seen.add(envelope.eventId)
      if (this.seen.size > 2000) {
        const drop: string[] = []
        this.seen.forEach((id: string) => { if (drop.length < 500) drop.push(id) })
        for (let index = 0; index < drop.length; index++) this.seen.delete(drop[index])
      }
    }
    if (envelope.roomSeq !== undefined && envelope.roomSeq > this.lastRoomSeq) this.lastRoomSeq = envelope.roomSeq
    return true
  }

  needsCatchUp(payload: WireObject): boolean {
    const envelope = readEnvelope(payload)
    return envelope.roomSeq !== undefined && envelope.roomSeq > this.lastRoomSeq + 1
  }

  async catchUp(source: PteIMLiveCatchUpSource, apply: (eventType: string, payload: WireObject) => void): Promise<void> {
    const current = await source.getCurrentRoomSeq()
    if (this.lastRoomSeq <= 0 && current > 0) this.lastRoomSeq = current
    let after = this.lastRoomSeq
    for (let page = 0; page < 20; page++) {
      const pageData = await source.fetchEventsAfter(after, 100)
      for (let index = 0; index < pageData.events.length; index++) {
        const row = pageData.events[index]
        const payload = parseLivePayload(row.payload) ?? {}
        if (payload['eventId'] === undefined && row.eventId.length > 0) payload['eventId'] = row.eventId
        if (payload['roomSeq'] === undefined && row.roomSeq > 0) payload['roomSeq'] = row.roomSeq
        if (this.accept(payload)) apply(row.eventType, payload)
        if (row.roomSeq > after) after = row.roomSeq
      }
      if (pageData.events.length < 100) {
        if (pageData.currentRoomSeq > this.lastRoomSeq) this.lastRoomSeq = pageData.currentRoomSeq
        break
      }
    }
  }
}

export function eventTypeFromFrame(frame: WireObject): PteIMFrameEvent {
  const empty = new PteIMFrameEvent()
  let envelope: Object | null = frame['data']
  if (typeof frame['data'] === 'string') {
    try {
      envelope = JSON.parse(frame['data'] as string) as Object
    } catch (_error) {
      return empty
    }
  }
  const root = asRecord(envelope)
  if (root === null) return empty
  const scene = asRecord(root['scene'])
  const payload = parseLivePayload(scene !== null ? scene['payload'] : null)
  let eventType: string | undefined = undefined
  const eventTypeSnake = root['event_type']
  const eventTypeCamel = root['eventType']
  const msg = frame['msg']
  if (typeof eventTypeSnake === 'string') eventType = eventTypeSnake
  else if (typeof eventTypeCamel === 'string') eventType = eventTypeCamel
  else if (typeof msg === 'string') eventType = msg
  const result = new PteIMFrameEvent()
  result.eventType = eventType
  result.payload = payload ?? flattenPayload(root) ?? undefined
  return result
}

function flattenPayload(root: WireObject): WireObject | null {
  if (root['eventId'] !== undefined || root['event_id'] !== undefined ||
    root['roomSeq'] !== undefined || root['room_seq'] !== undefined) return root
  return null
}
