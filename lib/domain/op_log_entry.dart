import 'timestamps.dart';

/// op-log 单条记录（F38：变更日志，用于审计与降级恢复）。
///
/// M1 只写不读（无上传）。字段级变更内容 `changes` 为 JSON 数组，
/// 每项形如 `{"field":"title","old":"a","new":"b"}`（create 时 old 为 null，
/// delete 时 new 为 null）。
class OpLogEntry {
  const OpLogEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.changesJson,
    required this.operatedTime,
    this.uploaded = false,
    this.uploadedTime,
  });

  final String id;

  /// 实体类型，取 [OpLogEntityType] 的 value（'task' / 'list' / 'subtask' /
  /// 'tag' / 'task_tag'）。
  final String entityType;
  final String entityId;

  /// 操作类型，取 [OpLogOperation] 的 value（'create' / 'update' / 'delete'）。
  final String operation;

  /// 字段级变更内容 JSON（见类注释格式约定）。
  final String changesJson;

  /// 操作发生时间（UTC 毫秒，来自本地时钟）。
  final DateTime operatedTime;

  /// 是否已上传（M1 恒为 false；M2 上传成功后置位）。
  final bool uploaded;
  final DateTime? uploadedTime;

  factory OpLogEntry.fromMap(Map<String, Object?> map) => OpLogEntry(
        id: map['id']! as String,
        entityType: map['entity_type']! as String,
        entityId: map['entity_id']! as String,
        operation: map['operation']! as String,
        changesJson: map['changes_json']! as String,
        operatedTime: msToDateTime(map['operated_time']! as int)!,
        uploaded: (map['uploaded'] ?? 0) == 1,
        uploadedTime: msToDateTime(map['uploaded_time'] as int?),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'changes_json': changesJson,
        'operated_time': dateTimeToMs(operatedTime),
        'uploaded': uploaded ? 1 : 0,
        'uploaded_time': dateTimeToMs(uploadedTime),
      };
}

/// op-log 的实体类型枚举（存字符串，op-log 是审计日志，可读性优先）。
///
/// 前五个是任务域；后四个是 M4a 课表域（`import_batches` 是本地簿记，
/// 不记 op-log、不参与同步，见 2026-10-10 定案 3）。
enum OpLogEntityType {
  task('task'),
  list('list'),
  subtask('subtask'),
  tag('tag'),
  taskTag('task_tag'),
  semester('semester'),
  timetable('timetable'),
  timeDetail('time_detail'),
  course('course');

  const OpLogEntityType(this.value);
  final String value;
}

/// op-log 的操作类型枚举。
enum OpLogOperation {
  create('create'),
  update('update'),
  delete('delete');

  const OpLogOperation(this.value);
  final String value;
}
