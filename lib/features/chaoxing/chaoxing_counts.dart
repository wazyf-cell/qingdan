/// 学习通面板要显示的几个数、头部那一句时间、以及失败原因的人话（纯函数，无 IO）。
///
/// 从 `chaoxing_model.dart` 搬出来只为了守住「单份源码不超过 300 行」那条红线，
/// 但顺带把这几件事变成可以直接单测的东西——模型里那两个 getter 只剩一行转发。
library;

import 'dart:async';
import 'dart:io';

import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

/// 只数「状态仍为待办且未被隐藏」的条目；**没拉取过返回 0**——这个数据刻意
/// 不落库、不后台刷，所以提示条与角标都停在上次拉取（M5 定案风险第 4 条已接受）。
///
/// [within] 非空时再要求「还没到点、且剩余不超过它」：那是「今天」页顶部
/// 那条 24 小时提示用的。没有截止时间的待办**不计进 within 这一档**（没法判断
/// 剩多久），但照常计进总角标。
int countTodos({
  required List<ChaoxingTask> tasks,
  required Set<String> hidden,
  required DateTime now,
  required bool fetched,
  Duration? within,
}) {
  if (!fetched) return 0;
  int n = 0;
  for (final ChaoxingTask t in tasks) {
    if (hidden.contains(t.key)) continue;
    if (t.stateAt(now, done: false) != ChaoxingTaskState.todo) continue;
    if (within != null) {
      final DateTime? due = t.dueAt;
      if (due == null) continue;
      final Duration left = due.difference(now);
      if (left.isNegative || left > within) continue;
    }
    n++;
  }
  return n;
}

/// 头部那一句：`22:20 更新`；不是今天就带日期（`10-19 22:20 更新`），跨年带年份。
///
/// 为什么用绝对时间而不是「16 分钟前」：用户要拿它和作业上写的截止时间对，
/// 相对时间还得自己在心里换算一次（2026-10-23 用户定案）。
///
/// 刷新中固定 `更新中…`：作业先到、考试后到，若作业一到就写时间，那两三秒里
/// 这句话对考试那一栏是假的（D1 定案——这个时间只代表「这批数据齐了」）。
String fetchedLabel({
  required DateTime? fetchedAt,
  required DateTime now,
  required bool loading,
  required bool stale,
}) {
  if (loading) return '更新中…';
  final DateTime? at = fetchedAt;
  if (at == null) return '未刷新';
  final DateTime l = at.toLocal();
  final DateTime n = now.toLocal();
  final String hm = '${_two(l.hour)}:${_two(l.minute)}';
  final String base;
  if (l.year != n.year) {
    base = '${l.year}-${_two(l.month)}-${_two(l.day)} $hm 更新';
  } else if (l.month != n.month || l.day != n.day) {
    base = '${_two(l.month)}-${_two(l.day)} $hm 更新';
  } else {
    base = '$hm 更新';
  }
  return stale ? '$base · 建议刷新' : base;
}

/// 失败原因压成一句能直接放进行里的中文；`null` 表示这次没失败。
///
/// 别把异常原文甩到界面上：它常带完整 URL 甚至 cookie 所在的域名，
/// 而用户只需要知道「哪一类问题、下一步做什么」。
String? refreshErrorText(Object? error) {
  if (error == null) return null;
  if (error is ChaoxingAuthException) return '会话已失效，请重新登录';
  if (error is TimeoutException) return '连不上学习通（超时）';
  if (error is SocketException) return '连不上学习通（网络不通）';
  return '刷新失败（${error.runtimeType}）';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `22:20`——失败行里要带上「上次成功是什么时候」，否则「刷新失败」四个字
/// 看不出你正看着的是几分钟前还是昨天下午的数据。
String hhmm(DateTime t) {
  final DateTime l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}
