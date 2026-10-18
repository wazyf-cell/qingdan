/// 手写的「从右往左滑揭示右侧按钮」容器（M6B §B2）。
///
/// 不引 `flutter_slidable`（M6 总纲铁律 1：本里程碑不加任何 pubspec 依赖），
/// 用 `GestureDetector` 的水平拖拽 + `AnimationController` 自己实现。
///
/// 三条约束决定了实现形状：
/// 1. **只接管水平方向**——垂直方向必须让给外层 `ListView`，靠手势竞技场
///    （`onHorizontalDrag*` 注册的是 horizontal recognizer）自动跟纵向滚动手势协商。
/// 2. **打开态由外部 key 驱动**——`ListView.builder` 会复用 item，只存内部 state
///    会让打开态跟着复用乱跳，所以 [open] 是受控属性，容器只做动画。
/// 3. **同一时刻只允许一张打开**——由 `ChaoxingPane` 持有「当前打开的条目 key」。
library;

import 'package:flutter/material.dart';

/// 揭示出来的一个动作按钮。
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.background,
    required this.onTap,
    this.key,
    this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final VoidCallback onTap;
  final Key? key;
  final Color? foreground;
}

class SwipeReveal extends StatefulWidget {
  const SwipeReveal({
    super.key,
    required this.child,
    required this.actions,
    this.open = false,
    this.onOpen,
    this.onClose,
    this.actionWidth = 72,
  });

  final Widget child;
  final List<SwipeAction> actions;

  /// 受控的打开态：父级（面板）知道「现在哪张卡片是开着的」。
  final bool open;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final double actionWidth;

  @override
  State<SwipeReveal> createState() => _SwipeRevealState();
}

class _SwipeRevealState extends State<SwipeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.open ? 1 : 0,
  );

  /// 最近一次「命令」到的档位（0 或 1），用来判断外部回传的状态是不是自己
  /// 刚请求的那个，避免动画与回调互相打乒乓。
  double _commanded = 0;

  double get _reveal => widget.actions.length * widget.actionWidth;

  @override
  void initState() {
    super.initState();
    // 字段初始化器里不能碰 `widget`，打开态的初值只能在 initState 同步。
    _commanded = widget.open ? 1 : 0;
  }

  @override
  void didUpdateWidget(SwipeReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部把别的卡片设成打开、或滚动时统一收回，都从这里同步回来。
    final double want = widget.open ? 1 : 0;
    if (want != _commanded) _go(want, notify: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(double target, {bool notify = true}) {
    final bool changed = _commanded != target;
    _commanded = target;
    _controller.animateTo(target, duration: const Duration(milliseconds: 200));
    if (!changed || !notify) return;
    if (target == 1) {
      widget.onOpen?.call();
    } else {
      widget.onClose?.call();
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_reveal <= 0) return;
    final double offset = -_reveal * _controller.value + d.delta.dx;
    _controller.value = (-offset.clamp(-_reveal, 0.0)) / _reveal;
  }

  void _onDragEnd(DragEndDetails d) {
    // 拖过一半停住，否则回弹。
    _go(_controller.value >= 0.5 ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext _, Widget? child) => ClipRect(
        child: Stack(
          children: <Widget>[
            // 完全收起时**不挂 actions**：测试与语义都按「关闭 = 没有这两个按钮」
            // 处理（留着会让 `findsNothing` 那类断言失效，也会让复用中的
            // item 在无障碍遍历里多出两个看不见却能聚焦的按钮）。
            if (_controller.value > 0)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _reveal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.actions
                      .map((SwipeAction a) => SizedBox(
                            width: widget.actionWidth,
                            child: _ActionButton(action: a),
                          ))
                      .toList(),
                ),
              ),
            // **必须拉满整行宽**：Stack(StackFit.loose) 会把 sliver 给的紧约束
            // 放宽，卡片与手势热区会缩成内容宽（实测 123.5dp），右侧空白区
            // 滑动/点击全部 hit-test 落空，底色也画不满整行。
            Transform.translate(
              offset: Offset(-_reveal * _controller.value, 0),
              child: SizedBox(
                width: double.infinity,
                child: child,
              ),
            ),
            // 打开态下点卡片主体 = 收回（B2 定案）。做成**盖在已让位的卡片区域上
            // 的一层**而不是只靠外层 GestureDetector 的 onTap：那样要和卡内
            // InkWell 的手势竞技场抢 tap，胜负不定；这层是 Stack 最顶子节点，
            // 命中必归它，且 `right: _reveal` 保证不遮动作按钮。
            if (_commanded == 1)
              Positioned(
                left: -_reveal,
                right: _reveal,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _go(0),
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
      // 打开态下点卡片主体 = 收回，不触发详情（用户裁决 2026-10-18）。
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _commanded == 1 ? () => _go(0) : null,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: widget.child,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final SwipeAction action;

  @override
  Widget build(BuildContext context) {
    final Color fg = action.foreground ?? Theme.of(context).colorScheme.onPrimary;
    return Material(
      key: action.key,
      color: action.background,
      child: InkWell(
        onTap: action.onTap,
        child: SizedBox(
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(action.icon, size: 18, color: fg),
              const SizedBox(height: 2),
              Text(action.label,
                  style: TextStyle(fontSize: 11, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
