import type { PteIMSceneKind } from './types.ts'

/** 电商直播 */
export const PTE_IM_SCENE_SHOP: PteIMSceneKind = 'shop'

export const SHOP_EVENT_EXAMPLES = [
  'shop.chat.created',
  'shop.gift.sent',
  'shop.product.on',
  'shop.product.off',
  'shop.product.explain.start',
  'shop.product.explain.cancel',
  'shop.product.list.refresh',
  'shop.moderation.muted',
  'shop.stream.state',
  'shop.online.count',
  'shop.like.update',
  'shop.user.enter',
] as const
