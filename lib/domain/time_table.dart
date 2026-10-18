import 'timestamps.dart';

/// 作息时间表（F28/F30）：`第 N 节 → 时间区间`。
///
/// **时间一律用「当日分钟数 int」**（`480 == 08:00`），`TimeOfDay` 只允许出现在
/// UI 层（§1.2 强制）。v6（M6-D）起 [semesterId] 可为学期专属作息；
/// `semester_id == null && isTemplate` 表示模板库条目，其中 [isBuiltin] 行
/// 是每台设备本地 seed 的内置模板（不参与同步）。
class TimeTable {
  TimeTable({
    required this.id,
    required this.name,
    this.semesterId,
    this.isTemplate = false,
    this.isBuiltin = false,
    this.createdTime,
    this.modifiedTime,
  });

  final String id;
  String name;
  String? semesterId;

  /// v6 列 `is_template`：模板库条目（可被新建学期复制快照）。
  final bool isTemplate;

  /// v6 列 `is_builtin`：内置模板（不可删、不可改名、不进同步）。
  final bool isBuiltin;
  final DateTime? createdTime;
  final DateTime? modifiedTime;

  TimeTable copyWith({
    String? name,
    String? semesterId,
    bool? isTemplate,
    bool? isBuiltin,
    DateTime? createdTime,
    DateTime? modifiedTime,
  }) =>
      TimeTable(
        id: id,
        name: name ?? this.name,
        semesterId: semesterId ?? this.semesterId,
        isTemplate: isTemplate ?? this.isTemplate,
        isBuiltin: isBuiltin ?? this.isBuiltin,
        createdTime: createdTime ?? this.createdTime,
        modifiedTime: modifiedTime ?? this.modifiedTime,
      );

  factory TimeTable.fromMap(Map<String, Object?> map) => TimeTable(
        id: map['id']! as String,
        name: map['name']! as String,
        semesterId: map['semester_id'] as String?,
        isTemplate: (map['is_template'] as int? ?? 0) != 0,
        isBuiltin: (map['is_builtin'] as int? ?? 0) != 0,
        createdTime: msToDateTime(map['created_time'] as int?),
        modifiedTime: msToDateTime(map['modified_time'] as int?),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'semester_id': semesterId,
        'is_template': isTemplate ? 1 : 0,
        'is_builtin': isBuiltin ? 1 : 0,
        'created_time': dateTimeToMs(createdTime),
        'modified_time': dateTimeToMs(modifiedTime),
      };
}

/// 作息表里的一节。[section] 从 1 开始且**允许跳号**（§2.2）。
class TimeDetail {
  const TimeDetail({
    required this.id,
    required this.timetableId,
    required this.section,
    required this.startMinutes,
    required this.endMinutes,
    this.createdTime,
    this.modifiedTime,
  });

  final String id;
  final String timetableId;
  final int section;

  /// 当日分钟数。
  final int startMinutes;
  final int endMinutes;

  /// 行级时间戳：字段级 LWW 的比较基准（v5 起才有列，老行可能为 null）。
  final DateTime? createdTime;
  final DateTime? modifiedTime;

  TimeDetail copyWith({
    int? startMinutes,
    int? endMinutes,
    int? section,
    DateTime? modifiedTime,
  }) =>
      TimeDetail(
        id: id,
        timetableId: timetableId,
        section: section ?? this.section,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        createdTime: createdTime,
        modifiedTime: modifiedTime ?? this.modifiedTime,
      );

  factory TimeDetail.fromMap(Map<String, Object?> map) => TimeDetail(
        id: map['id']! as String,
        timetableId: map['timetable_id']! as String,
        section: map['section']! as int,
        startMinutes: map['start_minutes']! as int,
        endMinutes: map['end_minutes']! as int,
        createdTime: msToDateTime(map['created_time'] as int?),
        modifiedTime: msToDateTime(map['modified_time'] as int?),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'timetable_id': timetableId,
        'section': section,
        'start_minutes': startMinutes,
        'end_minutes': endMinutes,
        'created_time': dateTimeToMs(createdTime),
        'modified_time': dateTimeToMs(modifiedTime),
      };
}

/// 校验节次列表：必须 `end > start`、按节次升序时时间也递增且互不重叠。
///
/// 返回 null 表示通过；否则返回可直接展示给用户的错误摘要（§2.3 保存校验）。
/// 相邻节之间允许零课间（`start == 上一节 end`）。
String? validateTimeDetails(List<TimeDetail> details) {
  for (final TimeDetail d in details) {
    if (d.section < 1) return '节次必须从 1 开始，出现 ${d.section}';
    if (d.endMinutes <= d.startMinutes) {
      return '第 ${d.section} 节的结束时间必须晚于开始时间';
    }
  }
  final List<TimeDetail> sorted = <TimeDetail>[...details]
    ..sort((TimeDetail a, TimeDetail b) => a.section.compareTo(b.section));
  for (int i = 1; i < sorted.length; i++) {
    if (sorted[i].startMinutes < sorted[i - 1].endMinutes) {
      return '第 ${sorted[i - 1].section} 节与第 ${sorted[i].section} 节时间重叠';
    }
  }
  return null;
}

/// 「快速生成」作息表（§2.3 预设：第一节开始 + 每节时长 + 课间 + 每天节数，
/// 可选午休）。纯函数，不碰数据库，界面「生成预览」与落库共用同一份实现。
List<TimeDetail> generateTimeDetails({
  required String timetableId,
  required int firstStartMinutes,
  required int lessonMinutes,
  required int breakMinutes,
  required int sectionCount,
  int? lunchAfterSection,
  int lunchMinutes = 0,
}) {
  final List<TimeDetail> out = <TimeDetail>[];
  int cursor = firstStartMinutes;
  for (int section = 1; section <= sectionCount; section++) {
    final int end = cursor + lessonMinutes;
    out.add(TimeDetail(
      id: '',
      timetableId: timetableId,
      section: section,
      startMinutes: cursor,
      endMinutes: end,
    ));
    cursor = end + breakMinutes;
    if (lunchAfterSection == section) cursor += lunchMinutes;
  }
  return out;
}

/// 「改第 [section] 节的开始时间 → 该节之后整体顺移 [deltaMinutes] 分钟，
/// 该节之前不动」（§2.3 的最常见诉求）。
///
/// 顺移而非重算：节与节之间的课间由用户逐节设定（可能不等），按 delta 平移
/// 才能既满足「改第 1 节后面全跟着走」，又不毁掉用户手工调过的课间。
List<TimeDetail> shiftSectionsAfter(
  List<TimeDetail> details,
  int section,
  int deltaMinutes,
) {
  final List<TimeDetail> out = <TimeDetail>[...details]
    ..sort((TimeDetail a, TimeDetail b) => a.section.compareTo(b.section));
  return <TimeDetail>[
    for (final TimeDetail d in out)
      d.section > section
          ? d.copyWith(startMinutes: d.startMinutes + deltaMinutes,
              endMinutes: d.endMinutes + deltaMinutes)
          : d,
  ];
}

/// 删除中间一节后把节次号补位重排（§2.3：节次本质是序号，不是 ID）。
List<TimeDetail> renumber(List<TimeDetail> details) {
  final List<TimeDetail> sorted = <TimeDetail>[...details]
    ..sort((TimeDetail a, TimeDetail b) => a.section.compareTo(b.section));
  return <TimeDetail>[
    for (int i = 0; i < sorted.length; i++) sorted[i].copyWith(section: i + 1),
  ];
}
