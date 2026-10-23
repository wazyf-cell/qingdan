/// 学习通面板的头部：**单行 44dp**（上下各 4dp 留白 = 面板头 52dp）。
///
/// M6B §B1 把原先 252dp 的四行（标题行 / 页签 / 间距 / 工具栏 148dp）压成这一行：
/// 页签自绘（`SegmentedButton` 最小 40dp 且带内边距，压不进 48dp 行内）、
/// 「N 分钟前」挪到刷新按钮**左边**（用户明确要求的相对位置）、
/// 搜索/课程/两个仅看/排序全部搬进 `cx-filter` 的筛选弹层、
/// 「学习通待办」标题删掉（壳顶栏已经写了「学习通」，`mobile_top_bar.dart:46`）。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_grouping.dart';
import 'chaoxing_keys.dart';

class ChaoxingHeader extends StatelessWidget {
  const ChaoxingHeader({
    super.key,
    required this.tab,
    required this.onTab,
    required this.statusText,
    required this.statusIsError,
    required this.stale,
    required this.loading,
    required this.loggedIn,
    required this.onRefresh,
    required this.filterCount,
    required this.onFilter,
    required this.onRelogin,
    required this.onHiddenList,
    required this.onLogout,
  });

  final ChaoxingTab tab;
  final ValueChanged<ChaoxingTab> onTab;

  /// 一句话的状态：`22:20 更新` / `更新中…` / `未刷新` / `刷新失败：超时 · 22:20`。
  final String statusText;

  /// 失败时那一句要红；同时决定它能不能被挤掉（失败比时间更重要）。
  final bool statusIsError;
  final bool stale;
  final bool loading;
  final bool loggedIn;
  final VoidCallback onRefresh;

  /// 生效中的筛选条件数（搜索非空 / 课程非全部 / 两个仅看 / 排序非默认，各算 1）。
  final int filterCount;
  final VoidCallback onFilter;
  final VoidCallback onRelogin;
  final VoidCallback onHiddenList;
  final VoidCallback onLogout;

  static const double _rowHeight = 44;
  static const double _vPad = 4;

