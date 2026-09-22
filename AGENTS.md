开始涉及项目架构、Flutter、FVM、依赖解析、CocoaPods、iOS Simulator 或功能工作流前，先查询 [`doc/index.md`](doc/index.md)，再阅读与任务最相关的稳定文档。`reference/` 只用于开发过程中的临时记录和背景材料。

Flutter 统一使用项目配置的 FVM 管理。由于当前 OHOS SDK 是自定义版本，FVM 会要求确认；用 `yes` 自动通过，以免交互式确认阻塞命令执行。

```bash
yes | fvm flutter <command>
```

例如：

```bash
yes | fvm flutter pub get
yes | fvm flutter run
```

只保留以下高层约束：

- 使用项目配置的 `fvm flutter` 管理 Flutter 版本；需要自动确认时使用上面的 `yes | fvm flutter <command>`。
- 稳定文档索引由 Git `pre-commit` hook 自动生成；修改或新增 `doc/*.md` 后不要手工编辑 `doc/index.md`。首次使用仓库时运行 `tool/install_git_hooks.sh`。
- 依赖、Pod 或 Xcode 构建失败时，先查参考文档，再检查 `git status` 和 `pubspec.lock`，避免无意升级或覆盖已有修复。
- 稳定文档规范见 [`doc/documentation-standard.md`](doc/documentation-standard.md)；文档描述的事实发生变化时，在同一变更中更新对应主题文档。

# For OpenAI Codex Agents

Codex 的安全沙箱机制会阻拦大部分网络活动和外部设备/资源访问。如果出现网络请求失败（如fvm提示找不到下载服务器）、找不到设备（如devicectl list devices）、命令行工具无权更改文件等问题，可以尝试要求提升权限执行。
