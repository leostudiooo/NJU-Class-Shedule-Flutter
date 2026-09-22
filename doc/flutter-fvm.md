# Flutter 与 FVM 工作流

项目通过 FVM 使用自定义 OHOS Flutter SDK。该版本不是官方 Flutter 版本，因此 FVM 执行命令前会要求确认。

## 高频命令

```bash
yes | fvm flutter pub get
yes | fvm flutter run
```

如果只是验证已有依赖和构建产物，优先使用 `--no-pub`，避免重新解析依赖并改写 `pubspec.lock`。运行前先检查：

```bash
git status --short --branch
```

依赖解析产生的锁文件变化必须审阅后再保留。

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
