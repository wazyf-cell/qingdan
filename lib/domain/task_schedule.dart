/// 任务日期规则（纯函数，无 IO）：今天 / 最近 7 天的成员资格、关注时间、
/// 分组与行内日期文案。
///
/// 2026-10-26 定案：开始或截止任一命中即进入今天/最近 7 天；结束时间只显示，
/// 不参与筛选。00:00 仍表示「没填时刻」，日期型截止按当天结束算，不因午夜
/// 过点就标已过期。
library;

import 'task.dart';

enum TaskDateGroup { overdue, started, today, tomorrow, later }

/// `00:00` = 没填时分（沿用 M6-A §A3 的约定）。
bool hasTimeOfDay(DateTime value) => value.hour != 0 || value.minute != 0;

DateTime dayStart(DateTime now) => DateTime(now.year, now.month, now.day);

DateTime dayEnd(DateTime now) => dayStart(now).add(const Duration(days: 1));

DateTime next7End(DateTime now) => dayEnd(now).add(const Duration(days: 6));

/// 截止是否已经过期。日期型截止（00:00）按当天结束算：今天不标红，
/// 只有日期早于今天才算过期。
bool dueIsOverdue(DateTime? dueUtc, DateTime now) {
  if (dueUtc == null) return false;
  final DateTime due = dueUtc.toLocal();
  if (hasTimeOfDay(due)) return due.isBefore(now);
  return DateTime(due.year, due.month, due.day)
      .isBefore(dayStart(now));
}

/// 关注时间 = 开始 / 截止中较早的一个；用于排序与分组。
DateTime? focusOf(Task t) {
  final DateTime? start = t.startDate?.toLocal();
  final DateTime? due = t.dueDate?.toLocal();
  if (start == null) return due;
  if (due == null) return start;
  return start.isBefore(due) ? start : due;
}

bool inToday(Task t, DateTime now) {
  if (t.completed) return false;
  final DateTime end = dayEnd(now);
  final DateTime? start = t.startDate?.toLocal();
  final DateTime? due = t.dueDate?.toLocal();
  return (start != null && start.isBefore(end)) ||
      (due != null && due.isBefore(end));
}

bool inNext7(Task t, DateTime now) {
  if (t.completed) return false;
  final DateTime end = next7End(now);
  final DateTime? start = t.startDate?.toLocal();
  final DateTime? due = t.dueDate?.toLocal();
  return (start != null && start.isBefore(end)) ||
      (due != null && due.isBefore(end));
}

TaskDateGroup groupOf(Task t, DateTime now) {
  if (dueIsOverdue(t.dueDate, now)) return TaskDateGroup.overdue;
  final DateTime? start = t.startDate?.toLocal();
  if (start != null && start.isBefore(dayStart(now))) {
    return TaskDateGroup.started;
  }
  final DateTime? focus = focusOf(t);
  if (focus == null) return TaskDateGroup.later;
  if (focus.isBefore(dayEnd(now))) return TaskDateGroup.today;
  if (focus.isBefore(dayEnd(now).add(const Duration(days: 1)))) {
    return TaskDateGroup.tomorrow;
  }
  return TaskDateGroup.later;
}

int groupRank(TaskDateGroup group) => switch (group) {
      TaskDateGroup.overdue => 0,
      TaskDateGroup.started => 1,
      TaskDateGroup.today => 2,
      TaskDateGroup.tomorrow => 3,
      TaskDateGroup.later => 4,
    };

String groupLabel(TaskDateGroup group) => switch (group) {
      TaskDateGroup.overdue => '已过期',
      TaskDateGroup.started => '已开始',
      TaskDateGroup.today => '今天',
      TaskDateGroup.tomorrow => '明天',
      TaskDateGroup.later => '以后',
    };

/// 行内日期文字：今天只给时分，明天带「明」，其他日期带 `M/D`；
/// 有时刻时未来日期也保留时刻（旧实现只给 M/D）。
String dateText(DateTime local, DateTime now) {
  final DateTime today = dayStart(now);
  final DateTime day = DateTime(local.year, local.month, local.day);
  final int days = day.difference(today).inDays;
  final String hhmm = '${_two(local.hour)}:${_two(local.minute)}';
  if (hasTimeOfDay(local)) {
    if (days == 0) return hhmm;
    if (days == 1) return '明 $hhmm';
    return '${local.month}/${local.day} $hhmm';
  }
  if (days == 0) return '今天';
  if (days == 1) return '明天';
  return '${local.month}/${local.day}';
}

/// 任务行的一行日期文案 + 是否用逾期色。
({String? text, bool overdue}) taskDateLine(Task t, DateTime now) {
  final DateTime? start = t.startDate?.toLocal();
  final DateTime? end = t.endDate?.toLocal();
  final DateTime? due = t.dueDate?.toLocal();
  final bool overdue = !t.completed && dueIsOverdue(t.dueDate, now);
  if (start == null && end == null && due == null) {
    return (text: null, overdue: false);
  }

  String text;
  if (start != null && end != null) {
    final String range = _rangeText(start, end, now);
    if (due == null) {
      text = range;
    } else if (end.isAtSameMomentAs(due)) {
      text = '$range 截止';
    } else {
      text = '$range · 截止 ${dateText(due, now)}';
    }
  } else if (start != null) {
    if (due == null) {
      text = '${dateText(start, now)} 开始';
    } else if (start.isAtSameMomentAs(due)) {
      text = dateText(due, now);
    } else {
      text = '${dateText(start, now)} 开始 · ${dateText(due, now)} 截止';
    }
  } else if (end != null) {
    if (due == null) {
      text = '${dateText(end, now)} 结束';
    } else if (end.isAtSameMomentAs(due)) {
      text = dateText(due, now);
    } else {
      text = '${dateText(end, now)} 结束 · 截止 ${dateText(due, now)}';
    }
  } else {
    text = dateText(due!, now);
  }
  return (text: text, overdue: overdue);
}

String _rangeText(DateTime start, DateTime end, DateTime now) {
  final DateTime sd = DateTime(start.year, start.month, start.day);
  final DateTime ed = DateTime(end.year, end.month, end.day);
  if (sd == ed) {
    if (hasTimeOfDay(start) && hasTimeOfDay(end)) {
      final DateTime today = dayStart(now);
      final String prefix = sd == today
          ? ''
          : sd == today.add(const Duration(days: 1))
              ? '明 '
              : '${start.month}/${start.day} ';
      return '$prefix${_hhmm(start)}–${_hhmm(end)}';
    }
    if (!hasTimeOfDay(start) && !hasTimeOfDay(end)) {
      return dateText(start, now);
    }
  }
  return '${_fullText(start)}–${_fullText(end)}';
}

String _fullText(DateTime d) {
  final String date = '${d.month}/${d.day}';
  return hasTimeOfDay(d) ? '$date ${_hhmm(d)}' : date;
}

String _hhmm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');
