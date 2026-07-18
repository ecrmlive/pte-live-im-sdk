# Release 流程（uni-app x）

本文档是 `uni_modules/pte-im-sdk` 与 `uni_modules/pte-im-uikit` 的统一发布规范。

## 发布入口

仓库已配置工作流：  
- `.github/workflows/release-uniappx.yml`

触发方式：**只在 `git push tag` 时执行**，tag 规则为 `v*`（如 `v1.0.0`）。

发版版本号来源于 tag：
- `v1.2.3` -> 发布版本 `1.2.3`

## 先决条件（仓库设置）

在 `pte-live-im-sdk` 仓库设置里配置：

1. Secrets
   - `NPM_REGISTRY`：你的私有 registry 地址，例如 `https://registry.your-company.com/repository/npm-release/`
   - `NPM_TOKEN`：可发布 token（与该 registry 对应）
   - `GH_PACKAGES_TOKEN`（可选）：用于同步 GitHub Packages 时使用

2. Variables（可选）
   - `PUBLISH_GH_PACKAGES`：`true` 或 `false`  
   - `true` 时会在主发布完成后同步到 `npm.pkg.github.com`

> 当前版本固定为 `@pte-live/pte-im-uniappx-core` 与 `@pte-live/pte-im-uniappx-uikit`，scope 为 `pte-live`。

## 发布步骤

1. 确保代码在目标分支已完成合并（推荐 `main`）。
2. 在本地打 tag（版本号需为三段语义化版本）：

```bash
git checkout main
git pull
git tag -a v1.0.0 -m "release v1.0.0"
git push origin v1.0.0
```

3. GitHub Actions 自动执行：
   - 解析 tag 并校验 `x.y.z` 格式
   - 将两个包版本都改为该版本
   - 发布到私有 registry
   - 如变量 `PUBLISH_GH_PACKAGES=true`，同步到 GitHub Packages

4. 发布完成后验证（示例）：

```bash
npm view @pte-live/pte-im-uniappx-core version --registry <私有源>
npm view @pte-live/pte-im-uniappx-uikit version --registry <私有源>
```

## 注意事项

1. 不要手动上传源码到发布仓库；按 tag 触发流程发布。
2. tag 必须是纯语义化版本（如 `1.0.0`），否则工作流会失败。
3. 若需回滚，请新建一个更高版本号进行修复发布（避免直接重发同版本）。

## 统一版本口径

- 每次统一发布时，`pte-im-sdk` 与 `pte-im-uikit` 均使用同一个版本号（例如 `1.0.0`）。
- 该版本号由 Git tag 决定，不需要手动改两个 `package.json` 里的 `version`。
