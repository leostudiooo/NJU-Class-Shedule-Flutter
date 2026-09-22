<div align="center">

<img src="./android/app/src/main/res/ic_launcher.png" alt="logo" width="128" height="128" />

<h1>南哪课表 APP</h1>

**为 不止 NJUer 打造的 Android/iOS 平台课程表,使用 Flutter 编写**

</div>

## 下载/Download

[南哪课表官网](https://nju.app)

[安卓下载地址](https://mirror.nju.edu.cn/download/%E5%8D%97%E5%93%AA%E8%AF%BE%E8%A1%A8)

[iOS 下载地址](https://apps.apple.com/cn/app/%E5%8D%97%E5%93%AA%E8%AF%BE%E8%A1%A8/id1511705694)

[南哪课表 FAQ](https://idealclover.top/archives/606/)

<!--more-->

## 功能/Features

当前适配学校：南京大学、东南大学、上海交通大学、中国人民大学

更多学校适配欢迎联系作者或自行 PR~

1. Android & iOS 全平台支持
2. 支持南京大学统一认证登录，本科生&研究生均支持
3. 一键导入南大教务处，自动获取当前周
4. 支持免修不免考，同一时段允许多门课程
5. 支持不同学期多个课表管理与切换
6. 更多样式，自由添加背景图片

## 如何支持更多学校

开发说明和维护约定见 [`doc/index.md`](doc/index.md)。该索引由 Git hook 在提交前自动生成。首次使用仓库时执行：

```bash
sh tool/install_git_hooks.sh
```

南哪课表解析课程的主要原理是通过打开页面，并通过 JS 脚本获取页面中的课程信息，然后解析出课程的时间、地点、教师等信息。

涉及到的主要文件：

> [api/schoolList.json](api/schoolList.json): 学校列表，包含学校名称、登录 URL、课程表 URL 等信息，在其中添加需要适配学校的相关信息
>
> [api/tools/njubksjw2.js](api/tools/njubksjw2.js): 当前南京大学使用的示例课程表解析脚本，你可以参考该文件，根据学校的课程表页面，获取课程信息并解析出时间、地点、教师等信息
>
> [api/tools/seubksxk.js](api/tools/parseCourse.js): 当前东南大学使用的示例课程表解析脚本，你可以参考该文件，在 JS 脚本中进行 http 请求，根据学校的课程表页面，获取课程信息并解析出时间、地点、教师等信息

需要返回的数据格式（返回下面 json 格式数据的 encodeURIComponent 结果）：

```
{
    "name": "当前学期名称",
    "courses": [
        {
            "name": "课程名称",
            "classroom": "课程地点",
            "class_number": "课程编号",
            "teacher": "教师名称",
            "test_time": "考试时间",
            "test_location": "考试地点",
            "link":"课程详情链接，没有传null",
            "week": [1,2,3], // 课程第几周上，是一个数组
            "week_time": 1, // 课程周几上
            "start_time": 1, // 课程开始节数，从1开始,
            "time_count": 2, // 课程持续节数，即结束节数-开始结束，注意如果是3-4节则为1，不需要额外进行加一操作
            "import_type": 1, // 固定填1，作为自动导入方式
            "info": "课程详情，没有传null",
            "data": null
        }
    ]
}

```

### 使用本地配置和解析脚本测试导入

开发或调试学校导入时，可以让 App 读取仓库中的本地配置和 JavaScript 解析脚本，而不是读取线上 `schoolList.json` 和 CDN 脚本。实现方式是通过 Dart define 打开 `USE_LOCAL_IMPORT_CONFIG`：

1. 在 `api/schoolList.json` 中添加或修改学校配置。
2. 将解析脚本放到 `api/tools/<文件名>.js`。这些目录已经作为 Flutter assets 打包。
3. 在配置的 `extractJSfileAndroid`、`extractJSfileiOS`、`extractJSfileOHOS` 中填写包含相同文件名的 URL，例如 `http://127.0.0.1/njubksxk.js`。本地模式只取 URL 的最后一段文件名，并从 `api/tools/` 加载对应脚本；不要求本地启动 HTTP 服务。
4. 运行本地配置：

   ```bash
   yes | fvm flutter run --dart-define=USE_LOCAL_IMPORT_CONFIG=true
   ```

   如果依赖已经解析完成，也可以加 `--no-pub`，避免测试时改写 `pubspec.lock`。

本地模式仍会在 WebView 中访问学校教务系统，因此需要网络、登录凭据和对应的 VPN/校园网条件。测试完成后，确认没有把仅用于调试的配置或脚本 URL 留在正式配置中。

## 部署相关

因为增加了鸿蒙支持，需要使用鸿蒙 Flutter 版本。

1. 根据 [flutter_flutter oh-3.27.0](https://gitcode.com/openharmony-tpc/flutter_flutter/tree/oh-3.27.0-release) 配置鸿蒙依赖
2. 加载项目环境变量：`source tool/setup_ohos_env.sh` （配好环境之后就只需要每次开发打开终端执行一次）
3. 安装并使用指定版本：`fvm install oh-3.27.0-release && fvm use 3.27.5-ohos-1.0.3` （这里很奇怪，下载的版本号和cache版本号不一样）
4. 运行 `fvm flutter doctor -v` 检查环境变量配置，Flutter 与 OpenHarmony 都应为 `ok`
5. 在 `external` 文件夹中 clone 依赖（若尚未 clone）
  * `cd external`
  * `git clone https://gitcode.com/openharmony-tpc/flutter_packages.git` 
  * `git clone https://gitcode.com/openharmony-sig/flutter_sqflite.git`
  * `git clone https://gitcode.com/nutpi/flutter_plus_plugins_package_info_plus.git`
  * `git clone https://gitcode.com/openharmony-sig/fluttertpc_mobile_scanner.git`
  * `git clone https://gitcode.com/openharmony-sig/fluttertpc_device_calendar`
6. 如果在中国大陆网络下载失败，执行：
  * `export USE_CN_FLUTTER_MIRROR=1`
  * `source tool/setup_ohos_env.sh`

### 快速切换构建环境

为了在 Android/iOS 与 OHOS 间减少手动操作，可在当前终端直接切换：

* 切到 OHOS 构建环境：`source tool/switch_flutter_env.sh ohos`
* 切回官方 Flutter（Android/iOS 常用）：`source tool/switch_flutter_env.sh official`

切换后建议运行 `flutter doctor -v` 或 `fvm flutter doctor -v` 做一次确认，并执行 `flutter clean` 以清除之前环境的构建缓存。
