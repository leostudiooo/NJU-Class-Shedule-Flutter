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
import '../../Resources/Config.dart';
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
  bool _manualImportPromptShown = false;

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
                if (widget.config['manualTermSelection'] == false) {
                  _injectManualImportButton();
                } else {
                  _showManualImportTermDialog();
                }
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

  Future<String> _loadExtractJavaScript(String url) async {
    if (Config.USE_LOCAL_IMPORT_CONFIG) {
      final uri = Uri.tryParse(url);
      final fileName =
          uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';

      if (fileName.isNotEmpty) {
        try {
          return await rootBundle.loadString('api/tools/$fileName');
        } catch (_) {}
      }
    }

    Response serverRsp = await Dio().get(url);
    return serverRsp.data.toString();
  }

  String _decodeJavaScriptStringResult(Object? result) {
    if (result == null) return '';

    String value = result.toString();
    try {
      final decoded = json.decode(value);
      if (decoded is String) {
        value = decoded;
      }
    } catch (_) {
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
    }

    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  Future<List<Map<String, dynamic>>> _loadManualImportTerms() async {
    final result = await _webViewController.runJavaScriptReturningResult(r'''
(function() {
  var CONFIG = {
    APP_BASE: 'https://ehall.seu.edu.cn/jwapp/sys/bykb',
    CURRENT_TERM_API: '/modules/jshkcb/dqxnxq.do',
    TERM_LIST_API: '/modules/jshkcb/xnxqcx.do',
    SEMESTER_CALENDAR_API: '/modules/xskcb/cxxljc.do'
  };

  function buildUrl(path) {
    if (typeof WIS_EMAP_SERV !== 'undefined' && WIS_EMAP_SERV.getAbsPath) {
      return WIS_EMAP_SERV.getAbsPath(path);
    }
    return CONFIG.APP_BASE + path;
  }

  function encodeParams(params) {
    return Object.keys(params || {}).map(function(key) {
      return encodeURIComponent(key) + '=' + encodeURIComponent(params[key]);
    }).join('&');
  }

  function syncRequest(path, params) {
    var url = buildUrl(path);
    if (typeof BH_UTILS !== 'undefined' && BH_UTILS.doSyncAjax) {
      return BH_UTILS.doSyncAjax(url, params || {});
    }

    var xhr = new XMLHttpRequest();
    xhr.open('POST', url, false);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    xhr.setRequestHeader('Accept', 'application/json, text/javascript, */*; q=0.01');
    xhr.send(encodeParams(params || {}));
    if (xhr.status !== 200) throw new Error('HTTP Error: ' + xhr.status);
    return JSON.parse(xhr.responseText);
  }

  function extractRows(data, tableName) {
    return data && data.datas && data.datas[tableName] && data.datas[tableName].rows
      ? data.datas[tableName].rows
      : [];
  }

  function getJqxSelectedItem(selector) {
    try {
      if (typeof $ === 'undefined' || !$(selector).jqxDropDownList) return null;
      return $(selector).jqxDropDownList('getSelectedItem');
    } catch (error) {
      return null;
    }
  }

  function getSelectedTerm() {
    var injected = window.__course_import_selected_term__;
    if (injected && (injected.dm || injected.DM)) {
      return { dm: injected.dm || injected.DM, name: injected.name || injected.MC || '' };
    }

    var termEl = document.querySelector('#dqxnxq2');
    var selectedItem = getJqxSelectedItem('.dropdowm-xnxqList2') || getJqxSelectedItem('#dqxnxq2');
    var dm = selectedItem && (selectedItem.value || (selectedItem.originalItem && selectedItem.originalItem.DM));
    var name = selectedItem && (selectedItem.label || (selectedItem.originalItem && selectedItem.originalItem.MC));

    if (!dm && termEl) dm = termEl.getAttribute('value') || termEl.value || '';
    if (!name && termEl) name = termEl.textContent ? termEl.textContent.trim() : '';
    if (dm || name) return { dm: dm || '', name: name || '' };

    try {
      var currentRows = extractRows(syncRequest(CONFIG.CURRENT_TERM_API, {}), 'dqxnxq');
      if (currentRows.length > 0) return { dm: currentRows[0].DM || '', name: currentRows[0].MC || '' };
    } catch (error) {}

    return { dm: '', name: '' };
  }

  function parseTermCode(dm) {
    var parts = String(dm || '').split('-');
    if (parts.length < 3) return null;
    return { xn: parts[0] + '-' + parts[1], xq: parts.slice(2).join('-') };
  }

  function getSemesterCalendar(dm) {
    var parts = parseTermCode(dm);
    if (!parts) return null;
    var rows = extractRows(syncRequest(CONFIG.SEMESTER_CALENDAR_API, {
      XN: parts.xn,
      XQ: parts.xq
    }), 'cxxljc');
    return rows.length > 0 ? rows[0] : null;
  }

  var selected = getSelectedTerm();
  var termRows = extractRows(syncRequest(CONFIG.TERM_LIST_API, { '*order': '-DM' }), 'xnxqcx');
  var terms = termRows.map(function(row) {
    var parts = parseTermCode(row.DM);
    var calendar = null;
    try { calendar = getSemesterCalendar(row.DM); } catch (error) {}

    return {
      dm: row.DM || '',
      name: row.MC || '',
      xn: parts ? parts.xn : row.XNDM || '',
      xq: parts ? parts.xq : row.XQDM || '',
      start: calendar && calendar.XQKSRQ ? String(calendar.XQKSRQ).slice(0, 10) : null,
      weeks: calendar && calendar.ZZC != null ? calendar.ZZC : null,
      teachingWeeks: calendar && calendar.ZJXZC != null ? calendar.ZJXZC : null,
      selected: (selected.dm && selected.dm === row.DM) || (!selected.dm && selected.name && selected.name === row.MC)
    };
  }).filter(function(term) { return term.dm; });

  return encodeURIComponent(JSON.stringify(terms));
})()
''');

    final response = _decodeJavaScriptStringResult(result);
    final terms = json.decode(response);
    if (terms is! List) return [];

    return terms
        .whereType<Map>()
        .map((term) => Map<String, dynamic>.from(term))
        .toList();
  }

  Future<Map<String, dynamic>?> _selectManualImportTerm(
      List<Map<String, dynamic>> terms) async {
    int selectedIndex = terms.indexWhere((term) => term['selected'] == true);
    if (selectedIndex < 0) {
      selectedIndex = terms.indexWhere((term) => term['start'] != null);
    }
    if (selectedIndex < 0 && terms.isNotEmpty) selectedIndex = 0;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            final selectedTerm = terms[selectedIndex];
            final dialogHeight =
                MediaQuery.of(dialogContext).size.height * 0.56;
            final listHeight = dialogHeight > 420.0 ? 420.0 : dialogHeight;

            return AlertDialog(
              title: const Text('选择要导入的学期'),
              content: SizedBox(
                width: double.maxFinite,
                height: listHeight,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: terms.length,
                        itemBuilder: (BuildContext context, int index) {
                          final term = terms[index];
                          final start = term['start']?.toString();
                          final dm = term['dm']?.toString() ?? '';
                          final subtitle = start == null || start.isEmpty
                              ? '$dm · 开学日期未发布'
                              : '$dm · 开学：$start';

                          return RadioListTile<int>(
                            dense: true,
                            value: index,
                            groupValue: selectedIndex,
                            title: Text(term['name']?.toString() ?? dm),
                            subtitle: Text(subtitle),
                            onChanged: (int? value) {
                              if (value == null) return;
                              setDialogState(() => selectedIndex = value);
                            },
                          );
                        },
                      ),
                    ),
                    if (selectedTerm['start'] == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          '该学期暂无开学日期，导入后可能需要手动校准当前周。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _manualImportPromptShown = false;
                    Navigator.of(dialogContext).pop(null);
                  },
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(selectedTerm),
                  child: const Text('确认抓取'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _applyManualImportTerm(Map<String, dynamic> term) async {
    final dm = term['dm']?.toString() ?? '';
    final name = term['name']?.toString() ?? '';
    final start = term['start']?.toString();
    final payload = json.encode({
      'dm': dm,
      'DM': dm,
      'name': name,
      'MC': name,
      'xn': term['xn'],
      'xq': term['xq'],
      'semester_start_monday': start,
      'semesterStartMonday': start,
    });

    await _webViewController.runJavaScript('''
(function(term) {
  window.__course_import_selected_term__ = term;
  var termEl = document.querySelector('#dqxnxq2');
  if (termEl) {
    termEl.setAttribute('value', term.dm || term.DM || '');
    if (term.name || term.MC) termEl.textContent = term.name || term.MC;
  }
})($payload);
''');
  }

  Future<void> _showManualImportTermDialog() async {
    if (_manualImportPromptShown || _isImporting || !mounted) return;
    _manualImportPromptShown = true;

    try {
      final terms = await _loadManualImportTerms();
      if (!mounted) return;

      if (terms.isEmpty) {
        Toast.showToast('未读取到学期列表，请在页面中选择学期后导入', context);
        await _injectManualImportButton();
        return;
      }

      final selectedTerm = await _selectManualImportTerm(terms);
      if (!mounted || selectedTerm == null) return;

      await _applyManualImportTerm(selectedTerm);
      if (!mounted) return;
      await import(_webViewController, context);
    } catch (_) {
      _manualImportPromptShown = false;
      if (mounted) {
        Toast.showToast('读取学期失败，请在页面中选择学期后导入', context);
      }
      await _injectManualImportButton();
    }
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
              _manualImportPromptShown = false;
              _isImporting = false;
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
        String url = '';
        if (Platform.isIOS) {
          url = widget.config['extractJSfileiOS'] ?? "";
        } else if (Platform.isAndroid) {
          url = widget.config['extractJSfileAndroid'] ?? "";
        } else if (Platform.operatingSystem == 'ohos') {
          url = widget.config['extractJSfileOHOS'] ?? "";
        }

        String js = await _loadExtractJavaScript(url);
        var result = await controller.runJavaScriptReturningResult(js);
        response = _decodeJavaScriptStringResult(result);
      } else {
        response = _decodeJavaScriptStringResult(rsp);
      }

      Map courseTableMap = json.decode(response);

      Map data = {};
      final classTimeList =
          courseTableMap['class_time_list'] ?? widget.config['class_time_list'];
      final hasExtractedSemesterStart =
          courseTableMap.containsKey('semester_start_monday');
      final semesterStartMonday = hasExtractedSemesterStart
          ? courseTableMap['semester_start_monday']
          : (widget.config['manualImport'] == true
              ? null
              : widget.config['semester_start_monday']);
      if (classTimeList != null) {
        data["class_time_list"] = classTimeList;
      }
      if (semesterStartMonday != null &&
          semesterStartMonday.toString().isNotEmpty) {
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
