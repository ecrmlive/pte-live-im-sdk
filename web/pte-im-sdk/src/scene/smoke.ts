/**
 * Minimal Scene smoke harness for Web SDK hosts.
 * Not a UIKit. Wire UserSig + CatchUpSource from your business API.
 */
import {
  PteIMSceneClient,
  type LiveCatchUpSource,
  type PteIMSceneKind,
} from '../index.ts'

export type SceneSmokeOptions = {
  wsUrl: string
  sdkAppId: string
  userId: string
  userSig: string
  scene: PteIMSceneKind
  roomId: string
  extend?: string
  catchUp?: LiveCatchUpSource
  log?: (line: string) => void
}

export async function runSceneSmoke(options: SceneSmokeOptions): Promise<() => void> {
  const log = options.log ?? ((line: string) => console.log(`[scene-smoke] ${line}`))
  const client = new PteIMSceneClient({
    wsUrl: options.wsUrl,
    sdkAppId: options.sdkAppId,
    userId: options.userId,
    userSig: options.userSig,
  })
  const listener = {
    onConnectionChanged: (ok: boolean) => log(`connection=${ok}`),
    onEntered: (info: { groupName: string }) => log(`entered ${info.groupName}`),
    onEnterFailed: (info: { message: string }) => log(`enter failed: ${info.message}`),
    onEvent: (eventType: string) => log(`event ${eventType}`),
    onError: (message: string) => log(`error ${message}`),
  }
  client.addListener(listener)
  await client.enter({
    scene: options.scene,
    roomId: options.roomId,
    extend: options.extend,
    catchUp: options.catchUp,
  })
  log('smoke enter ok')
  return () => {
    client.removeListener(listener)
    void client.leave()
    client.disconnect()
  }
}
