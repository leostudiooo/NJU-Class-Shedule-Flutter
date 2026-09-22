# 本地学校导入测试

导入页通过 `Config.USE_LOCAL_IMPORT_CONFIG` 决定配置来源：默认读取线上配置；设置 `--dart-define=USE_LOCAL_IMPORT_CONFIG=true` 后，读取打包资源 `api/schoolList.json`。解析脚本也会切换为本地加载：`ImportFromBEView` 只取 `extractJSfile*` URL 的最后一个路径段，并从 `api/tools/<文件名>.js` 读取脚本。

## 测试流程

1. 修改 `api/schoolList.json`，为待测学校配置正确的 `initialUrl`、`redirectUrl`、`targetUrl` 及平台对应的 `extractJSfile*`。
2. 将脚本放在 `api/tools/`，并确保 URL 最后一段与文件名完全一致。`http://127.0.0.1/<file>.js` 可以作为占位 URL；本地模式不会请求这个地址，也不需要启动本地 HTTP 服务。
3. 确认脚本返回经过 `encodeURIComponent` 的课程 JSON，字段格式参照 README 中的课程导入协议。
4. 启动：

   ```bash
   yes | fvm flutter run --dart-define=USE_LOCAL_IMPORT_CONFIG=true
   ```

   已经完成依赖解析时使用 `--no-pub`：

   ```bash
   yes | fvm flutter run --no-pub --dart-define=USE_LOCAL_IMPORT_CONFIG=true
   ```

5. 在导入页选择目标学校，完成真实登录并检查课程、周次、星期、开始节数、持续节数、教师和地点。

这条路径只把配置和解析脚本切换为本地版本；WebView 仍访问真实教务系统，所以仍需要网络、登录凭据以及目标学校要求的 VPN 或校园网。
