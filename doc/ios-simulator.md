---
title: iOS Apple Silicon Simulator 构建
summary: 改 ios/ 或 Podfile、模拟器产物架构不对时读。
group: build
applies_to: ios/
---
## 适用场景

调整 iOS 依赖、清理 `ios/Pods`，或需要确认模拟器产物是 arm64 时。日常改 Dart 代码不需要读。

## 操作

构建命令见 README。这里只列不按常规做会出错的部分：

- `ios/Podfile` 与 Xcode 工程的部署下限是 iOS 15.0，真机与模拟器一致。
- 修改 `ios/Podfile` 或清理 `ios/Pods` 后必须重新 `pod install`，且工具链与 CI 一致：

  ```bash
  gem install json -v 2.18.0 --no-document
  gem install xcodeproj -v 1.28.1 --no-document
  gem install cocoapods -v 1.17.0 --conservative --no-document
  ```

- 扫码依赖 `third_party/mobile_scanner`（iOS 走苹果 Vision），分享依赖 `third_party/share_extend`。

## 验证

```bash
file build/ios/iphonesimulator/Runner.app/Runner
```

输出必须包含 `Mach-O 64-bit executable arm64`。

## 常见故障

- **模拟器链接报 arm64 缺失** → 检查 `UMCommon` / `UMDevice` 是否锁在带 ARM64 模拟器切片的版本。旧方案是给 ML Kit 静态库打补丁，补丁脚本已删除，不要恢复。
- **`pod install` 后 `ios/Podfile.lock` 大范围变动** → CocoaPods 版本与 CI 不一致，按上面三个 gem 版本重装后重跑。
- **CI 的 iOS 任务报锁文件 diff** → 本地生成结果与 CI 不同，以 CI 版本为准重新生成再提交。
