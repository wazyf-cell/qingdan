/// 学习通面板要显示的两个数与「N 分钟前」文案（纯函数，无 IO）。
///
/// 从 `chaoxing_model.dart` 搬出来只为了守住「单份源码不超过 300 行」那条红线，
/// 但顺带把这两件事变成可以直接单测的东西——模型里那两个 getter 只剩一行转发。
library;

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

/// 「数据 · N 分钟前」文案；未抓取过时说「未刷新」。[stale] 由调用方算
/// （阈值是模型那个 `kStaleAfter`，搬过来会变成两份常量）。
///
/// 名字不叫 `fetchedAgoText`：模型上有个同名 getter，同名会让 getter 里的
/// 「转发」在类作用域里解析到自己，变成无限递归。
String fetchedAgo({
  required DateTime? fetchedAt,
  required DateTime now,
  required bool stale,
}) {
  final DateTime? at = fetchedAt;
  if (at == null) return '未刷新';
  final int m = now.difference(at).inMinutes;
  final String base = m < 1 ? '刚刚' : '$m 分钟前';
  return stale ? '$base · 建议刷新' : base;
}