  /// 面板头总高（供测试与布局算式核对：137dp 固定壳 + 本值 = 非滑动区）。
  static double get totalHeight => _rowHeight + _vPad * 2;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s8, _vPad, AppDimens.s4, _vPad),
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          children: <Widget>[
            for (final ChaoxingTab t in ChaoxingTab.values) _tab(context, t),
            // 状态文案吃掉页签与按钮之间的**全部**剩余宽度。以前这里是
            // `Spacer` + `Flexible`：两者都是 flex:1，各分一半，窄屏上文案只剩
            // 二三十 dp，于是用户看到的是一个「…」（2026-10-23 真机实测）。
            Expanded(
              child: loggedIn
                  ? _status(colors)
                  : const SizedBox.shrink(),
            ),
            if (loggedIn) ...<Widget>[
              _refresh(colors),
              IconButton(
                key: ChaoxingKeys.vkey(ChaoxingKeys.filter),
                tooltip: '筛选',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: colors.textSecondary,
                onPressed: onFilter,
                icon: filterCount > 0
                    // Badge 默认底色是 colorScheme.error（红）——必须显式传，
                    // 否则筛选角标长得像报错（总纲陷阱表）。
                    ? Badge(
                        backgroundColor: colors.accent,
                        textColor: Colors.white,
                        label: Text('$filterCount'),
                        child: const Icon(Icons.tune),
                      )
                    : const Icon(Icons.tune),
              ),
            ],
            _account(context, colors),
          ],
        ),
      ),
    );
  }

  /// 状态一句：失败红字、过期黄字、正常灰字。放不下就整句不显示（见 [_FitText]）。
  Widget _status(AppColors colors) {
    final Color color = statusIsError
        ? colors.priorityHigh
        : (stale ? colors.priorityMedium : colors.textFaint);
    return Padding(
      padding: const EdgeInsets.only(right: AppDimens.s4),
      child: Align(
        alignment: Alignment.centerRight,
        child: _FitText(
          key: ChaoxingKeys.vkey(ChaoxingKeys.stale),
          text: statusText,
          style: AppTypography.meta.copyWith(fontSize: 12, color: color),
        ),
      ),
    );
  }

  Widget _refresh(AppColors colors) {
    // loading 时换成转圈并禁点：刷新是单发的，连着点只会排队打超星。
    return IconButton(
      key: ChaoxingKeys.vkey(ChaoxingKeys.refresh),
      tooltip: '刷新',
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: colors.textSecondary,
      onPressed: loading ? null : onRefresh,
      icon: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: colors.accent))
          : const Icon(Icons.refresh),
    );
  }

  /// ⋮ 菜单三项，顺序固定：重新登录 / 隐藏列表 / 退出登录（破坏性动作放最后）。
  Widget _account(BuildContext context, AppColors colors) {
    return PopupMenuButton<String>(
      key: ChaoxingKeys.vkey(ChaoxingKeys.account),
      tooltip: '账号',
      icon: Icon(Icons.more_vert, size: 20, color: colors.textSecondary),
      color: colors.surface,
      itemBuilder: (BuildContext _) => <PopupMenuItem<String>>[
        PopupMenuItem<String>(
            key: ChaoxingKeys.vkey(ChaoxingKeys.menuRelogin),
            value: 'relogin',
            height: 44,
            child: Text('重新登录', style: AppTypography.body)),
        PopupMenuItem<String>(
            key: ChaoxingKeys.vkey(ChaoxingKeys.menuHidden),
            value: 'hidden',
            height: 44,
            child: Text('隐藏列表', style: AppTypography.body)),
        PopupMenuItem<String>(
            key: ChaoxingKeys.vkey(ChaoxingKeys.menuLogout),
            value: 'logout',
            height: 44,
            child: Text('退出登录', style: AppTypography.body)),
      ],
      onSelected: (String v) {
        switch (v) {
          case 'relogin':
            onRelogin();
          case 'hidden':
            onHiddenList();
          default:
            onLogout();
        }
      },
    );
  }

  /// 自绘文字页签：下划线 2dp，选中用主题色，未选中用次要文字色。
  /// 文案取枚举自带的 [ChaoxingTab.label]（「全部作业 / 全部考试 / 课堂活动」，
  /// 逐字对齐脚本 :5043-5045 的三个视图标题）。
  Widget _tab(BuildContext context, ChaoxingTab value) {
    final AppColors colors = AppColors.of(context);
    final bool selected = value == tab;
    return InkWell(
      key: ChaoxingKeys.vkey(ChaoxingKeys.tabKeyOf(value)),
      onTap: () => onTab(value),
      child: Container(
        height: _rowHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.s8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                width: 2, color: selected ? colors.accent : Colors.transparent),
          ),
        ),
        child: Text(value.label,
            style: AppTypography.meta.copyWith(
                color: selected ? colors.accent : colors.textSecondary)),
      ),
    );
  }
}

/// 放得下就显示，放不下就**整句不显示**。
///
/// 不用 `TextOverflow.ellipsis`：这一格只有几十 dp，加省略号等于把整句吃掉，
/// 用户看到的是一个孤零零的「…」——比不显示更难懂，而且没法判断是坏了还是没数据
/// （2026-10-23 用户在真机上就是这么看到的）。
class _FitText extends StatelessWidget {
  const _FitText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        final TextPainter measure = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(ctx),
          // 系统的字体放大也要算进来，否则「量着放得下」在真机上会溢出一行。
          textScaler: MediaQuery.textScalerOf(ctx),
        )..layout();
        final bool fits = measure.width <= c.maxWidth;
        measure.dispose();
        return fits ? Text(text, style: style, maxLines: 1) : const SizedBox.shrink();
      },
    );
  }
}
