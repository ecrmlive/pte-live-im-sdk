import type { PteIMSceneKind } from './types.ts'

/** 体育直播 */
export const PTE_IM_SCENE_SPORTS: PteIMSceneKind = 'sports'

export const SPORTS_EVENT_EXAMPLES = [
  'sports.chat.created',
  'sports.gift.sent',
  'sports.red_packet.sent',
  'sports.red_packet.claimed',
  'sports.moderation.muted',
  'sports.moderation.unmuted',
  'sports.moderation.kicked',
  'sports.stream.state',
  'sports.product.on',
  'sports.product.off',
] as const
