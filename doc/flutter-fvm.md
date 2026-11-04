# Flutter SDK 工作流

项目不使用全局 FVM 版本。Flutter SDK 由 `tool/ci/bootstrap.sh` 按 `.fvmrc` 固定的版本 checkout 到仓库内 `.fvm/flutter_sdk`，同时把 `external/` 下的本地依赖拉到指定 commit，并把 `PUB_CACHE` 限制在仓库内。

## 初始化与切换版本

```bash
bash tool/ci/bootstrap.sh
```

首次使用、合并上游后 `.fvmrc` 变化、或 `pubspec.lock` 变化时都要重新执行。脚本最后会跑 `flutter pub get --enforce-lockfile`，锁文件与 `pubspec.yaml` 不一致会直接失败。

## 高频命令

```bash
.fvm/flutter_sdk/bin/flutter pub get
.fvm/flutter_sdk/bin/flutter run
```

如果只是验证已有依赖和构建产物，优先使用 `--no-pub`，避免重新解析依赖并改写 `pubspec.lock`。运行前先检查：

```bash
git status --short --branch
```

依赖解析产生的锁文件变化必须审阅后再保留；CI 会校验 `pubspec.lock` 与 `ios/Podfile.lock` 在构建后没有变化。

## 与 CI 保持一致

[`.github/workflows/build.yml`](.github/workflows/build.yml) 使用同一个 `bootstrap.sh`，三端产物分别在 Android / iOS / OHOS 上构建。本地排查构建问题时应先确认跑的是仓库内 SDK：

```bash
.fvm/flutter_sdk/bin/flutter --version
```

版本与 `.fvmrc` 不一致时重新执行 `bootstrap.sh`，不要回退到全局 `fvm`。

## 依赖约束

`flutter_html 3.0.0` 通过 `html` 的内部 selector API 调用 `matches`。`html 0.15.7+` 改变了该 API，会导致：

```text
Method not found: 'matches'
```

`pubspec.yaml` 中因此固定了：

```yaml
dependency_overrides:
  html: 0.15.6
```

不要在未验证 `flutter_html` 兼容性的情况下升级 `html`。
