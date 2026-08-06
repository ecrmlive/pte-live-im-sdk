import type { PteIMSceneKind } from './types.ts'

/** 社交-直播 */
export const PTE_IM_SCENE_SHOW: PteIMSceneKind = 'show'

export const SHOW_EVENT_EXAMPLES = [
  'scene.chat.created',
  'scene.gift.sent',
  'scene.user.enter',
  'scene.moderation.muted',
  'scene.moderation.kicked',
  'scene.commerce.order.created',
] as const
