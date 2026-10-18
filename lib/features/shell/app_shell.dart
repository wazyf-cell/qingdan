import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'narrow_shell.dart';
import 'placeholder_panes.dart';
import 'sidebar/icon_rail.dart';
import 'sidebar/sidebar_view.dart';

/// 主窗口三栏壳（§1.7 断点与导航形态）。
///
/// | 逻辑宽度        | 形态 |
/// | ≥ 1040dp       | 三栏：侧栏 224 + 列表 flex(≥360) + 详情面板 360（可整栏收起） |
/// | 720–1039dp     | 两栏：图标栏 56 + 列表；详情改右侧锚定弹层 360dp |
/// | < 720dp        | 单栏 + 底部 4 页签（M5 修订，原为抽屉）；详情为全屏页 |
///
/// 分栏间分隔线按 §1.5（1dp 分隔线色）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 三栏形态下详情面板是否整栏收起（收起后列表区变宽，§1.7）。
  bool _detailCollapsed = false;

  TaskPaneModel? _pane;
  int _seenDetailRequest = 0;

  void _toggleDetail() =>
      setState(() => _detailCollapsed = !_detailCollapsed);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final TaskPaneModel pane = context.read<TaskPaneModel>();
    if (identical(pane, _pane)) return;
    _pane?.removeListener(_onPaneChanged);
    _pane = pane;
    _seenDetailRequest = pane.detailPageRequest;
    pane.addListener(_onPaneChanged);
  }

  @override
  void dispose() {
    _pane?.removeListener(_onPaneChanged);
    super.dispose();
  }

  /// 点通知进来时，窄屏要的是「直接看见那条任务」，不是回到列表页。
  /// 三栏 / 两栏形态详情本来就挂在右侧，只需模型选中即可，不推页。
  void _onPaneChanged() {
    final TaskPaneModel pane = _pane!;
    if (pane.detailPageRequest == _seenDetailRequest) return;
    _seenDetailRequest = pane.detailPageRequest;
    if (!mounted) return;
    if (MediaQuery.sizeOf(context).width >= AppDimens.breakpointNarrow) return;
    // 监听器可能在 build 期间被触发（模型在帧中通知），推路由要等这一帧画完。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openFullScreenDetail(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          if (width >= AppDimens.breakpointWide) {
            return _buildThreePane(context);
          }
          if (width >= AppDimens.breakpointNarrow) {
            return _buildTwoPane(context);
          }
          return _buildSinglePane(context);
        },
      ),
    );
  }

  // ---- ≥1040dp：三栏 ----
  Widget _buildThreePane(BuildContext context) {
    final bool showDetail = !_detailCollapsed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: AppDimens.sidebarWidth,
          child: const SidebarView(),
        ),
        const VerticalDivider1(),
        Expanded(
          child: ListPaneHost(
            onReopenDetail: showDetail ? null : _toggleDetail,
          ),
        ),
        if (showDetail) ...<Widget>[
          const VerticalDivider1(),
          SizedBox(
            width: AppDimens.detailPanelWidth,
            child: DetailPaneHost(onCollapse: _toggleDetail),
          ),
        ],
      ],
    );
  }

  // ---- 720–1039dp：图标栏 56 + 列表，详情为右侧锚定弹层 ----
  Widget _buildTwoPane(BuildContext context) {
    return Stack(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: AppDimens.iconRailWidth,
              child: const IconRail(),
            ),
            const VerticalDivider1(),
            Expanded(
              child: ListPaneHost(
                onReopenDetail: () => _openAnchoredDetail(context),
              ),
            ),
          ],
        ),
        // 锚定弹层入口按钮：右下角固定，点击浮出 360dp 详情弹层。
        Positioned(
          right: AppDimens.s16,
          bottom: AppDimens.s16,
          child: FloatingActionButton.small(
            tooltip: '打开详情面板',
            onPressed: () => _openAnchoredDetail(context),
            child: const Icon(Icons.chevron_left),
          ),
        ),
      ],
    );
  }

  void _openAnchoredDetail(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭详情面板',
      barrierColor: const Color(0x66000000), // 遮罩 40% 黑（§2.6 同款）
      transitionDuration: Duration.zero, // §1.2：不做过渡动画
      pageBuilder: (BuildContext ctx, _, _) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: AppColors.of(ctx).surface,
            elevation: 8,
            shadowColor: const Color(0x33000000),
            child: SizedBox(
              width: AppDimens.detailPanelWidth,
              child: DetailPaneHost(
                onCollapse: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- <720dp：单栏 + 底部 4 页签，详情为全屏页（M5 修订）----
  Widget _buildSinglePane(BuildContext context) {
    // §2.6 移动线框没有 FAB，需求规格书 :172 定的是「列表 ↔ 详情」两级页面：
    // 详情入口就是点任务行 → 推全屏详情页。此处也不传 onReopenDetail——
    // ListPaneHost 右上角箭头与它是同一动作，并存即重复入口。
    return NarrowShell(
      onOpenDetailPage: () => _openFullScreenDetail(context),
    );
  }

  void _openFullScreenDetail(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext ctx) => Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.of(ctx).pop()),
        ),
        body: const DetailPaneHost(twoColumns: true),
      ),
    ));
  }
}

/// 1dp 垂直分隔线（§1.5：侧栏与列表区、列表区与详情面板之间画 1dp 线）。
class VerticalDivider1 extends StatelessWidget {
  const VerticalDivider1({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: AppColors.of(context).divider);
}
