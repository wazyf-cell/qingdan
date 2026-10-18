import 'dart:convert';

import 'course_uid.dart';
import 'timestamps.dart';

/// 课程来源。`origin` 存在的唯一理由：「覆盖导入」只软删导入来的课，
/// **不动用户手工创建的课**（§3.5）。
enum CourseOrigin { manual, import }

/// 课程条目：数据库中一行 == 一个「星期 + 节次 + 周次」组合（§1.1）。
class Course {
  Course({
    required this.id,
    required this.uid,
    required this.name,
    required this.weekday,
    required this.startSection,
    required this.endSection,
    required List<int> weeks,
    this.semesterId,
    this.teacher,
    this.location,
    this.rawWeeksText,
    this.origin = CourseOrigin.manual,
    this.importBatchId,
    this.deleted = false,
    this.createdTime,
    this.modifiedTime,
  }) : weeks = normalizeWeeks(weeks);

  final String id;

  /// 去重键，见 [courseUidOf]。
  String uid;
  String name;
  String? teacher;
  String? location;

  /// 1~7，1 == 周一（ISO 8601；**不用 0~6**，§1.1:51）。
  int weekday;
  int startSection;
  int endSection;

  /// 具体周次，**唯一真源**；构造与写库前都已排序去重（§2.4、§6.3.3）。
  List<int> weeks;

  /// 原始周次字符串，仅供展示与回溯，不参与任何逻辑（§2.4:140）。
  String? rawWeeksText;
  String? semesterId;
  CourseOrigin origin;
  String? importBatchId;
  int get colorIndex => courseColorIndex(name);
  bool deleted;
  final DateTime? createdTime;
  DateTime? modifiedTime;

  /// 空字符串一律归一为 null（§1.1:49：大学课表常有「待定」）。
  static String? blankToNull(String? value) {
    final String? t = value?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// 周次归一：排序 + 去重。UID 参与哈希前必须先过这里（§6.3.3）。
  static List<int> normalizeWeeks(List<int> weeks) =>
      <int>{...weeks}.toList(growable: false)..sort();

  bool isOn(int week) => weeks.contains(week);

  /// 时间槽是否重叠：同星期、节次区间相交、且有共同周次（§3.4 同槽多课）。
  bool overlaps(Course other) =>
      other.weekday == weekday &&
      other.startSection <= endSection &&
      other.endSection >= startSection &&
      other.weeks.any(isOn);

  Course copyWith({
    String? uid,
    String? name,
    String? teacher,
    String? location,
    int? weekday,
    int? startSection,
    int? endSection,
    List<int>? weeks,
    String? rawWeeksText,
    String? semesterId,
    CourseOrigin? origin,
    String? importBatchId,
    bool? deleted,
    DateTime? modifiedTime,
  }) =>
      Course(
        id: id,
        uid: uid ?? this.uid,
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        location: location ?? this.location,
        weekday: weekday ?? this.weekday,
        startSection: startSection ?? this.startSection,
        endSection: endSection ?? this.endSection,
        weeks: weeks ?? this.weeks,
        rawWeeksText: rawWeeksText ?? this.rawWeeksText,
        semesterId: semesterId ?? this.semesterId,
        origin: origin ?? this.origin,
        importBatchId: importBatchId ?? this.importBatchId,
        deleted: deleted ?? this.deleted,
        createdTime: createdTime,
        modifiedTime: modifiedTime ?? this.modifiedTime,
      );

  factory Course.fromMap(Map<String, Object?> map) => Course(
        id: map['id']! as String,
        uid: map['uid']! as String,
        name: map['name']! as String,
        teacher: map['teacher'] as String?,
        location: map['location'] as String?,
        weekday: map['weekday']! as int,
        startSection: map['start_section']! as int,
        endSection: map['end_section']! as int,
        weeks: decodeWeeks(map['weeks'] as String?),
        rawWeeksText: map['raw_weeks_text'] as String?,
        semesterId: map['semester_id'] as String?,
        origin: (map['origin'] as String?) == 'import'
            ? CourseOrigin.import
            : CourseOrigin.manual,
        importBatchId: map['import_batch_id'] as String?,
        deleted: (map['deleted'] ?? 0) as int == 1,
        createdTime: msToDateTime(map['created_time'] as int?),
        modifiedTime: msToDateTime(map['modified_time'] as int?),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'uid': uid,
        'name': name,
        'teacher': blankToNull(teacher),
        'location': blankToNull(location),
        'weekday': weekday,
        'start_section': startSection,
        'end_section': endSection,
        'weeks': encodeWeeks(weeks),
        'raw_weeks_text': rawWeeksText,
        'semester_id': semesterId,
        'origin': origin == CourseOrigin.import ? 'import' : 'manual',
        'import_batch_id': importBatchId,
        'deleted': deleted ? 1 : 0,
        'created_time': dateTimeToMs(createdTime),
        'modified_time': dateTimeToMs(modifiedTime),
      };

  /// `weeks` 落库为 JSON 数组字符串（§2.4:142，不自造二进制格式）。
  static String encodeWeeks(List<int> weeks) =>
      jsonEncode(normalizeWeeks(weeks));

  static List<int> decodeWeeks(String? json) => json == null || json.isEmpty
      ? <int>[]
      : (jsonDecode(json) as List<dynamic>).cast<int>();
}

/// 一次导入的元信息（§1.1 唯一补充实体）。**本地簿记，不参与同步**。
class ImportBatch {
  ImportBatch({
    required this.id,
    required this.fileName,
    required this.importedAt,
    this.countImported = 0,
    this.countUpdated = 0,
    this.countSkipped = 0,
  });

  final String id;
  final String fileName;
  final DateTime importedAt;
  int countImported;
  int countUpdated;
  int countSkipped;

  factory ImportBatch.fromMap(Map<String, Object?> map) => ImportBatch(
        id: map['id']! as String,
        fileName: map['file_name']! as String,
        importedAt: msToDateTime(map['imported_at'] as int?) ??
            DateTime.now().toUtc(),
        countImported: (map['count_imported'] ?? 0) as int,
        countUpdated: (map['count_updated'] ?? 0) as int,
        countSkipped: (map['count_skipped'] ?? 0) as int,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'file_name': fileName,
        'imported_at': dateTimeToMs(importedAt),
        'count_imported': countImported,
        'count_updated': countUpdated,
        'count_skipped': countSkipped,
      };
}
