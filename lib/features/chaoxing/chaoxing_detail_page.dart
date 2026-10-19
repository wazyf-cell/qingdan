/// 「详情」= 应用内 WebView 打开超星真实的作业页（M6B §B3）。
///
/// 为什么不做原生题目解析：参考脚本 `扩展/作业列表.js`（6101 行，上游
/// Cooanyh/chaoxing-list，AGPL-3.0）全文没有任何取题目详情的接口，它的
/// 「查看」就是 `window.open(getHomeworkLink(item))`（:5619）。URL 拼法见
/// `lib/import/chaoxing/chaoxing_links.dart`（照抄脚本 :3527-3534）。
///
/// 登录态复用：WebView 的 cookie jar 是全局的，登录页种下的 cookie 这里直接
/// 就能用，**代码里不读 cookie 值、也不拼 Cookie 头**（避免进日志）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/chaoxing/chaoxing_links.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_login.dart';
import 'chaoxing_model.dart';

/// WebView 构造器：测试环境没有 `flutter_inappwebview` 的平台实现（一 build
/// 就抛 MissingPluginException），所以留一个注入点，测试换成占位 Widget。
typedef ChaoxingWebViewBuilder = Widget Function(
    BuildContext context, String url, ValueChanged<Uri?> onLoadStop);

/// 打开详情页；`webView` 只给测试用。
void showChaoxingDetail(BuildContext context, ChaoxingTask task,
        {ChaoxingWebViewBuilder? webView}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) =>
          ChaoxingDetailPage(task: task, webView: webView),
    ));

class ChaoxingDetailPage extends StatefulWidget {
  const ChaoxingDetailPage({super.key, required this.task, this.webView});

  final ChaoxingTask task;
  final ChaoxingWebViewBuilder? webView;

  @override
  State<ChaoxingDetailPage> createState() => _ChaoxingDetailPageState();
}

class _ChaoxingDetailPageState extends State<ChaoxingDetailPage> {
  /// 被重定向到登录页（`passport` / `login`）时非 null，页面内显示降级提示。
  bool _sessionLost = false;

  /// 重新登录后重建 WebView 的计数（同一个 key 不会重新加载 URL）。
  int _reloadTick = 0;

  String? get _url => detailUrlOf(widget.task);

  void _onLoadStop(Uri? uri) {
    final String text = uri.toString().toLowerCase();
    // 只认这两个特征：超星把未登录的请求重定向到 passport2.chaoxing.com 或
    // 带 /login 的路径；课程中间页本身不含这两串，不会误判。
    final bool lost =
        text.contains('passport') || text.contains('/login');
    if (lost == _sessionLost) return;
    setState(() => _sessionLost = lost);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String? url = _url;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.courseName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.panelTitle),
        // 副标题给作业标题留一行：课程名可能很长，挤在一起会看不出在看哪条。
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(left: AppDimens.s16, bottom: AppDimens.s8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTypography.meta.copyWith(color: colors.textSecondary)),
            ),
          ),
        ),
      ),
      body: url == null
          ? _unsupported(context)
          : Column(
              children: <Widget>[
                if (_sessionLost) _lostBanner(context),
                Expanded(
                  child: (widget.webView ?? _inAppWebView)(
                      context, url, _onLoadStop),
                ),
              ],
            ),
    );
  }

  Widget _inAppWebView(
          BuildContext context, String url, ValueChanged<Uri?> onLoadStop) =>
      InAppWebView(
        key: ValueKey<int>(_reloadTick),
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
        onLoadStop: (InAppWebViewController _, WebUri? uri) =>
            onLoadStop(uri == null ? null : Uri.tryParse(uri.toString())),
      );

  /// 拼不出 URL（课堂活动，或**真作业缺 `clazzId`** / **真考试缺 `examId`**）：
  /// **如实降级，不假装能看**。两类 null 的成因不一样，话也必须分开——
  /// `detailUrlOf`（`chaoxing_links.dart`）对作业页与考试页来的条目在缺参数时
  /// 同样返回 null，那种条目其实**有**题目页，只是我们手里少一个参数。把两种
  /// 情况都写成「这类条目没有题目页」会让用户以为这条作业/考试天生看不了，
  /// 从而不去超星里点开它。
  Widget _unsupported(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ChaoxingTask t = widget.task;
    final bool hasRealPage =
        t.serverStatus != null || t.source == ChaoxingSource.exam;
    // 缺的哪个参数要点名：作业缺 clazzId、考试缺 examId，成因不同，
    // 写成同一句话用户就不知道该回超星找什么。
    final List<String> missing = <String>[
      if (t.courseId.isEmpty) 'courseId',
      if (t.clazzId == null || t.clazzId!.isEmpty) 'clazzId',
      if (t.source == ChaoxingSource.exam &&
          (t.examId == null || t.examId!.isEmpty)) 'examId',
    ];
    final String headline = hasRealPage
        ? '这条${t.kind}打不开'
        : '该类型暂不支持查看详情';
    final String reason = hasRealPage
        ? '它在超星里是有题目页的，但抓到的这一行没带 ${missing.join(' / ')}，'
            '我们拼不出地址。请在「学习通」App 或网页版里进这门课打开。'
        : '这类「${t.kind}」在超星里没有单独的题目页，'
            '请在「学习通」App 或网页版的课程里打开。';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.info_outline, size: 40, color: colors.textFaint),
            const SizedBox(height: AppDimens.s12),
            Text(headline,
                key: const ValueKey<String>('detail-headline'),
                style: AppTypography.body.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppDimens.s8),
            Text(reason,
                key: const ValueKey<String>('detail-reason'),
                textAlign: TextAlign.center,
                style: AppTypography.meta.copyWith(color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _lostBanner(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      color: colors.surfaceHigh,
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, AppDimens.s8, AppDimens.s8, AppDimens.s8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text('登录态可能已失效',
                style: AppTypography.meta.copyWith(color: colors.overdue)),
          ),
          TextButton(
            onPressed: () => _relogin(context),
            child: const Text('重新登录'),
          ),
        ],
      ),
    );
  }

  /// 与面板那条登录路径同一条：弹登录 WebView → 导出 cookie → 存凭据库 →
  /// 刷新；成功后把本页重载一次。
  Future<void> _relogin(BuildContext context) async {
    final String? cookie = await showChaoxingLogin(context);
    if (cookie == null || !context.mounted) return;
    await context.read<ChaoxingModel>().saveCookie(cookie);
    if (!mounted) return;
    setState(() {
      _sessionLost = false;
      _reloadTick++;
    });
  }
}
