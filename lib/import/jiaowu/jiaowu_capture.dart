/// 教务系统课表页抓取（架构移植，非代码拷贝）。
///
/// **来源声明**（AGENTS.md 禁止事项）：思路取自 WakeUp 课程表反编译产物
/// `F:\Code\APK-MCP\3-Wakeup\Gradle\app\src\main\java\com\suda\net\schedule_import\`
/// ——`WebViewLoginFragment.java:621`（`getPageHtml` 递归抓 iframe/frame 的
/// innerHTML）与 `:1139`（把渲染后的 DOM 回传给解析层）。这里只借「用户在
/// WebView 里自己登录 → 把当前页渲染后的 HTML 取回来」这一步，未拷贝其 Java
/// 代码，也不引入它的任何第三方库。
///
/// 为什么先落盘而不是直接解析：强智（`/jsxsd/`）课表页的真实表格结构还没拿到
/// 过样本，凭空气写解析器就是猜。抓到样本后，解析器按 WakeUp 的 `qz` 系
/// （`schedule_parser/parser/base/OooOOO0.java:309` 等）逐格对齐再补。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/jiaowu/jiaowu_qz.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 用户 2026-10-18 定的入口：学校主页，登录与导航由他自己在页面里做。
const String kJiaowuEntryUrl = 'https://www.nchu.edu.cn/';

/// 递归取当前文档 HTML；跨域 iframe 取不到时留下标记，不静默丢。
const String _kHarvestJs = '''
(function () {
  function walk(doc) {
    var out = '';
    try { out += (doc && doc.body) ? doc.body.innerHTML : ''; } catch (e) {}
    var frames = doc ? doc.querySelectorAll('iframe,frame') : [];
    for (var i = 0; i < frames.length; i++) {
      try {
        var d = frames[i].contentDocument;
        if (d) { out += '\\n<!--FRAME ' + frames[i].src + '-->\\n' + walk(d); }
      } catch (e) {
        out += '\\n<!--FRAME-BLOCKED ' + frames[i].src + '-->\\n';
      }
    }
    return out;
  }
  return JSON.stringify({url: location.href, title: document.title,
                         html: walk(document)});
})()
''';

Future<ScheduleTable?> showJiaowuCapture(BuildContext context) =>
    Navigator.of(context).push<ScheduleTable>(MaterialPageRoute<ScheduleTable>(
        builder: (BuildContext _) => const JiaowuCapturePage()));

class JiaowuCapturePage extends StatefulWidget {
  const JiaowuCapturePage({super.key});

  @override
  State<JiaowuCapturePage> createState() => _JiaowuCapturePageState();
}

class _JiaowuCapturePageState extends State<JiaowuCapturePage> {
  final TextEditingController _url = TextEditingController(text: kJiaowuEntryUrl);
  InAppWebViewController? _controller;
  String _currentUrl = kJiaowuEntryUrl;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('从教务系统抓取'),
        actions: <Widget>[
          IconButton(
            tooltip: '抓当前页',
            icon: Icon(Icons.download, color: colors.textSecondary),
            onPressed: _busy ? null : _capture,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _url,
                    style: AppTypography.meta,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                    onPressed: _goto, child: const Text('前往')),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '在这个页面里登录教务系统，导航到「学生课表」页，再点右上「抓当前页」。'
              '抓到的 HTML 存到应用目录，解析器对着真实样本写。',
              style: AppTypography.meta.copyWith(color: colors.textSecondary)),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(kJiaowuEntryUrl)),
              initialSettings:
                  InAppWebViewSettings(javaScriptEnabled: true),
              onWebViewCreated: (InAppWebViewController c) => _controller = c,
              onLoadStop:
                  (InAppWebViewController _, WebUri? u) => setState(
                      () => _currentUrl = u?.toString() ?? _currentUrl),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _goto() async {
    final String url = _url.text.trim();
    if (url.isEmpty) return;
    await _controller?.loadUrl(
        urlRequest: URLRequest(
            url: WebUri(url.startsWith('http') ? url : 'http://$url')));
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final Object? raw =
          await _controller?.evaluateJavascript(source: _kHarvestJs);
      final Map<String, Object?> doc =
          (jsonDecode(raw as String) as Map<Object?, Object?>).cast();
      final String html = doc['html'] as String;
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File(
          '${dir.path}/jiaowu_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(html); // 留样：解析不对时回来对结构
      final ScheduleTable table = parseQzTimetable(html);
      if (table.isEmpty) {
        messenger.showSnackBar(SnackBar(
            content: Text('这一页里没有课表表格，已在教务系统里导航到「学生课表」页吗？'
                '（原文已存 ${file.path.split('/').last}）')));
        return;
      }
      nav.pop(table);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('抓取失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
