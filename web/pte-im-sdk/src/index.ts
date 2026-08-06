/** @pte-live/pte-im-sdk — Browser Core: chat + commerce + scene. */

export * from './chat/index.ts'
export * from './commerce/index.ts'
export * from './scene/index.ts'

import { PteLiveIMWebClient } from './chat/client.ts'
import { PteIMSceneClient } from './scene/client.ts'

/** Convenience facade: chat client factory + scene client factory. */
export const PteIMWeb = {
  chat: (credentials: ConstructorParameters<typeof PteLiveIMWebClient>[0]) => new PteLiveIMWebClient(credentials),
  scene: (credentials: ConstructorParameters<typeof PteIMSceneClient>[0]) => new PteIMSceneClient(credentials),
}
