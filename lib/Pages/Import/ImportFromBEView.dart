import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Utils/Analytics.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:scoped_model/scoped_model.dart';
import '../../Components/Dialog.dart';
import '../../Components/TransBgTextButton.dart';
import '../../Utils/States/MainState.dart';
import '../../generated/l10n.dart';
import '../../Components/Toast.dart';
import '../../Resources/Config.dart';
import '../../Resources/Url.dart';
import '../../Utils/OnlineImportService.dart';
import '../../Utils/ImportTestScript.dart';

class ImportFromBEView extends StatefulWidget {
  final String? title;
  final Map config;
  final bool testMode;

  const ImportFromBEView({
    Key? key,
    this.title,
    required this.config,
    this.testMode = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return ImportFromBEViewState();
  }
}

class ImportFromBEViewState extends State<ImportFromBEView> {
  late final WebViewController _webViewController;
  final WebViewCookieManager cookieManager = WebViewCookieManager();

  bool _extracting = false;
  bool _completed = false;
  bool _pageLoading = true;
  // Guards the manual import UI so repeated navigation events only prompt once.
  bool _manualImportPromptShown = false;
  String? _testStatus;
  String? _testUrl;
  String? _testJsError;

  @override
  void initState() {
    super.initState();

    _webViewController =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0x00000000))
          ..setUserAgent(
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          )
          ..addJavaScriptChannel(
            'SnackbarJSChannel',
            onMessageReceived: (JavaScriptMessage message) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message.message)));
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
              onPageStarted: (url) {
                _pageLoading = true;
                _recordTestNavigation(url);
              },
              onPageFinished: (String url) {
                _pageLoading = false;
                _recordTestNavigation(url);
                _handleImportUrl(url);
              },
              onUrlChange: (change) {
                if (change.url != null) _recordTestNavigation(change.url!);
                // History API navigation does not finish a new page load.
                // Full navigation still waits for onPageFinished so scripts
                // run in the destination document, rather than the old page.
                if (!_pageLoading && change.url != null) {
                  _handleImportUrl(change.url!);
                }
              },
            ),
          );

    // 启用第三方 Cookie 支持
    _enableThirdPartyCookies();
  }

  void _recordTestNavigation(String url) {
    if (!mounted || !widget.testMode) return;
    setState(() {
      _testUrl = url;
      if (!_extracting) {
        _testStatus =
            _pageLoading
                ? S.of(context).import_test_loading
                : S.of(context).import_test_waiting_url;
      }
    });
  }

  void _testStep(String status) {
    if (mounted && widget.testMode) {
      setState(() => _testStatus = status);
    }
  }

  String get _testAddress {
    // Login tickets and fragments are unnecessary for matching diagnosis.
    return (_testUrl ?? widget.config['initialUrl'])
        .toString()
        .split('?')
        .first
        .split('#')
        .first;
  }

  Future<void> _runTestPreScript(
    WebViewController controller,
    String script,
  ) async {
    // Android does not propagate JS exceptions. A final marker verifies that
    // the script completed, while preserving its global declaration scope.
    // Avoid eval()/Function(), which the portal's CSP may forbid.
    const marker = 'NJU_IMPORT_PRE_COMPLETED';
    dynamic result = await controller
        .runJavaScriptReturningResult('$script\n;"$marker";')
        .timeout(const Duration(seconds: 30));
    for (var i = 0; i < 4 && result is String; i++) {
      try {
        result = jsonDecode(result);
      } on FormatException {
        break;
      }
    }
    if (result != marker) {
      throw FormatException(
        _testJsError != null
            ? 'preExtractJS: $_testJsError'
            : S.of(context).import_test_script_invalid,
      );
    }
  }

  void _handleImportUrl(String url) {
    if (!mounted || _completed || _extracting) return;
    final target = (widget.config['targetUrl'] ?? '').toString();
    final redirect = (widget.config['redirectUrl'] ?? '').toString();
    // A target may share the redirect prefix; extract before redirecting.
    if (target.isNotEmpty && url.startsWith(target)) {
      if (!widget.testMode && widget.config['manualImport'] == true) {
        _startManualImport();
      } else {
        import(_webViewController, context);
      }
    } else if (target.isNotEmpty &&
        redirect.isNotEmpty &&
        url.startsWith(redirect)) {
      _pageLoading = true;
      _webViewController.loadRequest(Uri.parse(target));
    }
  }

  /// Manual import keeps the user on the page until they confirm, so the
  /// selected semester and the page state stay under their control.
  void _startManualImport() {
    if (widget.config['manualTermSelection'] == false) {
      _injectManualImportButton();
    } else {
      _showManualImportTermDialog();
    }
  }

  Future<void> _enableThirdPartyCookies() async {
    if (Platform.isAndroid) {
      final AndroidWebViewController androidController =
          _webViewController.platform as AndroidWebViewController;
      final AndroidWebViewCookieManager androidCookieManager =
          cookieManager.platform as AndroidWebViewCookieManager;
      await androidCookieManager.setAcceptThirdPartyCookies(
        androidController,
        true,
      );
      if (widget.testMode) {
        await androidController.setOnConsoleMessage((message) {
          if (_extracting && message.level == JavaScriptLogLevel.error) {
            _testJsError = message.message;
          }
        });
      }
    }
    // 等待第三方 cookie 设置完成后再加载页面
    if (mounted) {
      await _webViewController.loadRequest(
        Uri.parse(widget.config['initialUrl']),
      );
    }
  }

  /// Loads a configured script, preferring the bundled copy while developing
  /// against `api/` so import changes can be tested without a CDN round trip.
  Future<String> _loadConfiguredJavaScript(String url) async {
    if (url.isEmpty) return '';

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

    final serverRsp = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
      ),
    ).get<String>(url);
    return serverRsp.data ?? '';
  }

  /// Decodes a raw `runJavaScriptReturningResult` value into its string form.
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
    final manualTermScript =
        widget.config['manualTermScript']?.toString() ?? '';
    if (manualTermScript.isEmpty) return [];

    final script = await _loadConfiguredJavaScript(manualTermScript);
    if (script.isEmpty) return [];
    final result =
        await _webViewController.runJavaScriptReturningResult(script);

    final decoded = json.decode(_decodeJavaScriptStringResult(result));
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((term) => Map<String, dynamic>.from(term))
        .where((term) => (term['dm']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> _selectManualImportTerm(
    List<Map<String, dynamic>> terms,
  ) async {
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
                      child: RadioGroup<int>(
                        groupValue: selectedIndex,
                        onChanged: (int? value) {
                          if (value == null) return;
                          setDialogState(() => selectedIndex = value);
                        },
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
                              title: Text(term['name']?.toString() ?? dm),
                              subtitle: Text(subtitle),
                            );
                          },
                        ),
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
                  onPressed: () => Navigator.of(dialogContext).pop(selectedTerm),
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
})($payload);
''');
  }

  Future<void> _showManualImportTermDialog() async {
    if (_manualImportPromptShown || _extracting || _completed || !mounted) {
      return;
    }
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
    var injectedTerm = window.__course_import_selected_term__;
    var termText = injectedTerm && (injectedTerm.name || injectedTerm.MC)
      ? (injectedTerm.name || injectedTerm.MC).toString().trim()
      : '';
    if (!termText) {
      var selected = document.querySelector('[aria-selected="true"]') ||
        document.querySelector('.jqx-listitem-state-selected');
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
          if (widget.testMode)
            IconButton(
              key: const ValueKey('import-test-retry'),
              tooltip: S.of(context).import_test_retry,
              icon: const Icon(Icons.play_arrow),
              onPressed:
                  _extracting
                      ? null
                      : () => import(_webViewController, context),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed:
                widget.testMode && _extracting
                    ? null
                    : () async {
                      _manualImportPromptShown = false;
                      await cookieManager.clearCookies();
                      _webViewController.loadRequest(
                        Uri.parse(widget.config['initialUrl']),
                      );
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
          return Column(
            children: <Widget>[
              if (widget.testMode)
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _testStatus ?? S.of(context).import_test_loading,
                          key: const ValueKey('import-test-status'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _testAddress.replaceFirstMapped(
                                  RegExp(r'/(https?)/[a-f0-9]{30,}/'),
                                  (match) => '/${match[1]}/…/',
                                ),
                                key: const ValueKey('import-test-current-url'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  MaterialLocalizations.of(
                                    context,
                                  ).copyButtonLabel,
                              onPressed:
                                  () => Clipboard.setData(
                                    ClipboardData(text: _testAddress),
                                  ),
                              icon: const Icon(Icons.copy, size: 18),
                            ),
                          ],
                        ),
                        if (_extracting &&
                            _testStatus != S.of(context).import_test_error)
                          const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
              widget.config['banner_content'] == null
                  ? Container()
                  : MaterialBanner(
                    forceActionsBelow: true,
                    content: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.config['banner_content'],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    backgroundColor: Theme.of(context).primaryColor,
                    actions: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Theme.of(context).primaryColor,
                        ),
                        child: Text(widget.config['banner_action']),
                        onPressed:
                            () => launchUrl(
                              Uri.parse(widget.config['banner_url']),
                            ),
                      ),
                    ],
                  ),
              Expanded(child: WebViewWidget(controller: _webViewController)),
            ],
          );
        },
      ),
    );
  }

  import(
    WebViewController controller,
    BuildContext context, {
    String? rsp,
  }) async {
    if (_extracting || _completed || !mounted) return;
    _extracting = true;
    _testJsError = null;
    _testStep(S.of(context).import_test_preparing);
    try {
      if (!widget.testMode) {
        Toast.showToast(S.of(context).class_parse_toast_importing, context);
      }
      Object response;
      if (rsp != null) {
        response = rsp;
      } else {
        final pre = (widget.config['preExtractJS'] ?? '').toString();
        if (pre.isNotEmpty) {
          if (widget.testMode) {
            await _runTestPreScript(controller, pre);
          } else {
            await controller.runJavaScript(pre);
          }
        }
        if (!mounted) return;
        _testStep(
          '${S.of(context).import_test_delay} (${widget.config['delayTime'] ?? 0}s)',
        );
        await Future.delayed(
          Duration(seconds: widget.config['delayTime'] ?? 0),
        );
        if (!mounted) return;
        _testStep(S.of(context).import_test_extracting);
        _testJsError = null;
        String js;
        if (widget.testMode) {
          js = widget.config['extractJS'] as String;
        } else {
          final key =
              Platform.isIOS
                  ? 'extractJSfileiOS'
                  : Platform.isAndroid
                  ? 'extractJSfileAndroid'
                  : 'extractJSfileOHOS';
          final url =
              widget.config[key] ?? widget.config['extractJSfile'] ?? '';
          js = await _loadConfiguredJavaScript(url);
        }
        if (!mounted) return;
        final execution = controller.runJavaScriptReturningResult(
          widget.testMode ? guardImportTestExtraction(js) : js,
        );
        response =
            widget.testMode
                ? await execution.timeout(const Duration(seconds: 60))
                : await execution;
        if (widget.testMode && mounted) {
          validateImportTestExtraction(
            response,
            emptyResultMessage: S.of(context).import_test_extract_empty,
          );
        }
      }
      final data = decodeOnlineImportResult(response);
      if (!mounted) return;
      _testStep(S.of(context).import_test_saving);
      final state = ScopedModel.of<MainStateModel>(context);
      final index = await saveOnlineImport(data, widget.config);
      _completed = true;
      await state.changeclassTable(index);
      if (!widget.testMode) {
        Analytics.onEvent('class_import', {
          'type': 'be',
          'action': 'success',
        });
      }
      if (!mounted) return;
      Toast.showToast(S.of(context).class_parse_toast_success, context);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!widget.testMode) {
        await _resetManualImportButton();
      }
      if (!mounted) return;
      if (widget.testMode) {
        final failedStep = _testStatus;
        _testStep(S.of(context).import_test_error);
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: Text(S.of(context).import_test_error),
                content: SingleChildScrollView(
                  child: SelectableText(
                    [
                      if (failedStep != null) failedStep,
                      e.toString(),
                      if (_testJsError != null &&
                          !e.toString().contains(_testJsError!))
                        _testJsError!,
                    ].join('\n'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(
                      MaterialLocalizations.of(context).closeButtonLabel,
                    ),
                  ),
                ],
              ),
        );
        return;
      }
      var result = await controller.runJavaScriptReturningResult(
        "window.document.getElementsByTagName('html')[0].outerHTML;",
      );
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
        "way": "be",
      };

      try {
        await Dio().post(
          Url.URL_BACKEND + "/log/log",
          data: FormData.fromMap(info),
        );
      } catch (_) {}

      Analytics.onEvent("class_import", {"type": "be", "action": "fail"});

      if (!mounted) return;
      await showDialog<String>(
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
                  color:
                      Theme.of(context).brightness == Brightness.light
                          ? Theme.of(context).primaryColor
                          : Colors.white,
                  child: Text(S.of(context).parse_error_dialog_add_group),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: errorCode));
                    if (Platform.isIOS) {
                      launchUrl(Uri.parse(Url.QQ_GROUP_APPLE_URL));
                    } else if (Platform.isAndroid) {
                      launchUrl(Uri.parse(Url.QQ_GROUP_ANDROID_URL));
                    } else if (Platform.operatingSystem == 'ohos') {
                      launchUrl(Uri.parse(Url.QQ_GROUP_OHOS_URL));
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ),
              Container(
                alignment: Alignment.centerRight,
                child: TransBgTextButton(
                  color: Colors.grey,
                  child: Text(
                    S.of(context).parse_error_dialog_other_ways,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          );
        },
      );
      return;
    } finally {
      _extracting = false;
      if (mounted && widget.testMode) setState(() {});
    }
  }
}
