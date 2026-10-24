import 'package:flutter/material.dart';

import 'package:qingdan/platform/widget_bridge.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 「添加小组件」面板（v1.0.6）。
///
/// 能做的只有 `requestPinAppWidget`：由**桌面**弹出一次确认，允许后卡片直接
/// 落到主屏。应用无法静默添加，也打不开桌面的组件选择器（没有公开接口）——
/// 所以桌面不支持时如实给「长按桌面」的手路，不假装能跳过去。
///
/// 回执写在本面板里，不用 SnackBar：modal route 下面的 SnackBar 用户看不见。
Future<void> showAddWidgetSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => const SafeArea(
        top: false,
        child: SingleChildScrollView(child: _AddWidgetBody()),
      ),
    );

class _AddWidgetBody extends StatefulWidget {
  const _AddWidgetBody();

  @override
  State<_AddWidgetBody> createState() => _AddWidgetBodyState();
}

class _AddWidgetBodyState extends State<_AddWidgetBody> {
  bool? _supported;
  String? _said;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetBridge.isPinSupported().then((bool ok) {
      if (mounted) setState(() => _supported = ok);
    });
  }

  Future<void> _pin(String provider, String label) async {
    final bool ok = await WidgetBridge.pin(provider);
    if (!mounted) return;
    setState(() {
      _failed = !ok;
      _said = ok
          ? '已向系统发出「$label」的添加请求：允许后就会出现在桌面。'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, 0, AppDimens.s16, AppDimens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('添加小组件', style: AppTypography.panelTitle),
          const SizedBox(height: AppDimens.s8),
          Text(
            '卡片只读，点一下进对应页面。添加时系统会弹一次确认。',
            style: AppTypography.meta,
          ),
          const SizedBox(height: AppDimens.s12),
          _WidgetRow(
            rowKey: 'add-widget-today',
            icon: Icons.task_alt,
            title: '清单 · 今天',
            subtitle: '今天未完成的任务；2×2 两条，拉高到 2×4 五条',
            onAdd: _supported == true
                ? () => _pin('today', '清单 · 今天')
                : null,
          ),
          _WidgetRow(
            rowKey: 'add-widget-course',
            icon: Icons.calendar_view_week,
            title: '课表 · 今日',
            subtitle: '今天要上的课（2×4 为主）；点进课表页',
            onAdd: _supported == true
                ? () => _pin('course', '课表 · 今日')
                : null,
          ),
          _WidgetRow(
            rowKey: 'add-widget-chaoxing',
            icon: Icons.school,
            title: '学习通 · 待办',
            subtitle: '未交的作业与考试；最多 15 条，再多的部分可滚动查看',
            onAdd: _supported == true
                ? () => _pin('chaoxing', '学习通 · 待办')
                : null,
          ),
          if (_said != null) ...<Widget>[
            const SizedBox(height: AppDimens.s12),
            Text(_said!, style: AppTypography.meta),
          ],
          if (_failed) ...<Widget>[
            const SizedBox(height: AppDimens.s8),
            Text(
              '这台设备的桌面不支持直接添加。请先回到桌面，长按空白处 → '
              '小组件（有的机型叫「服务卡片」）→ 清单，再把卡片拖出来。',
              style: TextStyle(color: colors.overdue, fontSize: 12),
            ),
            const SizedBox(height: AppDimens.s8),
            Row(
              children: <Widget>[
                OutlinedButton(
                  key: const ValueKey<String>('add-widget-go-home'),
                  onPressed: WidgetBridge.goHome,
                  child: const Text('去桌面'),
                ),
              ],
            ),
          ],
          if (_supported == false && !_failed) ...<Widget>[
            const SizedBox(height: AppDimens.s8),
            Text(
              '这台设备的桌面不支持「直接添加」：长按桌面空白处 → 小组件'
              '（有的机型叫「服务卡片」）→ 清单。',
              style: AppTypography.meta,
            ),
          ],
          const SizedBox(height: AppDimens.s16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetRow extends StatelessWidget {
  const _WidgetRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });

  final String rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ListTile(
      key: ValueKey<String>(rowKey),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: colors.accent),
      title: Text(title, style: AppTypography.body),
      subtitle: Text(subtitle, style: AppTypography.meta),
      trailing: TextButton(
        onPressed: onAdd,
        child: const Text('添加'),
      ),
    );
  }
}
