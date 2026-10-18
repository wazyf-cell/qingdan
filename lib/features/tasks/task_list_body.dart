import 'package:flutter/material.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 智能清单完成行塌缩动画：高度 40 → 0（200ms），期间行已从数据源移除。
class CollapsingRow extends StatefulWidget {
  const CollapsingRow({super.key});

  @override
  State<CollapsingRow> createState() => _CollapsingRowState();
}

class _CollapsingRowState extends State<CollapsingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _controller, curve: Curves.linear),
      alignment: Alignment.topCenter,
      child: const SizedBox(height: AppDimens.taskRowHeight),
    );
  }
}

/// 列表体：手动排序模式用 ReorderableListView（拖拽排序），其余用普通 ListView。
///
/// [groupHeaders] 与 [rows] 等长；非空字符串表示该行前渲染分组头（仅手动排序）。
class TaskListBody extends StatelessWidget {
  const TaskListBody({
    super.key,
    required this.rows,
    required this.groupHeaders,
    required this.reorderable,
    required this.buildRow,
    required this.onReorder,
    required this.emptyState,
  });

  final List<Task> rows;

  /// 与 [rows] 等长；非空 → 在该行上方插入分组头。
  final List<String?> groupHeaders;
  final bool reorderable;
  final Widget Function(BuildContext context, Task task, int index) buildRow;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget emptyState;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return emptyState;
    if (!reorderable) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: AppDimens.s24),
        itemCount: rows.length,
        itemBuilder: (BuildContext context, int index) => _withHeader(
          context,
          index,
          buildRow(context, rows[index], index),
        ),
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: AppDimens.s24),
      itemCount: rows.length,
      onReorderItem: onReorder,
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? _) {
            final double t = Curves.easeOut.transform(animation.value);
            return Transform.scale(
              scale: 1.0 + 0.02 * t,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 8 * t,
                borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (BuildContext context, int index) => _withHeader(
        context,
        index,
        buildRow(context, rows[index], index),
        key: ValueKey<String>(rows[index].id),
      ),
    );
  }

  Widget _withHeader(BuildContext context, int index, Widget row,
      {Key? key}) {
    final String? header = groupHeaders[index];
    if (header == null) return _wrap(key, row);
    return _wrap(
      key,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: AppDimens.groupHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.s8),
            alignment: Alignment.centerLeft,
            child: Text(
              header,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600),
            ),
          ),
          row,
        ],
      ),
    );
  }

  Widget _wrap(Key? key, Widget child) => key == null
      ? child
      // ignore: avoid_redundant_argument_values
      : KeyedSubtree(key: key, child: child);
}
