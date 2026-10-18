import 'timestamps.dart';

/// 作息时间表（F28/F30）：`第 N 节 → 时间区间`。
///
/// **时间一律用「当日分钟数 int」**（`480 == 08:00`），`TimeOfDay` 只允许出现在
/// UI 层（§1.2 强制）。[semesterId] 当前版本恒为 null，即「默认作息表」。
class TimeTable {
  TimeTable({
    required this.id,
    required this.name,
    this.semesterId,
    this.createdTime,
    this.modifiedTime,
  });

  final String id;
  String name;
  String? semesterId;
  final DateTime? createdTime;
  final DateTime? modifiedTime;

  factory TimeTable.fromMap(Map<String, Object?> map) => TimeTable(
        id: map['id']! as String,
        name: map['name']! as String,
        semesterId: map['semester_id'] as String?,
        createdTime: msToDateTime(map['created_time'] as int?),
        modifiedTime: msToDateTime(map['modified_time'] as int?),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'semester_id': semesterId,
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

/// 一天里最后一个合法分钟数（`23:59`）。
///
/// `parseMinutes` 永远不可能给出比它更大的值，但**库里存的历史脏数据可以**
/// （旧版校验没有上限，平移也无天花板 → 结束时间 1475 即 `24:35`），
/// 所以载入与保存都必须过这道闸。
const int kMaxMinuteOfDay = 1439;

/// 一天最多几节（用户定：20 节够用，同时挡住「节数多到时间排过 24 时」）。
const int kMaxSectionsPerDay = 20;

/// 单个分钟数是否越出 00:00–23:59（校验、平移体检、UI 标红共用同一个判据）。
bool minuteOutOfRange(int minutes) => minutes < 0 || minutes > kMaxMinuteOfDay;

/// `HH:MM` 敲完之后的字符数（`inputFormatters` + `maxLength` 保证不会更长）。
const int kTimeShapeLength = 5;

String _rangeError(TimeDetail d) =>
    '第 ${d.section} 节时间超出 00:00–23:59 范围'
    '（${formatMinutes(d.startMinutes)}–${formatMinutes(d.endMinutes)}）';

/// 第一个越界节次的错误串，全部合法时返回 null。
///
/// 给 UI **载入既有数据**时做体检用：越界的时间格显示成 `24:35`，而
/// `parseMinutes('24:35')` 恒返回 null，用户从此改不动这一格——所以脏数据
/// 必须当场暴露，不能静默 clamp（静默改数据比报错更糟）。
String? firstOutOfRange(List<TimeDetail> details) {
  for (final TimeDetail d in details) {
    if (minuteOutOfRange(d.startMinutes) || minuteOutOfRange(d.endMinutes)) {
      return _rangeError(d);
    }
  }
  return null;
}

/// 校验节次列表：节数不超上限、每节落在 00:00–23:59 内、
/// 必须 `end > start`、按节次升序时时间也递增且互不重叠。
///
/// 返回 null 表示通过；否则返回可直接展示给用户的错误摘要（§2.3 保存校验）。
/// 相邻节之间允许零课间（`start == 上一节 end`）。
String? validateTimeDetails(List<TimeDetail> details) {
  if (details.length > kMaxSectionsPerDay) {
    return '一天最多 $kMaxSectionsPerDay 节，当前 ${details.length} 节';
  }
  for (final TimeDetail d in details) {
    if (minuteOutOfRange(d.startMinutes) || minuteOutOfRange(d.endMinutes)) {
      return _rangeError(d);
    }
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
///
/// **本函数不设天花板**（保持纯计算）；调用方拿结果去问 [firstOutOfRange]，
/// 越界就整次拒绝——旧版没这一步，20 节的课表能被顺移到 `24:35` 存进库。
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

/// `HH:MM` → 当日分钟数；格式不合法返回 null（UI 层输入校验用）。
///
/// 与 [formatMinutes] 成对：全链路只有「当日分钟数 int」一种时间表示（§1.2），
/// `TimeOfDay` 只允许出现在 UI 层，边界就在这里换算。
///
/// 这两个函数原先住在 `section_layout.dart`，2026-10-18 挪到这里是因为校验错误
/// 摘要要回显 `HH:MM`（`_rangeError`），而 `section_layout.dart` 本来就依赖
/// 本文件——留在原处会构成循环 import。`section_layout.dart` 现在 re-export
/// 它们，所有既有 `import 'section_layout.dart'` 的调用点不用改。
int? parseMinutes(String text) {
  final RegExpMatch? m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final int h = int.parse(m.group(1)!);
  final int min = int.parse(m.group(2)!);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return h * 60 + min;
}

/// 「已经敲成一个完整的 `HH:MM` 形状、却还是解析不过」——UI 只在这一刻才染红。
///
/// 为什么要有这一条（M6-A1）：`parseMinutes` 只认完整形状，用户敲到一半
/// （`0`、`09`、`09:`、`09:3`）必然返回 null。把「解析不过」直接当非法，就是
/// 每敲一个字符红一次，helperText 与错误行一出现/消失就把行高与按钮行顶得抖。
/// 非法**输入**照样要记账（见 `timetable_rows.dart` 的 `TimeCellRecords`），
/// 这里只管「现在该不该说它红」。
bool isInvalidFullTime(String text) =>
    text.length >= kTimeShapeLength && parseMinutes(text) == null;

/// 当日分钟数 → `HH:MM`（节次轴、课程块、作息错误摘要显示用）。
String formatMinutes(int minutes) {
  final int h = minutes ~/ 60;
  final int m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
