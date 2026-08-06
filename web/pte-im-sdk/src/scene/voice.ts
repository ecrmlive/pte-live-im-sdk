import type { PteIMSceneKind } from './types.ts'

/** 社交-语聊 */
export const PTE_IM_SCENE_VOICE: PteIMSceneKind = 'voice'

export const VOICE_EVENT_EXAMPLES = [
  'scene.chat.created',
  'scene.gift.sent',
  'scene.user.enter',
  'scene.mic.seat.changed',
  'scene.moderation.muted',
  'scene.moderation.kicked',
  'scene.commerce.order.created',
] as const
