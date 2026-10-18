import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_conflict.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_block.dart';
import 'course_cycle_badge.dart';

/// 左侧节次轴（细化 §2.1:62）：桌面两行（节号 + 开始时间），移动只放节号。
///
/// 它随网格一起纵向滚动（本视图没有横向滚动，所以恒可见，不需要真的「吸住」）。
class CourseSectionAxis extends StatelessWidget {
  const CourseSectionAxis(
      {super.key, required this.layout, required this.isMobile});

  final SectionLayout layout;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Stack(
      children: <Widget>[
        for (final SectionSlot slot in layout.slots)
          Positioned(
            top: slot.top + 2,
            left: 0,
            right: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('${slot.section}', style: const TextStyle(fontSize: 12)),
                if (!isMobile)
                  Text(formatMinutes(slot.startMinutes),
                      style:
                          TextStyle(fontSize: 10, color: colors.textSecondary)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一天的列：今天色带 + 1dp 分隔线 + 课程块。
///
/// 同槽几门课 = **一个块**（细化 §2.4，2026-10-19 改版）：每门课保留自己真实的
/// 节次跨度，组内共享一个「当前索引」，只显示被选中的那一条，右下角挂循环角标
/// 切下一条。原来的「跨度按条数均分堆叠」与「<28dp 降级成首二字 +N」都已废掉。
class CourseDayColumn extends StatefulWidget {
  const CourseDayColumn({
    super.key,
    required this.layout,
    required this.groups,
    required this.week,
    required this.isToday,
    required this.isMobile,
    this.onBlockTap,
  });

  final SectionLayout layout;
  final List<OverlapGroup> groups;

  /// 这一列是第几周。只为「换周就把组内索引清回第一条」服务（见 State 注释），
  /// 渲染本身不看它。
  final int week;
  final bool isToday;
  final bool isMobile;
  final void Function(Course course, List<Course> sameSlot)? onBlockTap;

  @override
  State<CourseDayColumn> createState() => _CourseDayColumnState();
}

class _CourseDayColumnState extends State<CourseDayColumn> {
  /// 每个同槽分组当前显示组内第几条（0 起）。
  ///
  /// **为什么放这儿**：这是纯视图态（用户裁决不持久化），作用域恰好是一列（组
  /// 不会跨列），而 `CoursePaneModel` 不该知道「看到第几条」这种界面概念；再往
  /// 上放到全局就更没人负责清空了。
  ///
  /// **键用 [OverlapGroup.groupKey]**（成员 id 排序拼接）：分组每帧重算
  /// （`CourseWeekGrid.build` 直接调 `groupByOverlap`），用 List 的 identity
  /// hashCode 一漂，用户刚切到的那条会在任意一次重绘后莫名回到第一条。
  Map<String, int> _cycleIndex = <String, int>{};

  /// 「周次 + 各组**显示顺序**的成员 id」的签名：换了周、换了学期、课程集合或
  /// 次序变了 → 签名变 → 索引整表清空，回到第一条（Q6）。
  ///
  /// 这里刻意用**显示顺序**而不是 [OverlapGroup.groupKey]（排序后的）：改名会把
  /// 同一起始节次的两条换位置，索引指向的对象跟着变——那时必须清零，否则用户
  /// 看到的课会凭空换一门。次序没变的重载（同步拉下来一批一样的数据）签名相同，
  /// 索引保持，不会把用户刚切到的那条弹回第一条。
  late String _signature;

  @override
  void initState() {
    super.initState();
    // 必须在 initState 就取好基准：`late` 的惰性初始化会拖到第一次读它的时候，
    // 而那正是 didUpdateWidget 里比对的那一刻——基准跟现值同时算出来，永远相等，
    // 换周/改名清空索引这条整条失效（反证过一次：去掉清空逻辑测试照样绿）。
    _signature = _signatureOf(widget);
  }

  static String _signatureOf(CourseDayColumn w) {
    final String groups = w.groups
        .map((OverlapGroup g) => g.courses.map((Course c) => c.id).join(','))
        .join(';');
    return 'w${w.week}|$groups';
  }

  @override
  void didUpdateWidget(covariant CourseDayColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String next = _signatureOf(widget);
    if (next == _signature) return;
    _signature = next;
    _cycleIndex = <String, int>{};
  }

  void _select(String key, int index) =>
      setState(() => _cycleIndex[key] = index);

  ({double top, double height})? _rectOf(Course c) =>
      widget.layout.rectFor(c.startSection, c.endSection);

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colors.divider, width: 1),
          left: BorderSide(color: colors.divider, width: 1),
        ),
        // 今天整列的极淡色带（细化 §2.5:117）。
        color: widget.isToday
            ? colors.accent
                .withValues(alpha: AppDimens.courseTodayBandOpacity)
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final SectionSlot slot in widget.layout.slots)
            Positioned(
              top: slot.bottom,
              left: 0,
              right: 0,
              child: Container(height: 1, color: colors.divider),
            ),
          for (final OverlapGroup group in widget.groups) ..._blockOf(group),
        ],
      ),
    );
  }

  /// 一个组渲染成**一个**块：位置与高度取「当前显示那一条」自己的真实跨度。
  ///
  /// 传递性合并会带来跨度不等的组（A=1-2、B=2-3）这时**各画各的跨度**、叠在
  /// 同一位置上，绝不画一个 1-3 的大块冒充两门课；没被选中的成员不显示。
  List<Widget> _blockOf(OverlapGroup group) {
    // 节次不在作息表上的成员画不出来，也不能当循环目标（它会掉进「未排时间」区）。
    final List<Course> drawable =
        <Course>[for (final Course c in group.courses) if (_rectOf(c) != null) c];
    if (drawable.isEmpty) return const <Widget>[];
    final String key = group.groupKey;
    final int index = drawable.length == 1
        ? 0
        : (_cycleIndex[key] ?? 0).clamp(0, drawable.length - 1);
    final Course selected = drawable[index];
    final ({double top, double height}) rect = _rectOf(selected)!;
    // ≥2 门才挂角标（Q2）：入参本来就按当前周过滤过，所以「A 上 1-8 周、B 上
    // 9-16 周」这种本周只上一门的情况压根不成组，这里不再另加判据。
    final bool cycle = drawable.length >= 2;
    final bool showCounter = drawable.length > 2; // Q4：总数 == 2 不显示数字

    return <Widget>[
      Positioned(
        key: ValueKey<String>('slot-$key'),
        top: rect.top,
        left: 1,
        right: 1,
        height: rect.height,
        // ClipRect：外层日列 Stack 是 clipBehavior.none，切到下一条时新块要从
        // 右边滑进来，不剪的话它会横穿到隔壁那一列（或压在节次轴上）。
        // 剪的是**画面**：块高 `0.9×分钟−2`，一节排到 43 分钟以下就不足 36dp
        // （每节时长是自由输入，30 分钟能落库），角标顶出块外的那截既看不见也
        // 点不到（2026-10-19 探针：30 分钟一节的作息下，上一块下沿那 9dp 与两块
        // 之间 2dp 的缝都切不动条目），20dp 圆底倒会被剪掉一截——所以热区在下面
        // 按块高钳位，不拿这层裁剪当兜底。
        child: ClipRect(
          child: Stack(
            children: <Widget>[
              AnimatedSwitcher(
                duration: AppDimens.courseCycleSwitchDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: _previousBehind,
                transitionBuilder: _slideFromRight,
                child: CourseBlock(
                  key: ValueKey<String>('block-${selected.id}'),
                  name: selected.name,
                  location: selected.location,
                  teacher: selected.teacher,
                  colorIndex: selected.effectiveColorIndex,
                  height: rect.height,
                  trailingReserve:
                      showCounter ? AppDimens.courseCycleCounterGap : 0,
                  isMobile: widget.isMobile,
                  // 点块本体 = 打开当前显示那一门的详情（Q3，行为不变）。
                  onTap: () => widget.onBlockTap?.call(selected, group.courses),
                ),
              ),
              if (cycle)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CourseCycleBadge(
                    key: ValueKey<String>('cycle-badge-$key'),
                    colorIndex: selected.effectiveColorIndex,
                    hiddenCount: drawable.length - 1,
                    // 热区不得超过块自身（短节次时块高 < 36dp），见组件注释。
                    maxHeight: rect.height,
                    onTap: () => _select(key, (index + 1) % drawable.length),
                  ),
                ),
              if (showCounter)
                Positioned(
                  right: AppDimens.courseBlockPadding.right,
                  top: AppDimens.courseBlockPadding.top,
                  child: CourseCycleCounter(
                    key: ValueKey<String>('cycle-count-$key'),
                    colorIndex: selected.effectiveColorIndex,
                    index: index,
                    total: drawable.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }
}

/// 切换动画（Q5，200ms）：**两条同向往右**——旧的一条原地向右滑出并淡出，新的
/// 一条从右边界滑进来并淡入。
///
/// `Tween(begin: Offset(1,0), end: Offset.zero)` 对入场（t 0→1）是把子节点从
/// 右边界推进到位；退场那条走的是同一条偏移序列的反向（t 1→0），所以它从原位
/// **往右**退出，不是往左。定案原文只要求「内容水平滑出 + 下一条从右侧滑入，
/// 不做翻转/缩放/弹跳」，同向这条满足；改成一进一出的对滑要在 transitionBuilder
/// 里辨别入场/退场，换来的只是观感差异，2026-10-19 评审第 2 条定的是「注释与
/// 实现必须一致」，这里按实现改注释。
Widget _slideFromRight(Widget child, Animation<double> animation) =>
    FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(animation),
        child: child,
      ),
    );

/// 退场中的那一条压在下面**且不接点击**：否则这 200ms 里点到旧块的位置会打开
/// 已经切走的那门课的详情。
///
/// `StackFit.expand` 不是可选的：`AnimatedSwitcher` 给子树的是**宽松**约束，
/// 默认 fit 会让课程块缩到内容宽（实测 1280 下从整列宽掉到 76.5dp），
/// 右下角的角标就会飘到块外面。
Widget _previousBehind(Widget? current, List<Widget> previous) => Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final Widget w in previous) IgnorePointer(child: w),
        ?current,
      ],
    );
