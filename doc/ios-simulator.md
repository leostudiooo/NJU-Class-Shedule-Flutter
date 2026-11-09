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

当前 Pod/Xcode 配置要求 iOS 15.0，真机与模拟器部署下限一致。Xcode 27 上 `flutter build ios --simulator` 会失败，需按下节只编 arm64。

## Xcode 27 差异

`Simulator.app` 已不存在，模拟器界面由 `DeviceHub.app` 提供：`open -a DeviceHub`，文件在 `/Applications/Xcode.app/Contents/Applications/`，`Contents/Developer/Applications/` 为空是正常的。命令行仍是 `xcrun simctl`。

Icon Studio 导出从 Xcode 27 起区分大小写。`ios/WhereToSleepInNJU.icon/icon.json` 里 `image-name-specializations` 必须写实际文件名 `Bottom.png`，写成 `bottom.png` 只会在构建时报 `Icon export exited with status 255` 和 `Failed to create a catalog from the Icon Studio document`，不会提示文件名错误。

Xcode 27 的 `lipo -verify_arch` 只接受单个架构，而 `debug_unpack_ios`（`thinFramework`）一次传 `arm64 x86_64`，于是 `flutter build ios --simulator` 报 `does not contain architectures "arm64 x86_64"`，同时 `lipo -info` 显示两个架构都在。Apple Silicon 只编 arm64 即可绕过：

```bash
source tool/setup_ohos_env.sh
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination 'id=<模拟器 UDID>' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Runner-*/Build/Products/Debug-iphonesimulator/Runner.app
xcrun simctl launch booted top.idealclover.wheretosleepinnju
```

`flutter run` 走同一条脚本阶段，同样会失败。

修改 `ios/Podfile` 或清理 `ios/Pods` 后，重新执行：

```bash
pod install
```

如果 Flutter SDK 缓存锁文件、网络或设备命令被沙箱拦截，再考虑使用提升权限；不要把提升权限当作常规构建步骤。
