import 'task_priority.dart';
import 'timestamps.dart';

/// 任务（需求规格书 F2；同步基线字段见 `lastSyncedJson`）。
///
/// 纯数据类，无 IO。字段级 LWW 与三路合并（方案设计 §5.4）依赖两点：
/// - [modifiedTime]（UTC 毫秒）：任一字段变更即刷新，是字段冲突时的决胜依据；
/// - [lastSyncedJson]：上次同步成功时的实体快照 JSON（可空），作为三路合并的
///   `base`（TickTick TaskSyncCollector 同款做法）。null 表示「从未同步过」，
///   合并时视为 base == current（本地权威）。
class Task {
  const Task({
    required this.id,
    required this.title,
    this.note = '',
    this.priority = TaskPriority.none,
    this.startDate,
    this.endDate,
    this.dueDate,
    this.listId,
    this.completed = false,
    this.completedTime,
    this.createdTime,
    this.modifiedTime,
    this.sortOrder = 0,
    this.deleted = false,
    this.deletedTime,
    this.lastSyncedJson,
    this.subtasks = const <Subtask>[],
  });

  final String id;
  final String title;

  /// 备注（Markdown，F2）。
  final String note;

  final TaskPriority priority;

  /// 开始 / 结束时间（时间段任务，F26）。
  final DateTime? startDate;
  final DateTime? endDate;

  /// 到期时间（智能清单「今天 / 最近 7 天」的判定依据，F8）。
  final DateTime? dueDate;

  /// 所属清单 id；null = 收集箱（任务随清单删除时移入，见迁移 v2 外键语义）。
  final String? listId;

  final bool completed;

  /// 完成时间；取消完成时清空（F3 验收）。
  final DateTime? completedTime;
  final DateTime? createdTime;
  final DateTime? modifiedTime;

  /// 手动排序序号（F9）。
  final int sortOrder;

  /// 回收站语义（F4）：true = 已移入回收站。
  final bool deleted;
  final DateTime? deletedTime;

  /// 上次同步成功时的实体快照 JSON（三路合并 base，方案设计 §5.4）。
  final String? lastSyncedJson;

  /// 子任务（单层，F5）。DAO 默认不填，需单独查询（`subtasks` 表）。
  final List<Subtask> subtasks;

