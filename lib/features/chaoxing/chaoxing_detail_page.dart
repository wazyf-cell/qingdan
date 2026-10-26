/// 「详情」= 推进本应用自己的一个全屏页（M6B §B3，2026-10-19 改版）。
///
/// 这一屏**默认是原生正文**：作业的题干、题型、附件名由
/// `chaoxing_detail_view.dart` 抽出来自己渲染（链路见 `chaoxing_work_detail.dart`），
/// 抽不到才退回超星真实网页。早先这里是「一进来就一个 WebView」，等于把
/// 详情按钮做成了「打开外部页面」，用户要的正是别这样。
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

import 'chaoxing_detail_view.dart';
import 'chaoxing_login.dart';
import 'chaoxing_model.dart';

export 'chaoxing_detail_view.dart' show ChaoxingWebViewBuilder;

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

  /// 用户点了「打开网页版」后的地址；null = 还在降级说明页。
  String? _fallbackUrl;

  String? get _url => detailUrlOf(widget.task);

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String? url = _url;
    final String? fallback = _fallbackUrl;
    final Widget body;
    if (fallback != null) {
      body = _fallbackWeb(context, fallback);
    } else if (url == null && widget.task.detailEntryUrl == null) {
      // 既没有网页地址、也没有入口地址（课堂活动 / 缺参数的条目）：
      // 只能如实降级，见 [_unsupported]。
      body = _unsupported(context);
    } else {
      // 有入口地址时交给主体去试抽取——**抽取不需要 clazzId**，所以
      // 「拼不出网页地址」的条目也可能抽得出正文，不能在这里就判它看不了。
      body = Column(
        children: <Widget>[
          if (_sessionLost) _lostBanner(context),
          Expanded(
            child: ChaoxingDetailView(
              // 重新登录后整块重建：换 key 才会重跑一次抽取（登录前那次
              // 必然失败，不重建就永远停在「登录态已失效」那一屏）。
              key: ValueKey<int>(_reloadTick),
              task: widget.task,
              webView: widget.webView ?? _inAppWebView,
              onSessionLost: (bool lost) {
                if (lost == _sessionLost) return;
                setState(() => _sessionLost = lost);
              },
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(fallback == null ? widget.task.courseName : '学习通网页版',
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
      body: body,
    );
  }

  /// 网页版兜底：带登录态的 WebView 打开课程页 / 全局考试列表，
  /// 用户自己在页面里找到那条考试。不是「假装拼出了题目页」。
  Widget _fallbackWeb(BuildContext context, String url) {
    final AppColors colors = AppColors.of(context);
    return Column(
      children: <Widget>[
        if (_sessionLost) _lostBanner(context),
        Container(
          width: double.infinity,
          color: colors.surfaceHigh,
          padding: const EdgeInsets.fromLTRB(
              AppDimens.s16, AppDimens.s8, AppDimens.s16, AppDimens.s8),
          child: Text(
            '网页版 · 在页面里找到「${widget.task.title}」并点开',
            key: const ValueKey<String>('detail-fallback-note'),
            style: AppTypography.meta.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: (widget.webView ?? _inAppWebView)(context, url, (Uri? uri) {
            final String text = uri.toString().toLowerCase();
            final bool lost =
                text.contains('passport') || text.contains('/login');
            if (lost != _sessionLost) setState(() => _sessionLost = lost);
          }),
        ),
      ],
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
    final String? fallback = webFallbackUrlOf(t);
    final bool coursePage =
        t.courseId.isNotEmpty && (t.clazzId?.isNotEmpty ?? false);
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
            if (fallback != null) ...<Widget>[
              const SizedBox(height: AppDimens.s12),
              Text(
                  coursePage
                      ? '可以用带登录态的网页版课程打开，自己找到这一条。'
                      : '可以直接打开学习通网页版考试列表，按标题找到它。',
                  textAlign: TextAlign.center,
                  style: AppTypography.meta
                      .copyWith(color: colors.textFaint)),
              const SizedBox(height: AppDimens.s8),
              FilledButton.tonal(
                key: const ValueKey<String>('detail-open-web-fallback'),
                onPressed: () => setState(() => _fallbackUrl = fallback),
                child: Text(
                    coursePage ? '打开网页版课程' : '打开学习通网页版考试列表'),
              ),
            ],
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
