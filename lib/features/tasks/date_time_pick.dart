// 日期 + 可选时分的选择器（M6-A §A3）。
//
// 为什么是「先选日期、时间另有一钮」而不是选完日期自动弹时间：
// 需求写的是「可默认不填」，自动弹就等于逼每个人多取消一次。
// 存储层不动：`Task` 的三个日期字段本来就是完整 UTC 毫秒（`dateTimeToMs` 无截断），
// 过去只显示日期纯粹是 `showDatePicker` 恰好返回 00:00。
// 「00:00 == 没填时间」这条约定写在 `due_format.dart` 的 `hasTimeOfDay` 上。

import 'package:flutter/material.dart';

import 'package:qingdan/features/tasks/due_format.dart';

/// 可选范围：两年前 ~ 五年后（够用，且不挡住跨很多年的任务）。
DateTime _firstDate() => DateTime(DateTime.now().year - 2, 1, 1);

DateTime _lastDate() => DateTime(DateTime.now().year + 5, 12, 31);

/// 选日期。**不会**自动接着弹时间，返回当日零点（或保留 [initial] 已填的时分）。
Future<DateTime?> pickDateWithOptionalTime(
  BuildContext context, {
  DateTime? initial,
  String? helpText,
}) async {
  final DateTime base = initial ?? DateTime.now();
  final DateTime lower = _firstDate();
  final DateTime upper = _lastDate();
  final DateTime? picked = await showDatePicker(
    context: context,
    // 越界的旧值得夹回来：showDatePicker 要求 initialDate 落在 first~last 之间，否则 assert 崩。
    initialDate: _clamp(base, lower, upper),
    firstDate: lower,
    lastDate: upper,
    helpText: helpText,
  );
  if (picked == null) return null;
  return preserveTime(initial, picked);
}

DateTime _clamp(DateTime v, DateTime min, DateTime max) =>
    v.isBefore(min) ? min : (v.isAfter(max) ? max : v);

/// 改日期时把**已填的时分**带过去；没填（00:00）则继续是零点。
DateTime preserveTime(DateTime? previous, DateTime pickedDate) =>
    previous != null && hasTimeOfDay(previous)
        ? DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
            previous.hour, previous.minute)
        : DateTime(pickedDate.year, pickedDate.month, pickedDate.day);

/// 把时分合成到 [date] 那一天上（纯函数，测试可直接断言换算结果）。
DateTime applyTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);

/// 选时刻并合到 [date] 上；取消时间选择器 = 不改任何东西（返回 null）。
///
/// 注：`showTimePicker` 的 12/24 小时制跟随系统 locale，未接 `flutter_localizations`
/// 时按钮是英文 OK/Cancel —— 当前接受的现状（i18n 归 M6-E 批）。
Future<DateTime?> pickTimeFor(
  BuildContext context,
  DateTime date, {
  TimeOfDay? initial,
  String? helpText,
}) async {
  final TimeOfDay? picked = await showTimePicker(
    context: context,
    initialTime: initial ?? TimeOfDay.fromDateTime(date),
    helpText: helpText,
  );
  return picked == null ? null : applyTime(date, picked);
}
