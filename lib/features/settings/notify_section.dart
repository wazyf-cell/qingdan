import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/platform/system_intents.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 提前量档位（§C2 §3）：**固定五档，不做自由文本输入**——省掉一套校验，
/// 也让「填了个 7 分钟」这种值根本进不了 prefs。
const List<int> kTaskLeadChoices = <int>[5, 15, 30, 60, 120];
const List<int> kCxLead1Choices = <int>[30, 60, 120, 240, 360];
const List<int> kCxLead2Choices = <int>[5, 15, 30, 60, 120];

/// 设置 · 通知节（M6-C2 §3）。
///
/// 只经 [NotifySettingsStore] 读写：`apply` 里「改内存 → notifyListeners → 落盘」
/// 一条龙，`ReminderCoordinator` 订阅那个通知去重排——**本节不碰通知引擎**，除顶部
/// 那张权限状态卡。两端共用同一份组件，[showTitle] 控制自绘标题（同 GeneralSection）。
/// Windows 端 `flutter_local_notifications` 不可用（§0.1），整节**置灰而不是隐藏**
/// ——隐藏会让人以为设置丢了。
class NotifySection extends StatelessWidget {
  const NotifySection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    // Provider 缺失时给一行可读提示，不让整棵设置树红屏：本节由设置树并行接线，
    // 缺 Provider 是接线方的问题，不该炸掉旁边几节能正常工作的内容。
    final NotifySettingsStore? store = _maybe<NotifySettingsStore>(context, true);
    final NotificationService? service = _maybe<NotificationService>(context, false);
    if (store == null) {
      return _note(colors, '通知设置尚未装配（NotifySettingsStore 未注册进 Provider 树）。');
    }
    final NotifySettings s = store.value;
    final bool grayed = service != null && !service.supported;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('通知', style: AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        if (grayed) _note(colors, '当前平台不支持系统通知；提醒功能仅在 Android 端生效。'),
        if (service != null && !grayed) _PermCard(service: service),
        _switch(colors, 'notify-enabled', '启用提醒', s.enabled, store.setEnabled),
        _group(colors, '清单'),
        _switch(colors, 'notify-task-lead', '到期前提前提醒', s.taskLeadEnabled,
            (v) => store.apply((x) => x.taskLeadEnabled = v)),
        _lead(colors, 'notify-task-lead-minutes', kTaskLeadChoices, s.taskLeadMinutes,
            (m) => store.apply((x) => x.taskLeadMinutes = m)),
        _switch(colors, 'notify-task-due', '到期时刻提醒', s.taskDueEnabled,
            (v) => store.apply((x) => x.taskDueEnabled = v)),
        _group(colors, '学习通'),
        _switch(colors, 'notify-cx-lead1', '截止前提醒（第一档）', s.chaoxingLead1Enabled,
            (v) => store.apply((x) => x.chaoxingLead1Enabled = v)),
        _lead(colors, 'notify-cx-lead1-minutes', kCxLead1Choices, s.chaoxingLead1Minutes,
            (m) => store.apply((x) => x.chaoxingLead1Minutes = m)),
        _switch(colors, 'notify-cx-lead2', '截止前提醒（第二档）', s.chaoxingLead2Enabled,
            (v) => store.apply((x) => x.chaoxingLead2Enabled = v)),
        _lead(colors, 'notify-cx-lead2-minutes', kCxLead2Choices, s.chaoxingLead2Minutes,
            (m) => store.apply((x) => x.chaoxingLead2Minutes = m)),
        _group(colors, '免打扰'),
        _switch(colors, 'notify-quiet', '免打扰时段', s.quietHoursEnabled,
            (v) => store.apply((x) => x.quietHoursEnabled = v)),
        _quietRow(context, store, s),
        const SizedBox(height: AppDimens.s12),
        // 诚实边界（§C2 §3）：省一句就像 bug。
        _note(colors, '提醒由本应用在打开时排入系统闹钟。应用被系统彻底杀死后，'
            '已排入的提醒仍会响；但新增或改动的待办要等应用下次打开才会重新排程。'
            '学习通提醒取决于最近一次刷新的数据。'),
      ],
    );
    return grayed ? IgnorePointer(child: Opacity(opacity: 0.45, child: body)) : body;
  }

  Widget _switch(AppColors colors, String key, String label, bool value,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        key: ValueKey<String>(key),
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: onChanged,
        title: Text(label, style: AppTypography.body.copyWith(color: colors.textPrimary)),
      );

  Widget _lead(AppColors colors, String key, List<int> choices, int value,
          ValueChanged<int> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(left: AppDimens.s8, bottom: AppDimens.s4),
        child: Row(
          children: <Widget>[
            Flexible(
                child: Text('提前',
                    style: AppTypography.meta.copyWith(color: colors.textSecondary))),
            DropdownButton<int>(
              key: ValueKey<String>(key),
              isDense: true,
              // 存进来的若不是档位值（手改 prefs / 旧版本残留）：hint 里显示原值、
              // 不谎报，也绝不当 value 传进去（DropdownButton 会断言失败）。
              value: choices.contains(value) ? value : null,
              hint: Text('$value 分钟',
                  style: AppTypography.meta.copyWith(color: colors.textSecondary)),
              items: <DropdownMenuItem<int>>[
                for (final int m in choices)
                  DropdownMenuItem<int>(value: m, child: Text('$m 分钟'))
              ],
              onChanged: (int? m) {
                if (m != null) onChanged(m);
              },
            ),
          ],
        ),
      );

  Widget _quietRow(BuildContext context, NotifySettingsStore store, NotifySettings s) =>
      Row(
        children: <Widget>[
          TextButton(
            key: const ValueKey<String>('notify-quiet-start'),
            onPressed: () => _pickTime(context, store, true, s.quietStart),
            child: Text('开始 ${s.quietStartText}'),
          ),
          const SizedBox(width: AppDimens.s12),
          TextButton(
            key: const ValueKey<String>('notify-quiet-end'),
            onPressed: () => _pickTime(context, store, false, s.quietEnd),
            child: Text('结束 ${s.quietEndText}'),
          ),
        ],
      );

  /// 免打扰起止走 `showTimePicker`（§C2 §3）；落盘只存**当日分钟数 int**，
  /// `TimeOfDay` 不许离开 UI 层。
  Future<void> _pickTime(BuildContext context, NotifySettingsStore store,
      bool start, int current) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: start ? '免打扰开始时间' : '免打扰结束时间',
    );
    if (picked == null || !context.mounted) return;
    final int minutes = picked.hour * 60 + picked.minute;
    await store.apply((x) => start ? x.quietStart = minutes : x.quietEnd = minutes);
  }

  Widget _group(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(top: AppDimens.s12, bottom: AppDimens.s4),
        child: Text(text,
            style: AppTypography.groupHeader.copyWith(color: colors.textSecondary)),
      );

  static Widget _note(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.s8),
        child: Text(text,
            style:
                AppTypography.meta.copyWith(color: colors.textFaint, height: 1.4)),
      );

  /// 取 [T]，Provider 缺失时返回 null 而不是抛 ProviderNotFoundException。
  static T? _maybe<T>(BuildContext context, bool listen) {
    try {
      return Provider.of<T>(context, listen: listen);
    } catch (_) {
      return null;
    }
  }
}

