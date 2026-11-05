---
title: 本地学校导入测试
summary: 改导入脚本、新增学校、调整手动学期选择时读。
group: feature
applies_to: api/, lib/Pages/Import/, lib/Utils/OnlineImportService.dart
---
## 适用场景

需要不依赖线上配置验证学校导入脚本，或新增、修改学校配置与手动学期选择时。

## 操作

导入页通过 `Config.USE_LOCAL_IMPORT_CONFIG` 决定配置来源：默认读线上，加 `--dart-define` 后读打包资源 `api/schoolList.json`。

配置约定：

- 本地模式下，脚本按 URL 最后一段从 `api/tools/<文件名>.js` 读取；`http://127.0.0.1/<file>.js` 可作占位，不会真的发起请求。
- 线上模式请求配置里的完整 URL。
- 解析脚本必须返回经过 `encodeURIComponent` 的课程 JSON，字段格式见 README 的课程导入协议。
- 启用 `manualTermSelection` 的学校要配 `manualTermScript`，脚本返回经过编码的学期数组，至少包含 `dm`、`name`、`start`、`selected`。
- 学校专用接口和原始响应结构留在对应学校脚本里，不要抽到通用层。

启动：

```bash
.fvm/flutter_sdk/bin/flutter run --dart-define=USE_LOCAL_IMPORT_CONFIG=true
```

依赖已解析时加 `--no-pub`。发布前要把 `manualTermScript` 同步到线上配置并发布脚本；此路径只切换配置和脚本来源，WebView 仍访问真实教务系统，所以仍需要网络、登录凭据，以及目标学校要求的 VPN 或校园网。

## 验证

在导入页选择目标学校，完成真实登录，检查课程、周次、星期、开始节数、持续节数、教师和地点。启用 `manualTermSelection` 的学校应先弹出学期选择框，选中后开学日期与周次都正确。

## 常见故障

- **手动选了学期但周次全错** → `OnlineImportService` 必须让抓取结果里的 `semester_start_monday` 优先于学校静态配置。改回只读配置会丢掉开学日期。
- **页面内「确认导入课表」按钮点了没反应** → `CourseImportJSChannel` 必须注册，按钮通过它回调 `import`。
- **学期选择框弹两次** → `_manualImportPromptShown` 负责幂等。`onPageFinished` 和 `onUrlChange` 两个入口都会触发，不要删这个标记。
- **本地模式读不到脚本** → 配置 URL 最后一段必须与 `api/tools/` 下的文件名完全一致。
