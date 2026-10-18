import 'course.dart';

/// 课表「上次更新 / 导入时间」的取值（M6-A A8）。
///
/// 为什么不落库：它是 `import_batches` 最近一次 + 本学期课程 `MAX(modified_time)`
/// 两个只读查询的派生结果，存下来还得管失效，不如每次 `load()` 现取。
enum CourseFreshnessKind { none, import, edit }

/// 一次新鲜度读数的值类（不可变）。
class CourseFreshness {
  const CourseFreshness({
    this.at,
    this.kind = CourseFreshnessKind.none,
    this.fileName,
    this.imported = 0,
    this.updated = 0,
    this.skipped = 0,
    this.batches = const <ImportBatch>[],
  });

  /// 展示用的时刻（UTC）；[CourseFreshnessKind.none] 时为 null。
  final DateTime? at;
  final CourseFreshnessKind kind;

  /// 仅 [CourseFreshnessKind.import] 有值。
  final String? fileName;
  final int imported;
  final int updated;
  final int skipped;

  /// 最近 10 次导入批次，供「点这一行看历史」渲染。
  ///
  /// **局限**：`import_batches` 没有 `semester_id` 列（要等 M6-D 迁移 v6 才补），
  /// 所以这份是**全局**的、不区分学期；A 批不动库结构，界面用 tooltip 如实写明。
  final List<ImportBatch> batches;

  bool get isEmpty => at == null;
}

/// UTC 时刻 → `MM-dd HH:mm`（按本地时区，与 `due_format.dart` 同一口径）。
String courseStamp(DateTime at) {
  final DateTime local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
