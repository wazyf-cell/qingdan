import 'package:flutter/material.dart';

/// 尺寸 token（`开发文档/02-方案设计/方案设计-M1界面.md` §1.4/§1.5/§1.7/§1.8）。
///
/// 4dp 基准间距阶梯 + 断点/栏宽/行高等布局常量，全项目从这里取值，
/// 不在 widget 内散落魔数。
abstract final class AppDimens {
  // ---- 间距阶梯（§1.4）：4 / 8 / 12 / 16 / 24 / 32 ----
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;

  // ---- 断点（§1.7）----
  /// < 720dp：单栏 + 抽屉，详情为全屏页。
  static const double breakpointNarrow = 720;

  /// ≥ 1040dp：三栏。
  static const double breakpointWide = 1040;

  // ---- 栏宽（§1.7）----
  /// 三栏侧栏宽度。
  static const double sidebarWidth = 224;

  /// 两栏形态的图标栏宽度。
  static const double iconRailWidth = 56;

  /// 详情面板宽度（三栏右栏 / 两栏锚定弹层）。
  static const double detailPanelWidth = 360;

  /// 列表区最小宽度（三栏下 flex 的下限）。
  static const double minListWidth = 360;

  // ---- 关键高度（§1.4）----
  /// 侧栏项高。
  static const double sidebarItemHeight = 32;

  /// 任务行高（UI-2 使用）。
  static const double taskRowHeight = 40;

  /// 分组头高。
  static const double groupHeaderHeight = 32;

  /// 侧栏底部同步状态槽高（§1.8，M1 透明占位）。
  static const double syncSlotHeight = 28;

  /// 面板内边距。
  static const double panelPadding = 16;

  /// 列表区左右内边距。
  static const double listPanePaddingH = 8;

  // ---- 圆角（§1.5）：桌面 6dp，移动 8dp ----
  static const double radiusDesktop = 6;

  /// 学习通卡片左侧的到期档位竖条宽度（§1.2 的 6dp 图形档）。
  static const double dueStripeWidth = 6;
  static const double radiusMobile = 8;

  // ---- 课表周视图（细化 §2.1~§2.6，2026-10-10 定案）----
  /// 左侧节次轴宽：桌面 52dp（节号 + 开始时间两行）。
  static const double courseAxisDesktop = 52;

  /// 左侧节次轴宽：移动 40dp（只放节号）。
  static const double courseAxisMobile = 40;

  /// 顶部星期轴高：桌面 48dp（周几 + 日期）。
  static const double courseHeaderDesktop = 48;

  /// 顶部星期轴高：移动 44dp（触控下限）。
  static const double courseHeaderMobile = 44;

  /// 课程块左侧实色竖条宽。
  static const double courseBarWidth = 3;

  /// 课程块内边距（细化 §2.3:89：左 9 = 3 + 6，上/下 4，右 6）。
  static const EdgeInsets courseBlockPadding =
      EdgeInsets.fromLTRB(9, 4, 6, 4);

  /// 同槽堆叠时块与块之间的间隙。
  static const double courseStackGap = 2;

  /// 单条课程块的最低可读高度（低于此值整组降级为「首二字 + +N」）。
  static const double courseMinBlockHeight = 28;

  /// 周导航 ‹ › 按钮边长。
  static const double courseNavButton = 40;

  /// 「今天」列头主题色胶囊高。
  static const double courseTodayPill = 28;

  /// 「今天」整列的极淡背景色带透明度（细化 §2.5:117）。
  static const double courseTodayBandOpacity = 0.04;

  /// 今日摘要条高（细化 §2.8:140）。
  static const double courseTodayBarHeight = 44;

  // ---- 阴影（§1.5）：仅浮层 —— 弹窗/菜单/抽屉/锚定弹层 ----
  /// y+2 blur 8dp @ 20% 黑。
  static const List<BoxShadow> overlayShadow = [
    BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 8,
      color: Color(0x33000000),
    ),
  ];
}
