开始涉及项目架构、Flutter、依赖解析、CocoaPods、iOS Simulator 或功能工作流前，先查询 [`doc/index.md`](doc/index.md)，再阅读与任务最相关的稳定文档。`reference/` 只用于开发过程中的临时记录和背景材料。

Flutter SDK 由 `tool/ci/bootstrap.sh` 按 `.fvmrc` 固定的版本 checkout 到仓库内 `.fvm/flutter_sdk`，同时把 `external/` 下的本地依赖拉到指定 commit。首次使用或切换版本后先执行：

```bash
bash tool/ci/bootstrap.sh
```

之后统一使用仓库内 SDK，不再使用全局 `fvm`：

```bash
.fvm/flutter_sdk/bin/flutter pub get
.fvm/flutter_sdk/bin/flutter run
```

当 OHOS 环境报错时，先 `source tool/setup_ohos_env.sh`，再执行上述命令。

只保留以下高层约束：

- 构建、依赖与 CI 流程以 [`tool/ci/README.md`](tool/ci/README.md) 和 [`.github/workflows/build.yml`](.github/workflows/build.yml) 为准；本地环境需与 CI 保持一致，不要混用全局 FVM 版本。
- 依赖、Pod 或 Xcode 构建失败时，先查参考文档，再检查 `git status` 和 `pubspec.lock`，避免无意升级或覆盖已有修复。
- 稳定文档索引由 Git `pre-commit` hook 自动生成；修改或新增 `doc/*.md` 后不要手工编辑 `doc/index.md`。首次使用仓库时运行 `tool/install_git_hooks.sh`。
- `doc/` 只放代码读不出来的稳定事实：先问「删掉它谁会犯什么错」，答不出就不要建文件。新建用 `tool/new_doc.sh <name> "<title>"`，格式见 [`doc/documentation-standard.md`](doc/documentation-standard.md)；`doc/index.md` 自动生成，不要手改。

# For OpenAI ChatGPT Codex Agents

ChatGPT Codex 的安全沙箱机制会阻拦大部分网络活动和外部设备/资源访问。如果出现网络请求失败（如拉取 Flutter SDK 时找不到下载服务器）、找不到设备（如devicectl list devices）、命令行工具无权更改文件等任何问题，都应该先尝试 elevate exec tool 的权限先重试，而不要立刻就说环境不存在、无法执行、网络问题等。因为这些问题大多是权限不足需要访问外部资源导致的，而不是环境本身的问题。
