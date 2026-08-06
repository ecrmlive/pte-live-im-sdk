/** Room scene kinds owned by PteIMSceneClient. */
export type PteIMSceneKind = 'show' | 'voice' | 'shop' | 'sports'

export const PTE_IM_SCENES: readonly PteIMSceneKind[] = ['show', 'voice', 'shop', 'sports'] as const

/** Expected eventType prefixes (unknown types still pass through onEvent). */
export const PTE_IM_SCENE_EVENT_PREFIX: Record<PteIMSceneKind, readonly string[]> = {
  show: ['scene.', 'scene.commerce.'],
  voice: ['scene.', 'scene.commerce.'],
  shop: ['shop.'],
  sports: ['sports.'],
}

export function groupNameForScene(scene: PteIMSceneKind, roomId: string): string {
  if (scene === 'shop') return `live:${roomId}`
  if (scene === 'sports') return `sports:${roomId}`
  return `${scene}:${roomId}`
}

/** Local pre-check for sports room_id shape. */
export function assertSceneRoomId(scene: PteIMSceneKind, roomId: string): void {
  const id = String(roomId || '').trim()
  if (!id) throw new Error('roomId 不能为空')
  if (scene === 'sports' && !/^sports-live-\d+$/.test(id)) {
    throw new Error('体育房间 roomId 必须为 sports-live-{数字id}')
  }
}
