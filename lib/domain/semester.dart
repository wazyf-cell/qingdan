import 'timestamps.dart';

/// 学期（F28）。当前版本全局只有一个激活学期（[isActive] == true）——这条仍成立。
///
/// 模型上 `Course`/`TimeTable` 都带可空 `semesterId`，是为了将来做「上学期
/// 归档」时不必迁数据。
///
/// 「**不做**并显示多个学期的 UI（§零.1）」这句已过期于 M6-D §7.1/§7.4：多学期
/// 界面已经落地，三个入口 = 周视图行内的 `features/course/semester_switcher.dart`、
/// 学期面板 `semester_sheet.dart`、课表管理整页 `course_manage_page.dart`。
class Semester {
  Semester({
    required this.id,
    required this.name,
    required this.firstWeekMonday,
    this.totalWeeks = defaultTotalWeeks,
    this.isActive = true,
    this.createdTime,
    this.modifiedTime,
  });

  /// 学期总周数默认值与上限（§1.1：范围 1~30）。
  static const int defaultTotalWeeks = 16;
  static const int minTotalWeeks = 1;
  static const int maxTotalWeeks = 30;

  final String id;
  String name;

  /// 第 1 周的周一。
  ///
  /// **按「纯日期」处理**：落库为该日 00:00 的 UTC 毫秒，字段也是 `DateTime.utc`
  /// 构造的零点。这样周次算术只用整日差，不受设备时区与夏令时影响
  /// （§1.2 只允许一种时间表示；实测模拟器时区并非 Asia/Shanghai）。
  DateTime firstWeekMonday;
  int totalWeeks;
  bool isActive;
  final DateTime? createdTime;
  DateTime? modifiedTime;

  /// 把任意日期归一化到「该周的周一」（§2.1：用户选开学第一周的任意一天）。
  ///
  /// 只取年月日，丢弃时分；周一 == weekday 1（ISO 8601，Dart 的 `DateTime.monday`）。
  static DateTime mondayOf(DateTime date) {
    final DateTime day = DateTime.utc(date.year, date.month, date.day);
    final int back = (day.weekday - DateTime.monday) % 7;
    return day.subtract(Duration(days: back));
  }

  /// 某日期是第几周；不在学期范围内返回 null（渲染与今日课共用，§6.3.2）。
  int? weekOf(DateTime date) {
    final DateTime monday = Semester.mondayOf(date);
    final int days = monday.difference(firstWeekMonday).inDays;
    if (days < 0) return null;
    final int week = (days / 7).floor() + 1;
    return week > totalWeeks ? null : week;
  }

  /// 第 [week] 周的周一。
  DateTime mondayOfWeek(int week) =>
      firstWeekMonday.add(Duration(days: (week - 1) * 7));

  Semester copyWith({
    String? name,
    DateTime? firstWeekMonday,
    int? totalWeeks,
    bool? isActive,
    DateTime? modifiedTime,
  }) =>
      Semester(
        id: id,
        name: name ?? this.name,
        firstWeekMonday: firstWeekMonday ?? this.firstWeekMonday,
        totalWeeks: totalWeeks ?? this.totalWeeks,
        isActive: isActive ?? this.isActive,
        createdTime: createdTime,
        modifiedTime: modifiedTime ?? this.modifiedTime,
      );

  factory Semester.fromMap(Map<String, Object?> map) => Semester(
        id: map['id']! as String,
        name: map['name']! as String,
        firstWeekMonday:
            msToDateTime(map['first_week_monday']! as int)!,
        totalWeeks: (map['total_weeks'] ?? defaultTotalWeeks) as int,
        isActive: (map['is_active'] ?? 1) as int == 1,
        createdTime: msToDateTime(map['created_time'] as int?),
        modifiedTime: msToDateTime(map['modified_time'] as int?),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'first_week_monday': dateTimeToMs(firstWeekMonday),
        'total_weeks': totalWeeks,
        'is_active': isActive ? 1 : 0,
        'created_time': dateTimeToMs(createdTime),
        'modified_time': dateTimeToMs(modifiedTime),
      };
}
