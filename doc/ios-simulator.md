# iOS Apple Silicon Simulator 构建

初始化环境并构建：

```bash
source tool/setup_ohos_env.sh
export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
export PUB_CACHE="$PWD/.fvm/.pub_cache"
flutter build ios --simulator --debug --no-codesign --no-pub
file build/ios/iphonesimulator/Runner.app/Runner
```

成功时产物应显示：

```text
Mach-O 64-bit executable arm64
```

Xcode Build Phase 会自动执行 `ios/MLKitAppleSiliconSimulator/patch_arm64_simulator.py`，修复旧版 ML Kit 静态库的 arm64 Simulator platform 标记；不需要手动运行该脚本。

当前 Pod/Xcode 配置要求 iOS 15.0，并保留 Apple Silicon Simulator 的 arm64 架构。修改 `ios/Podfile` 或清理 `ios/Pods` 后，重新执行：

```bash
pod install
```

如果 Flutter SDK 缓存锁文件、网络或设备命令被沙箱拦截，再考虑使用提升权限；不要把提升权限当作常规构建步骤。
