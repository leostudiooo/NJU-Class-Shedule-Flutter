import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:scoped_model/scoped_model.dart';
import '../../Components/Dialog.dart';
import '../../Components/TransBgTextButton.dart';
import '../../Utils/States/MainState.dart';
import '../../generated/l10n.dart';
import '../../Components/Toast.dart';
import '../../Models/CourseModel.dart';
import '../../Models/CourseTableModel.dart';
import '../../Resources/Url.dart';
import '../../Utils/CourseImportCodec.dart';

class ImportFromBEView extends StatefulWidget {
  final String? title;
  final Map config;

  const ImportFromBEView({Key? key, this.title, required this.config})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return ImportFromBEViewState();
  }
}

class ImportFromBEViewState extends State<ImportFromBEView> {
  late final WebViewController _webViewController;
  final WebViewCookieManager cookieManager = WebViewCookieManager();
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..addJavaScriptChannel(
        'SnackbarJSChannel',
        onMessageReceived: (JavaScriptMessage message) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(message.message),
          ));
        },
      )
      ..addJavaScriptChannel(
        'CourseImportJSChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'import') {
            import(_webViewController, context);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (widget.config['redirectUrl'] != '' &&
                url.startsWith(widget.config['redirectUrl'])) {
              _webViewController
                  .loadRequest(Uri.parse(widget.config['targetUrl']));
            } else if (url.startsWith(widget.config['targetUrl'])) {
              if (widget.config['manualImport'] == true) {
                _injectManualImportButton();
              } else {
                import(_webViewController, context);
              }
            }
          },
        ),
      );

    // 启用第三方 Cookie 支持
    _enableThirdPartyCookies();
  }

  Future<void> _enableThirdPartyCookies() async {
    if (Platform.isAndroid) {
      final AndroidWebViewController androidController =
          _webViewController.platform as AndroidWebViewController;
      final AndroidWebViewCookieManager androidCookieManager =
          cookieManager.platform as AndroidWebViewCookieManager;
      await androidCookieManager.setAcceptThirdPartyCookies(
          androidController, true);
    }
    // 等待第三方 cookie 设置完成后再加载页面
    _webViewController.loadRequest(Uri.parse(widget.config['initialUrl']));
  }

  Future<void> _injectManualImportButton() async {
    await _webViewController.runJavaScript('''
(function() {
  if (window.__course_import_manual_button_installed__) return;
  window.__course_import_manual_button_installed__ = true;

  function getSelectedTermText() {
    var termEl = document.querySelector('#dqxnxq2');
    var termText = termEl && termEl.textContent ? termEl.textContent.trim() : '';
    if (!termText) {
      var selected = document.querySelector('.jqx-listitem-state-selected');
      termText = selected && selected.textContent ? selected.textContent.trim() : '';
    }
    return termText || '当前页面学期';
  }

  function installButton() {
    if (!document.body) return false;

    var panel = document.createElement('div');
    panel.id = 'course-import-manual-panel';
    panel.style.cssText = [
      'position:fixed',
      'right:16px',
      'bottom:20px',
      'z-index:2147483647',
      'display:flex',
      'flex-direction:column',
      'gap:8px',
      'align-items:flex-end',
      'font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif'
    ].join(';');

    var preview = document.createElement('div');
    preview.id = 'course-import-term-preview';
    preview.style.cssText = [
      'max-width:260px',
      'padding:7px 10px',
      'border-radius:10px',
      'background:rgba(0,0,0,.72)',
      'color:#fff',
      'font-size:12px',
      'line-height:1.35',
      'box-shadow:0 4px 14px rgba(0,0,0,.18)'
    ].join(';');

    var button = document.createElement('button');
    button.type = 'button';
    button.id = 'course-import-confirm-button';
    button.textContent = '确认导入课表';
    button.style.cssText = [
      'height:44px',
      'padding:0 18px',
      'border:none',
      'border-radius:22px',
      'background:#1976d2',
      'color:#fff',
      'font-size:15px',
      'font-weight:600',
      'box-shadow:0 6px 18px rgba(25,118,210,.35)'
    ].join(';');
    button.onclick = function() {
      button.disabled = true;
      button.textContent = '正在导入...';
      CourseImportJSChannel.postMessage('import');
    };

    function refreshPreview() {
      preview.textContent = '将导入：' + getSelectedTermText();
    }

    panel.appendChild(preview);
    panel.appendChild(button);
    document.body.appendChild(panel);
    refreshPreview();
    window.setInterval(refreshPreview, 800);
    return true;
  }

  if (!installButton()) {
    var timer = window.setInterval(function() {
      if (installButton()) window.clearInterval(timer);
    }, 500);
  }
})();
''');
  }

  Future<void> _resetManualImportButton() async {
    if (widget.config['manualImport'] != true) return;

    try {
      await _webViewController.runJavaScript('''
(function() {
  var button = document.querySelector('#course-import-confirm-button');
  if (!button) return;
  button.disabled = false;
  button.textContent = '确认导入课表';
})();
''');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config['page_title']),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await cookieManager.clearCookies();
              _webViewController
                  .loadRequest(Uri.parse(widget.config['initialUrl']));
            },
          ),
          // IconButton(
          //   icon: const Icon(Icons.gamepad),
          //   onPressed: () async {
          //     String rsp = "";
          //     import(_webViewController, context, rsp: rsp);
          //   },
          // )
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          return Column(children: <Widget>[
            widget.config['banner_content'] == null
                ? Container()
                : MaterialBanner(
                    forceActionsBelow: true,
                    content: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(widget.config['banner_content'],
                            style: const TextStyle(color: Colors.white))),
                    backgroundColor: Theme.of(context).primaryColor,
                    actions: [
                      TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Theme.of(context).primaryColor),
                          child: Text(widget.config['banner_action']),
                          onPressed: () => launch(widget.config['banner_url'])),
                    ],
                  ),
            Expanded(child: WebViewWidget(controller: _webViewController))
          ]);
        },
      ),
    );
  }

  import(WebViewController controller, BuildContext context,
      {String? rsp}) async {
    if (_isImporting) return;
    _isImporting = true;

    try {
      String response = "";
      CourseTableProvider courseTableProvider = CourseTableProvider();
      Toast.showToast(S.of(context).class_parse_toast_importing, context);

      if (rsp == null) {
        await controller.runJavaScript(widget.config['preExtractJS'] ?? '');
        await Future.delayed(
            Duration(seconds: widget.config['delayTime'] ?? 0));
        Dio dio = Dio();

        String url = '';
        if (Platform.isIOS) {
          url = widget.config['extractJSfileiOS'] ?? "";
          ;
        } else if (Platform.isAndroid) {
          url = widget.config['extractJSfileAndroid'] ?? "";
        } else if (Platform.operatingSystem == 'ohos') {
          url = widget.config['extractJSfileOHOS'] ?? "";
        }

        Response serverRsp = await dio.get(url);
        String js = serverRsp.data;
        var result = await controller.runJavaScriptReturningResult(js);
        response = result.toString();

        if (response.startsWith('"') && response.endsWith('"')) {
          response = response.substring(1, response.length - 1);
        }
      } else {
        response = rsp;
      }

      response = Uri.decodeComponent(response.replaceAll('"', ''));
      Map courseTableMap = json.decode(response);

      Map data = {};
      final classTimeList =
          courseTableMap['class_time_list'] ?? widget.config['class_time_list'];
      final semesterStartMonday = courseTableMap['semester_start_monday'] ??
          widget.config['semester_start_monday'];
      if (classTimeList != null) {
        data["class_time_list"] = classTimeList;
      }
      if (semesterStartMonday != null) {
        data["semester_start_monday"] = semesterStartMonday;
      }

      CourseTable courseTable;
      if (data.isEmpty) {
        courseTable = await courseTableProvider
            .insert(CourseTable(courseTableMap['name']));
      } else {
        try {
          String dataString = json.encode(data);
          courseTable = await courseTableProvider
              .insert(CourseTable(courseTableMap['name'], data: dataString));
        } catch (e) {
          courseTable = await courseTableProvider
              .insert(CourseTable(courseTableMap['name']));
        }
      }
      int index = (courseTable.id!);
      CourseProvider courseProvider = CourseProvider();
      await ScopedModel.of<MainStateModel>(context).changeclassTable(index);
      Iterable courses;
      if (courseTableMap['courses'].runtimeType != String) {
        courses = courseTableMap['courses'];
      } else if (json.decode(courseTableMap['courses']).runtimeType != String) {
        courses = json.decode(courseTableMap['courses']);
      } else {
        courses = json.decode(json.decode(courseTableMap['courses']));
      }
      List<Map<String, dynamic>> coursesMap =
          List<Map<String, dynamic>>.from(courses);
      for (var courseMap in coursesMap) {
        final dbMap =
            CourseImportCodec.onlineCourseToDbMap(courseMap, tableId: index);
        Course course = Course.fromMap(dbMap);
        await courseProvider.insert(course);
      }
      UmengCommonSdk.onEvent(
          "class_import", {"type": "be", "action": "success"});
      Toast.showToast(S.of(context).class_parse_toast_success, context);
      Navigator.of(context).pop(true);
    } catch (e) {
      _isImporting = false;
      await _resetManualImportButton();
      var result = await controller.runJavaScriptReturningResult(
          "window.document.getElementsByTagName('html')[0].outerHTML;");
      String response = result.toString();
      String url = await controller.currentUrl() ?? "";

      String now = DateTime.now().toString();
      String errorCode = now
          .replaceAll("-", "")
          .replaceAll(":", "")
          .replaceAll(" ", "")
          .replaceAll(".", "");
      Map<String, String> info = {
        "errorCode": errorCode,
        "response": response,
        "errorMsg": e.toString(),
        "url": url,
        "way": "be"
      };

      try {
        await Dio()
            .post(Url.URL_BACKEND + "/log/log", data: FormData.fromMap(info));
      } catch (_) {}

      UmengCommonSdk.onEvent("class_import", {"type": "be", "action": "fail"});

      showDialog<String>(
          barrierDismissible: false,
          context: context,
          builder: (BuildContext context) {
            return MDialog(
              S.of(context).parse_error_dialog_title,
              Text(S.of(context).parse_error_dialog_content(errorCode)),
              overrideActions: <Widget>[
                Container(
                    alignment: Alignment.centerRight,
                    child: TransBgTextButton(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).primaryColor
                            : Colors.white,
                        child: Text(S.of(context).parse_error_dialog_add_group),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: errorCode));
                          if (Platform.isIOS) {
                            launch(Url.QQ_GROUP_APPLE_URL);
                          } else if (Platform.isAndroid) {
                            launch(Url.QQ_GROUP_ANDROID_URL);
                          } else if (Platform.operatingSystem == 'ohos') {
                            launch(Url.QQ_GROUP_OHOS_URL);
                          }
                          Navigator.of(context).pop();
                        })),
                Container(
                    alignment: Alignment.centerRight,
                    child: TransBgTextButton(
                        color: Colors.grey,
                        child: Text(S.of(context).parse_error_dialog_other_ways,
                            style: const TextStyle(color: Colors.grey)),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                        }))
              ],
            );
          });
      return;
    }
  }
}
