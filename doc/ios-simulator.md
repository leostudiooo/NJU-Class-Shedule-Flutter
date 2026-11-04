# iOS Apple Silicon Simulator 构建

初始化环境并构建：

```bash
bash tool/ci/bootstrap.sh
source tool/setup_ohos_env.sh
.fvm/flutter_sdk/bin/flutter build ios --simulator --debug --no-codesign --no-pub
file build/ios/iphonesimulator/Runner.app/Runner
```

成功时产物应显示：

```text
Mach-O 64-bit executable arm64
```

Apple Silicon 模拟器的 arm64 切片由依赖版本保证：`UMCommon` / `UMDevice` 固定在带 ARM64 模拟器切片的官方 XCFramework 版本，扫码使用 `third_party/mobile_scanner` 中的源码版本（iOS 走苹果 Vision）。不再需要对预编译 ML Kit 静态库做 arm64 标记修补。

当前 Pod/Xcode 配置要求 iOS 15.0，真机与模拟器部署下限一致，支持 Xcode 27 构建。修改 `ios/Podfile` 或清理 `ios/Pods` 后，重新执行：

```bash
pod install
```

如果 Flutter SDK 缓存锁文件、网络或设备命令被沙箱拦截，再考虑使用提升权限；不要把提升权限当作常规构建步骤。
