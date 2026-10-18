/// 学习通登录页：内嵌 WebView 走超星自己的登录（账号密码 / 扫码都在页面里），
/// 登录成功后从 WebView 的 cookie jar 导出会话，交给上层存进系统凭据库。
///
/// 为什么必须让用户自己在 WebView 里登录：超星登录带验证码与扫码跳转，脚本化
/// 登录既脆弱又越界。我们只要那串 cookie。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:qingdan/theme/app_typography.dart';

const String _loginUrl =
    'https://passport2.chaoxing.com/login?newversion=true&refer=https%3A%2F%2Fi.chaoxing.com';

/// 会话判定用的 cookie 名：登录后超星会种下 `_uid`（值为学号/用户 id）。
const String _sessionCookieName = '_uid';

/// 这三个域都要问一遍：接口分别打在 mooc1-api 与 mobilelearn 上，
/// 超星虽然大多把 cookie 种在 `.chaoxing.com`，但存在按主机发的项。
const List<String> _cookieProbeUrls = <String>[
  'https://i.chaoxing.com',
  'https://mooc1-api.chaoxing.com',
  'https://mobilelearn.chaoxing.com',
];

/// 弹出登录页；返回导出的 Cookie 头值，用户中途退出则返回 null。
Future<String?> showChaoxingLogin(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (BuildContext _) => const ChaoxingLoginPage(),
    ));

/// 从 WebView cookie jar 导出 `a=1; b=2`；未登录（没有 `_uid`）返回 null。
Future<String?> exportChaoxingCookie() async {
  final Map<String, String> merged = <String, String>{};
  for (final String url in _cookieProbeUrls) {
    final List<Cookie> cookies =
        await CookieManager().getCookies(url: WebUri(url));
    for (final Cookie c in cookies) {
      merged[c.name] = c.value;
    }
  }
  if (!merged.containsKey(_sessionCookieName)) return null;
  return merged.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join('; ');
}

class ChaoxingLoginPage extends StatefulWidget {
  const ChaoxingLoginPage({super.key});

  @override
  State<ChaoxingLoginPage> createState() => _ChaoxingLoginPageState();
}

class _ChaoxingLoginPageState extends State<ChaoxingLoginPage> {
  String? hint;

  /// 登录成功后超星会连着跳好几个页面，每个页面都触发一次 onLoadStop；
  /// 导出成功后必须**只弹一次**——第二次 pop 会把主页路由也弹掉，界面变成
  /// 全白屏（真机实测：cookie 已存进凭据库，但屏幕空白、logcat 无异常）。
  bool _busy = false;
  bool _returned = false;

  Future<void> _capture({bool manual = false}) async {
    if (_busy || _returned) return;
    _busy = true;
    try {
      final String? cookie = await exportChaoxingCookie();
      if (cookie == null) {
        if (manual && mounted) {
          setState(() => hint = '还没检测到登录态（_uid cookie 不存在）');
        }
        return;
      }
      _returned = true;
      if (mounted) Navigator.of(context).pop(cookie);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(hint ?? '登录学习通',
            style: AppTypography.meta, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          TextButton(
            onPressed: () => _capture(manual: true),
            child: const Text('我登录好了'),
          ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
        onLoadStop: (InAppWebViewController controller, WebUri? url) =>
            _capture(),
      ),
    );
  }
}
