import 'course.dart';

/// 课表「上次更新 / 导入时间」的取值（M6-A A8，M6-D §八 补学期维度）。
///
/// 为什么不落库：它是 `import_batches` 该学期最近一次 + 本学期课程
/// `MAX(modified_time)` 两个只读查询的派生结果，存下来还得管失效，
/// 不如每次 `load()` 现取。
enum CourseFreshnessKind { none, import, edit }

/// 一条导入批次 + 它的学期归属（M6-D §八）。
///
/// v6 起 `import_batches` 有 `semester_id` 列；**老批次该列为 NULL**，
/// 归属未知，界面上显示「（学期未知）」而不是假装属于当前学期。
/// [semesterName] 由读侧 LEFT JOIN `semesters` 带出——NULL 或学期已删都归为未知。
class ImportBatchEntry {
  const ImportBatchEntry({
    required this.batch,
    this.semesterId,
    this.semesterName,
  });

  factory ImportBatchEntry.fromRow(Map<String, Object?> row) {
    final ImportBatch batch = ImportBatch.fromMap(row);
    return ImportBatchEntry(
      batch: batch,
      semesterId: row['semester_id'] as String?,
      semesterName: row['semester_name'] as String?,
    );
  }

  final ImportBatch batch;

  /// NULL = v6 之前的老批次，不知道属于哪个学期。
  final String? semesterId;

  /// 归属可查（且学期还在）时的学期名；否则 null。
  final String? semesterName;

  bool get semesterKnown => semesterId != null && semesterName != null;

  /// 历史面板的一行文案：老批次不许伪装成当前学期的导入。
  String get semesterLabel => semesterKnown ? semesterName! : '（学期未知）';

  DateTime get importedAt => batch.importedAt;
}

/// 一次新鲜度读数的值类（不可变）。
class CourseFreshness {
  const CourseFreshness({
    this.at,
    this.kind = CourseFreshnessKind.none,
    this.fileName,
    this.imported = 0,
    this.updated = 0,
    this.skipped = 0,
    this.batches = const <ImportBatchEntry>[],
  });

  /// 展示用的时刻（UTC）；[CourseFreshnessKind.none] 时为 null。
  final DateTime? at;
  final CourseFreshnessKind kind;

  /// 仅 [CourseFreshnessKind.import] 有值。
  final String? fileName;
  final int imported;
  final int updated;
  final int skipped;

  /// 最近 10 次导入批次（全学期混排、新的在前），供「点这一行看历史」渲染。
  ///
  /// 每条带学期归属（M6-D §八）：老批次 `semesterId == null`，
  /// 历史面板按 [ImportBatchEntry.semesterLabel] 显示「（学期未知）」。
  /// 顶部那行的**导入时刻**不从这里取——那里用 `latestBatch(semesterId)`，
  /// 只认真正属于本学期批次。
  final List<ImportBatchEntry> batches;

  bool get isEmpty => at == null;
}

/// UTC 时刻 → `MM-dd HH:mm`（按本地时区，与 `due_format.dart` 同一口径）。
String courseStamp(DateTime at) {
  final DateTime local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
