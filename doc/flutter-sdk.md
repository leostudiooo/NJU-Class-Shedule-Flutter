---
title: Flutter SDK 工作流
summary: 首次搭环境、切换 SDK 版本、lockfile 校验失败时读。
group: build
applies_to: tool/ci/, .fvmrc, pubspec.lock
---
## 适用场景

需要初始化本机环境、升级 Flutter、或 `pub get` 报 lockfile 不一致时。日常改 Dart 代码不需要读。

## 操作

```bash
bash tool/ci/bootstrap.sh
```

脚本把 SDK checkout 到 `.fvm/flutter_sdk`，按固定 commit 拉取 `external/` 下的三个路径依赖，把 `PUB_CACHE` 固定在 `.fvm/pub-cache`，最后执行 `flutter pub get --enforce-lockfile`。

之后统一使用仓库内 SDK，不要用全局 `fvm`：

```bash
.fvm/flutter_sdk/bin/flutter run
```

只验证已有产物时加 `--no-pub`，避免重新解析依赖改写 `pubspec.lock`。

## 验证

```bash
.fvm/flutter_sdk/bin/flutter --version
```

输出应与 `.fvmrc` 的 `flutter` 字段一致。

## 常见故障

- **只改 `.fvmrc` 后重跑脚本，版本没变** → `bootstrap.sh` 顶部的 `flutter_ref` / `flutter_commit` 是独立真值。脚本在两者不一致时会直接失败，按报错同步修改即可，不会静默装旧版本。
- **`pub get --enforce-lockfile` 失败** → `pubspec.lock` 与 `pubspec.yaml` 不一致。先确认没有意外升级，再决定是否更新锁文件并提交。
- **升级 `html` 后编译报 `Method not found: 'matches'`** → `flutter_html 3.0.0` 依赖旧 selector API，`pubspec.yaml` 里的 `dependency_overrides: html: 0.15.6` 不要动。