/// 系统通知权限状态卡（§C2 §3）：**首次进入本页才请求权限**，不在启动时请求。
/// 未开启时下方开关仍可操作（用户可以预设），只给一条橙色提示。
class _PermCard extends StatefulWidget {
  const _PermCard({required this.service});

  final NotificationService service;

  @override
  State<_PermCard> createState() => _PermCardState();
}

class _PermCardState extends State<_PermCard> {
  bool? _enabled;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    // 两个信号都要看：requestPermission 只反映授权框的结果，notificationsEnabled
    // 还包含系统里那条「通知总开关」是否被关掉。
    final bool granted = await widget.service.requestPermission();
    final bool systemOn = await widget.service.notificationsEnabled();
    if (!mounted) return;
    setState(() => _enabled = granted && systemOn);
  }

  Future<void> _openSettings() async {
    // 走 C3 的深链；两条路都失败才给手动路径文案（不猜原生行为，失败就是失败）。
    final bool ok = await SystemIntents.openAppNotificationSettings() ||
        await SystemIntents.openAppDetails();
    if (!mounted) return;
    setState(() => _hint = ok ? null : '打不开，请手动到 系统设置 → 应用 → 清单 里找');
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool on = _enabled ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          Flexible(
            child: Text('系统通知权限：${on ? '已开启' : '未开启'}',
                key: const ValueKey<String>('notify-perm-status'),
                style: AppTypography.body
                    .copyWith(color: on ? colors.success : colors.textPrimary)),
          ),
          const SizedBox(width: AppDimens.s12),
          TextButton(
            key: const ValueKey<String>('notify-perm-open'),
            onPressed: _openSettings,
            child: const Text('去开启'),
          ),
        ]),
        if (!on)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.s8),
            // 橙色用 priorityMedium token（浅 #F5A524 / 深 #FFB224），不是 overdue 红。
            child: Text('系统通知权限未开启，提醒不会响。',
                style: AppTypography.meta.copyWith(color: colors.priorityMedium)),
          ),
        if (_hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.s8),
            child: Text(_hint!,
                style: AppTypography.meta.copyWith(color: colors.textFaint)),
          ),
      ],
    );
  }
}
