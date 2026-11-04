# 本地学校导入测试

导入页通过 `Config.USE_LOCAL_IMPORT_CONFIG` 决定配置来源：默认读取线上配置；设置 `--dart-define=USE_LOCAL_IMPORT_CONFIG=true` 后，读取打包资源 `api/schoolList.json`。导入解析脚本和手动学期脚本均按配置加载：本地模式取 `extractJSfile*` 或 `manualTermScript` URL 的最后一个路径段，从 `api/tools/<文件名>.js` 读取；线上模式则请求配置中的完整 URL。启用 `manualTermSelection` 的学校可配置 `manualTermScript`，脚本应返回经过 `encodeURIComponent` 的标准学期数组，至少包含 `dm`、`name`、`start` 和 `selected` 字段。学校专用接口及原始响应结构留在对应学校脚本中。

## 测试流程

1. 修改 `api/schoolList.json`，为待测学校配置正确的 `initialUrl`、`redirectUrl`、`targetUrl`、平台对应的 `extractJSfile*`，以及需要时的 `manualTermScript`。
2. 将脚本放在 `api/tools/`，并确保配置 URL 最后一段与文件名完全一致。`http://127.0.0.1/<file>.js` 可以作为占位 URL；本地模式不会请求这个地址，也不需要启动本地 HTTP 服务。
3. 确认解析脚本返回经过 `encodeURIComponent` 的课程 JSON，字段格式参照 README 中的课程导入协议；手动学期脚本返回经过编码的标准学期数组。
4. 启动：

   ```bash
   .fvm/flutter_sdk/bin/flutter run --dart-define=USE_LOCAL_IMPORT_CONFIG=true
   ```

   已经完成依赖解析时使用 `--no-pub`：

   ```bash
   .fvm/flutter_sdk/bin/flutter run --no-pub --dart-define=USE_LOCAL_IMPORT_CONFIG=true
   ```

5. 在导入页选择目标学校，完成真实登录并检查课程、周次、星期、开始节数、持续节数、教师和地点。

发布时要将 `manualTermScript` 配置同步到线上学校配置，并发布相应脚本。此路径只把配置和脚本切换为本地版本；WebView 仍访问真实教务系统，所以仍需要网络、登录凭据以及目标学校要求的 VPN 或校园网。
