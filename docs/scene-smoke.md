# Scene 烟测说明

五端用同一契约验证房间进房（不接业务 UI / 推流）。

## Web

```ts
import { runSceneSmoke } from '../web/pte-im-sdk/src/scene/smoke.ts'

const stop = await runSceneSmoke({
  wsUrl, sdkAppId, userId, userSig, scene: 'show', roomId, catchUp,
})
// later: stop()
```

或直接使用 `PteIMSceneClient`（见 `web/pte-im-sdk/README.md`）。

## Android

```kotlin
val scene = im.createSceneClient()
scene.addListener(object : PteIMSceneListener { /* log onEntered / onEvent */ })
scene.connect(userId, loginUserSig) { result ->
  result.onSuccess {
    scene.enter(PteIMSceneKind.SHOW, roomId, catchUp = hostCatchUp) { /* ... */ }
  }
}
```

## iOS

```swift
let scene = im.createSceneClient()
try await scene.connect(userId: userId, userSig: loginUserSig)
try await scene.enter(scene: .show, roomId: roomId, catchUp: hostCatchUp)
```

## HarmonyOS

```ts
const scene = im.createSceneClient(credentials)
await scene.connect()
await scene.enter({ scene: 'voice', roomId, catchUp })
```

## UTS

```ts
const scene = client.scene.create(credentials)
scene.connect((err) => {
  if (err != null) return
  scene.enter({ scene: 'shop', roomId }, (result, error) => { /* ... */ })
})
```

宿主补漏 HTTP 对接：社交 → social 业务仓库；电商 → `pte-live-shop`；体育 → `qixi-live-sports`。SDK 不内置这些 REST。
