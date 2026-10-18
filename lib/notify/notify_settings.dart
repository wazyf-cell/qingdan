// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 通知设置（M6-C2）：11 个 `notify.*` key 的值类 + SharedPreferences 存取。
///
/// key 名与默认值**逐字照抄** `待执行-M6总纲.md` §五——改名等于丢掉用户已存的设置。
/// 免打扰起止用「当日分钟数 int」（§1.2：`TimeOfDay` 只允许出现在 UI 层），文案
/// 换算复用领域层的 `formatMinutes` / `parseMinutes`。
///
/// 字段可写（与 `TimeTable`、`SettingsModel` 同范式），但**只能经
/// [NotifySettingsStore.apply] 改**：那条路径同时落盘并通知监听者去重排提醒。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/domain/section_layout.dart' show formatMinutes;
import 'package:qingdan/notify/reminder_plan.dart' show ReminderConfig;

class NotifySettings implements ReminderConfig {
  NotifySettings({
    this.enabled = true,
    this.taskLeadEnabled = true,
    this.taskLeadMinutes = 30,
    this.taskDueEnabled = true,
    this.chaoxingLead1Enabled = true,
    this.chaoxingLead1Minutes = 120,
    this.chaoxingLead2Enabled = true,
    this.chaoxingLead2Minutes = 30,
    this.quietHoursEnabled = true,
    this.quietStart = 1380, // 23:00
    this.quietEnd = 420, // 07:00
  });

  static const String kEnabledKey = 'notify.enabled';
  static const String kTaskLeadEnabledKey = 'notify.task.leadEnabled';
  static const String kTaskLeadMinutesKey = 'notify.task.leadMinutes';
  static const String kTaskDueEnabledKey = 'notify.task.dueEnabled';
  static const String kCxLead1EnabledKey = 'notify.chaoxing.lead1Enabled';
  static const String kCxLead1MinutesKey = 'notify.chaoxing.lead1Minutes';
  static const String kCxLead2EnabledKey = 'notify.chaoxing.lead2Enabled';
  static const String kCxLead2MinutesKey = 'notify.chaoxing.lead2Minutes';
  static const String kQuietEnabledKey = 'notify.quietHoursEnabled';
  static const String kQuietStartKey = 'notify.quietStart';
  static const String kQuietEndKey = 'notify.quietEnd';

  @override
  bool enabled,
      taskLeadEnabled,
      taskDueEnabled,
      chaoxingLead1Enabled,
      chaoxingLead2Enabled,
      quietHoursEnabled;
  @override
  int taskLeadMinutes,
      chaoxingLead1Minutes,
      chaoxingLead2Minutes,
      quietStart,
      quietEnd;

  /// 缺项回落到构造器默认值（首次使用、或用户手动清过应用数据）。
  factory NotifySettings.fromPrefs(SharedPreferences p) => NotifySettings(
        enabled: p.getBool(kEnabledKey) ?? true,
        taskLeadEnabled: p.getBool(kTaskLeadEnabledKey) ?? true,
        taskLeadMinutes: p.getInt(kTaskLeadMinutesKey) ?? 30,
        taskDueEnabled: p.getBool(kTaskDueEnabledKey) ?? true,
        chaoxingLead1Enabled: p.getBool(kCxLead1EnabledKey) ?? true,
        chaoxingLead1Minutes: p.getInt(kCxLead1MinutesKey) ?? 120,
        chaoxingLead2Enabled: p.getBool(kCxLead2EnabledKey) ?? true,
        chaoxingLead2Minutes: p.getInt(kCxLead2MinutesKey) ?? 30,
        quietHoursEnabled: p.getBool(kQuietEnabledKey) ?? true,
        quietStart: p.getInt(kQuietStartKey) ?? 1380,
        quietEnd: p.getInt(kQuietEndKey) ?? 420,
      );

  /// 11 项一次写全：不做增量 set，省得留下「改了一半」的键。
  Future<void> writeTo(SharedPreferences p) async {
    await p.setBool(kEnabledKey, enabled);
    await p.setBool(kTaskLeadEnabledKey, taskLeadEnabled);
    await p.setInt(kTaskLeadMinutesKey, taskLeadMinutes);
    await p.setBool(kTaskDueEnabledKey, taskDueEnabled);
    await p.setBool(kCxLead1EnabledKey, chaoxingLead1Enabled);
    await p.setInt(kCxLead1MinutesKey, chaoxingLead1Minutes);
    await p.setBool(kCxLead2EnabledKey, chaoxingLead2Enabled);
    await p.setInt(kCxLead2MinutesKey, chaoxingLead2Minutes);
    await p.setBool(kQuietEnabledKey, quietHoursEnabled);
    await p.setInt(kQuietStartKey, quietStart);
    await p.setInt(kQuietEndKey, quietEnd);
  }

  String get quietStartText => formatMinutes(quietStart);
  String get quietEndText => formatMinutes(quietEnd);
}

/// 通知设置的持有者：读一次、改一项就落盘 + 通知。
///
/// 监听者（`ReminderCoordinator`）收到通知后重排全部提醒——规格 §C2「任一 setter
/// 后重排」就是挂在这里，设置页自己不需要知道通知引擎的存在。
class NotifySettingsStore extends ChangeNotifier {
  NotifySettingsStore({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;
  NotifySettings _value = NotifySettings();

  NotifySettings get value => _value;

  /// 幂等：启动时读一次。读不到任何 key 就是全默认值。
  Future<void> load() async {
    _value = NotifySettings.fromPrefs(await _instance());
    notifyListeners();
  }

  /// 改设置的唯一入口：先改内存并通知（UI 立即跟手），再写盘。
  /// 例：`await store.apply((NotifySettings s) => s.taskLeadMinutes = 60);`
  Future<void> apply(void Function(NotifySettings settings) change) async {
    change(_value);
    notifyListeners();
    await _value.writeTo(await _instance());
  }

  /// 总开关关掉后调用方要 `cancelAll()`；快照清理不在这里（属 C4）。
  Future<void> setEnabled(bool enabled) =>
      apply((NotifySettings s) => s.enabled = enabled);

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();
}
