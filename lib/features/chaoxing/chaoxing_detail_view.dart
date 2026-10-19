/// 详情页主体：先抽正文、原生渲染；抽不到才退回超星真实网页。
///
/// 2026-10-19 用户裁决：「详情界面最好点击后跳转到我应用新建一个同主题的页面……
/// 实在没有提取到就转向真实页面」。所以原生这一屏是**默认形态**，WebView 是兜底：
/// 已提交 / 已过时效 / 活动类条目 / 抽取失败都走网页，网页里再给一个「在网页中
/// 作答」的入口给前者用。
///
/// 附件按用户要求**只显示名字、不可点击**（页面上那是个 iframe，下载要走超星
/// 自己的云盘接口，我们既不解析也不代理）。名字用强调色，跟正文区分开。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/chaoxing/chaoxing_client.dart'
    show ChaoxingAuthException;
import 'package:qingdan/import/chaoxing/chaoxing_links.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_time.dart';
import 'package:qingdan/import/chaoxing/chaoxing_work_detail.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_model.dart';

/// WebView 构造器：测试环境没有 `flutter_inappwebview` 的平台实现（一 build
/// 就抛 MissingPluginException），所以留一个注入点，测试换成占位 Widget。
typedef ChaoxingWebViewBuilder = Widget Function(
    BuildContext context, String url, ValueChanged<Uri?> onLoadStop);

/// [task] 有 `detailEntryUrl` 时先尝试抽正文；[webView] 是网页兜底（测试注入点）。
class ChaoxingDetailView extends StatefulWidget {
  const ChaoxingDetailView({
    super.key,
    required this.task,
    required this.webView,
    required this.onSessionLost,
  });

  final ChaoxingTask task;
  final ChaoxingWebViewBuilder webView;
  final ValueChanged<bool> onSessionLost;

  @override
  State<ChaoxingDetailView> createState() => _ChaoxingDetailViewState();
}

class _ChaoxingDetailViewState extends State<ChaoxingDetailView> {
  bool _loading = false;
  ChaoxingWorkDetail? _detail;

  /// 抽取失败（null / 异常）时置 true：直接落网页，不再显示「重试」。
  bool _fellBack = false;

  /// 抽取失败的原因，只在网页形态顶部那一行小字里用（不弹框、不打断）。
  String? _fallbackNote;

  @override
  void initState() {
    super.initState();
    if (widget.task.detailEntryUrl != null) _load();
  }

