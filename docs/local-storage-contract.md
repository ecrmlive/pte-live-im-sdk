# PteIM 本地存储契约

| 平台 | 存储实现 | 数据范围 | 安全边界 |
| --- | --- | --- | --- |
| iOS | Core Data | 消息、会话、Outbox、同步游标、设备 E2EE 状态 | Keychain 密钥、AES-256-GCM 内容加密、文件保护 |
| Android | Room | 消息、会话、Outbox、同步游标、设备 E2EE 状态 | Android Keystore 密钥、AES-256-GCM 内容加密 |
| OpenHarmony | ArkData RDB | 消息、会话、Outbox、同步游标、设备 E2EE 状态 | RDB 加密、系统安全等级 |
| uni-app x UTS | 宿主安全存储 | 加密热缓存与同步游标 | `localStorageCipher` 由宿主提供；UserSig 不落盘 |
| Browser（`@pte-live/im-web-sdk`） | IndexedDB | 仅 E2EE 设备身份（私钥 + `device_id`） | 同源不可导出 AES-GCM 包装；不持久化消息/Outbox/游标；UserSig 不落盘 |

每个账号使用独立的缓存命名空间。会话与消息的读取均限制分页大小为 1–200；同步按服务器游标逐页提交；Outbox 保存重试计数和下一次重试时间。SDK 不保存 UserSig、业务登录密码、COS 临时凭据或推送平台主密钥。

缓存中的消息正文、Outbox 内容和同步游标均经 AES-256-GCM 加密。查询所需的会话 ID、消息 ID、创建时间、发送状态和服务端序号作为索引元数据，用于可靠分页、去重和重试。