  Task copyWith({
    String? title,
    String? note,
    TaskPriority? priority,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? dueDate,
    String? listId,
    bool? completed,
    DateTime? completedTime,
    DateTime? createdTime,
    DateTime? modifiedTime,
    int? sortOrder,
    bool? deleted,
    DateTime? deletedTime,
    String? lastSyncedJson,
    List<Subtask>? subtasks,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        priority: priority ?? this.priority,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        dueDate: dueDate ?? this.dueDate,
        listId: listId ?? this.listId,
        completed: completed ?? this.completed,
        completedTime: completedTime ?? this.completedTime,
        createdTime: createdTime ?? this.createdTime,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        sortOrder: sortOrder ?? this.sortOrder,
        deleted: deleted ?? this.deleted,
        deletedTime: deletedTime ?? this.deletedTime,
        lastSyncedJson: lastSyncedJson ?? this.lastSyncedJson,
        subtasks: subtasks ?? this.subtasks,
      );

  // ---- SQLite 行映射（毫秒整数时间戳） ----

  factory Task.fromMap(Map<String, Object?> map) => Task(
        id: map['id']! as String,
        title: map['title']! as String,
        note: (map['note'] ?? '') as String,
        priority: TaskPriority.fromValue((map['priority'] ?? 0) as int),
        startDate: msToDateTime(map['start_date'] as int?),
        endDate: msToDateTime(map['end_date'] as int?),
        dueDate: msToDateTime(map['due_date'] as int?),
        listId: map['list_id'] as String?,
        completed: (map['completed'] ?? 0) == 1,
        completedTime: msToDateTime(map['completed_time'] as int?),
        createdTime: msToDateTime(map['created_time'] as int?),
        modifiedTime: msToDateTime(map['modified_time'] as int?),
        sortOrder: (map['sort_order'] ?? 0) as int,
        deleted: (map['deleted'] ?? 0) == 1,
        deletedTime: msToDateTime(map['deleted_time'] as int?),
        lastSyncedJson: map['last_synced_json'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'note': note,
        'priority': priority.value,
        'start_date': dateTimeToMs(startDate),
        'end_date': dateTimeToMs(endDate),
        'due_date': dateTimeToMs(dueDate),
        'list_id': listId,
        'completed': completed ? 1 : 0,
        'completed_time': dateTimeToMs(completedTime),
        'created_time': dateTimeToMs(createdTime),
        'modified_time': dateTimeToMs(modifiedTime),
        'sort_order': sortOrder,
        'deleted': deleted ? 1 : 0,
        'deleted_time': dateTimeToMs(deletedTime),
        'last_synced_json': lastSyncedJson,
      };

  // ---- JSON 映射（lastSyncedJson 快照与未来云盘分片） ----

  factory Task.fromJson(Map<String, Object?> json) => Task(
        id: json['id']! as String,
        title: json['title']! as String,
        note: (json['note'] ?? '') as String,
        priority: TaskPriority.fromValue((json['priority'] ?? 0) as int),
        startDate: msToDateTime(json['startDate'] as int?),
        endDate: msToDateTime(json['endDate'] as int?),
        dueDate: msToDateTime(json['dueDate'] as int?),
        listId: json['listId'] as String?,
        completed: (json['completed'] ?? false) as bool,
        completedTime: msToDateTime(json['completedTime'] as int?),
        createdTime: msToDateTime(json['createdTime'] as int?),
        modifiedTime: msToDateTime(json['modifiedTime'] as int?),
        sortOrder: (json['sortOrder'] ?? 0) as int,
        deleted: (json['deleted'] ?? false) as bool,
        deletedTime: msToDateTime(json['deletedTime'] as int?),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'note': note,
        'priority': priority.value,
        'startDate': dateTimeToMs(startDate),
        'endDate': dateTimeToMs(endDate),
        'dueDate': dateTimeToMs(dueDate),
        'listId': listId,
        'completed': completed,
        'completedTime': dateTimeToMs(completedTime),
        'createdTime': dateTimeToMs(createdTime),
        'modifiedTime': dateTimeToMs(modifiedTime),
        'sortOrder': sortOrder,
        'deleted': deleted,
        'deletedTime': dateTimeToMs(deletedTime),
      };
}

/// 子任务（检查事项，单层，F5）。
class Subtask {
  const Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    this.completed = false,
    this.sortOrder = 0,
    this.modifiedTime,
    this.lastSyncedJson,
  });

  final String id;

  /// 父任务 id（外键 ON DELETE CASCADE：父任务彻底删除时子任务随之删除）。
  final String taskId;
  final String title;

  /// 勾选状态（父任务详情显示「1/3」进度，F5 验收）。
  final bool completed;
  final int sortOrder;
  final DateTime? modifiedTime;
  final String? lastSyncedJson;

  Subtask copyWith({
    String? title,
    bool? completed,
    int? sortOrder,
    DateTime? modifiedTime,
    String? lastSyncedJson,
  }) =>
      Subtask(
        id: id,
        taskId: taskId,
        title: title ?? this.title,
        completed: completed ?? this.completed,
        sortOrder: sortOrder ?? this.sortOrder,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        lastSyncedJson: lastSyncedJson ?? this.lastSyncedJson,
      );

  factory Subtask.fromMap(Map<String, Object?> map) => Subtask(
        id: map['id']! as String,
        taskId: map['task_id']! as String,
        title: map['title']! as String,
        completed: (map['completed'] ?? 0) == 1,
        sortOrder: (map['sort_order'] ?? 0) as int,
        modifiedTime: msToDateTime(map['modified_time'] as int?),
        lastSyncedJson: map['last_synced_json'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'task_id': taskId,
        'title': title,
        'completed': completed ? 1 : 0,
        'sort_order': sortOrder,
        'modified_time': dateTimeToMs(modifiedTime),
        'last_synced_json': lastSyncedJson,
      };

  factory Subtask.fromJson(Map<String, Object?> json) => Subtask(
        id: json['id']! as String,
        taskId: json['taskId']! as String,
        title: json['title']! as String,
        completed: (json['completed'] ?? false) as bool,
        sortOrder: (json['sortOrder'] ?? 0) as int,
        modifiedTime: msToDateTime(json['modifiedTime'] as int?),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'taskId': taskId,
        'title': title,
        'completed': completed,
        'sortOrder': sortOrder,
        'modifiedTime': dateTimeToMs(modifiedTime),
      };
}