  Future<void> _load() async {
    final ChaoxingModel model = context.read<ChaoxingModel>();
    setState(() {
      _loading = true;
      _fellBack = false;
    });
    ChaoxingWorkDetail? detail;
    String? note;
    try {
      detail = await model.loadWorkDetail(widget.task);
      if (detail == null) note = '这一页没抽出题目';
    } on ChaoxingAuthException {
      note = '登录态已失效';
      widget.onSessionLost(true);
    } catch (e) {
      note = '抽取失败（${e.runtimeType}）';
    }
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
      _fellBack = detail == null;
      _fallbackNote = note;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          key: ValueKey<String>('detail-loading'),
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      );
    }
    final ChaoxingWorkDetail? detail = _detail;
    if (detail != null && !_fellBack) return _native(context, detail);
    return _web(context);
  }

  Widget _native(BuildContext context, ChaoxingWorkDetail detail) {
    final ChaoxingTask t = widget.task;
    final List<Widget> blocks = <Widget>[
      _meta(context, t),
      for (final ChaoxingQuestion q in detail.questions) _question(context, q),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppDimens.s16, 0, AppDimens.s16, AppDimens.s24),
        child: TextButton.icon(
          key: const ValueKey<String>('detail-open-web'),
          onPressed: () => setState(() => _fellBack = true),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('在网页中作答 / 看原图'),
        ),
      ),
    ];
    return ListView(
      key: const ValueKey<String>('detail-native'),
      padding: const EdgeInsets.only(top: AppDimens.s8),
      children: blocks,
    );
  }

  Widget _meta(BuildContext context, ChaoxingTask t) {
    final AppColors colors = AppColors.of(context);
    final List<String> bits = <String>[
      if (t.serverStatus != null && t.serverStatus!.isNotEmpty) t.serverStatus!,
      if (t.dueAt != null) formatDeadlineLine(t.dueAt!, DateTime.now()),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, AppDimens.s4, AppDimens.s16, AppDimens.s12),
      child: Text(bits.join(' · '),
          key: const ValueKey<String>('detail-meta'),
          style: AppTypography.meta.copyWith(color: colors.textSecondary)),
    );
  }

  Widget _question(BuildContext context, ChaoxingQuestion q) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, AppDimens.s8, AppDimens.s16, AppDimens.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(q.type.isEmpty ? '${q.index}.' : '${q.index}. ${q.type}',
              key: ValueKey<String>('detail-q${q.index}-head'),
              style: AppTypography.panelTitle),
          const SizedBox(height: AppDimens.s8),
          // 颜色必须写死在 style 里：`Text` 不给 color 时继承的是主题默认色，
          // 那样「标签用强调色、正文用正文色」这条要求只在深色/浅色主题恰好
          // 不等的时候才成立，等于没实现。
          SelectableText(
            q.text.isEmpty ? '（本题没有文字题干）' : q.text,
            key: ValueKey<String>('detail-q${q.index}-body'),
            style: AppTypography.body
                .copyWith(color: colors.textPrimary, height: 1.55),
          ),
          for (final String name in q.attachments) _attachment(colors, name),
          if (q.imageCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.s8),
              child: Text('题干里还有 ${q.imageCount} 张图片，这里不显示，请看原页面。',
                  key: ValueKey<String>('detail-q${q.index}-images'),
                  style: AppTypography.meta.copyWith(color: colors.textFaint)),
            ),
        ],
      ),
    );
  }

  /// 附件：一个不可点的名字标签。用 `Tooltip` + 纯 `Text`，外面**不套**任何
  /// 手势组件——用户明确说「不要显示（预览），最好也不能点击」。
  Widget _attachment(AppColors colors, String name) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.s8),
      child: Container(
        key: ValueKey<String>('detail-attach-$name'),
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.s8, vertical: AppDimens.s4),
        decoration: BoxDecoration(
          color: colors.accentFaint,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.description_outlined, size: 16, color: colors.accent),
            const SizedBox(width: AppDimens.s8),
            Flexible(
              child: Text(name,
                  style: AppTypography.meta
                      .copyWith(color: colors.accent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _web(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String? url = detailUrlOf(widget.task);
    if (url == null) {
      // 有入口地址、抽不出正文，而网页地址又拼不出来（抓到的那一行没带 clazzId）。
      // 外层那塊「这条作业打不开」的降级块在这种条目上**不该**再出现：入口地址在
      // 手上，抽取真的试过，所以这里说清试过了、为什么还是看不了。
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.s24),
          child: Text(
              '${_fallbackNote ?? '这一页没抽出题目'}，'
              '而且抓到的那一行没带班级 id，网页地址也拼不出来。'
              '请在「学习通」App 或网页版里进这门课打开。',
              key: const ValueKey<String>('detail-web-note'),
              textAlign: TextAlign.center,
              style: AppTypography.meta.copyWith(color: colors.textSecondary)),
        ),
      );
    }
    return Column(
      children: <Widget>[
        if (_fallbackNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppDimens.s16, AppDimens.s4, AppDimens.s16, AppDimens.s4),
            child: Text('$_fallbackNote，已转真实页面',
                key: const ValueKey<String>('detail-web-note'),
                textAlign: TextAlign.center,
                style: AppTypography.meta.copyWith(color: colors.textFaint)),
          ),
        Expanded(
            child: widget.webView(context, url, (Uri? uri) {
          final String text = uri.toString().toLowerCase();
          widget.onSessionLost(
              text.contains('passport') || text.contains('/login'));
        })),
      ],
    );
  }
}
