/// 任务优先级（F2：4 级）。
///
/// 存储约定：显式存整数（0–3），不用字符串——排序与 LWW 比较都需要整数序。
enum TaskPriority {
  none(0),
  low(1),
  medium(2),
  high(3);

  const TaskPriority(this.value);

  /// SQLite / JSON 中的整数值。
  final int value;

  /// 从整数值还原；非法值兜底为 [none]（防御远端脏数据）。
  static TaskPriority fromValue(int value) => TaskPriority.values
      .firstWhere((TaskPriority p) => p.value == value, orElse: () => none);
}
