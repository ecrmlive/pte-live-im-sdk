# Release 流程

## Web SDK（`web/pte-im-sdk`）

包名：`@pte-live/pte-im-sdk`。

本地消费：

```json
{ "dependencies": { "@pte-live/pte-im-sdk": "file:../pte-live-im-sdk/web/pte-im-sdk" } }
```

构建与单测：

```bash
cd web/pte-im-sdk && npm install && npm test && npm run build
```

建议与四端同一 minor（如 `1.1.0`）对齐后发 tag。Scene / Commerce / 聊一聊能力见 [docs/platform-capability-matrix.md](docs/platform-capability-matrix.md)。

## uni-app x

以下是 `uni_modules/pte-im-sdk` 与 `uni_modules/pte-im-uikit` 的统一发布规范。

### 发布入口

仓库已配置工作流：`.github/workflows/release-uniappx.yml`  
触发方式：**只在 `git push tag` 时执行**，tag 规则为 `v*`（如 `v1.0.0`）。

发版版本号来源于 tag：`v1.2.3` -> 发布版本 `1.2.3`。

### 先决条件

在 `pte-live-im-sdk` 仓库设置里配置 Secrets：`NPM_REGISTRY`、`NPM_TOKEN`；可选 `GH_PACKAGES_TOKEN` 与变量 `PUBLISH_GH_PACKAGES`。

### 发布步骤

```bash
git checkout main && git pull
git tag -a v1.1.0 -m "release v1.1.0"
git push origin v1.1.0
```

### 统一版本口径

- `pte-im-sdk` 与 `pte-im-uikit` 使用同一 tag 版本。
- Web `@pte-live/pte-im-sdk` 建议与上述 minor 对齐。
