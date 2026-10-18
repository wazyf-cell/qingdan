/// 意图推导器测试的共用测试数据构造（非 `_test` 文件，flutter test 不直接执行）。
///
/// 测试数据统一走「SQLite 行 Map（snake_case）+ base JSON 串」的真实形状：
/// `resolveFromState` 的输入在生产环境里就是 DAO 行 + `sync_state.base_json`，
/// 测试不放大简化。
library;

import 'dart:convert';

import 'package:qingdan/domain/op_log_entry.dart';

/// 一条任务的 SQLite 行 Map（与 `tasks` 表真实列名一致，毫秒时间戳）。
Map<String, Object?> taskRow({
  required String id,
  String title = '任务',
  int priority = 0,
  String? listId = 'list-1',
  int completed = 0,
  int? completedTime,
  int modifiedTime = 1000,
  int sortOrder = 0,
  int deleted = 0,
  int? deletedTime,
  String? lastSyncedJson,
}) =>
    <String, Object?>{
      'id': id,
      'title': title,
      'note': '',
      'priority': priority,
      'start_date': null,
      'end_date': null,
      'due_date': null,
      'list_id': listId,
      'completed': completed,
      'completed_time': completedTime,
      'created_time': 900,
      'modified_time': modifiedTime,
      'sort_order': sortOrder,
      'deleted': deleted,
      'deleted_time': deletedTime,
      'last_synced_json': lastSyncedJson,
    };

/// 一份 base JSON 的 camelCase 同步 JSON 形状（与实体 `toJson()` 一致）。
const Map<String, Object?> kTaskJson = <String, Object?>{
  'id': 't1',
  'title': '任务',
  'note': '',
  'priority': 0,
  'startDate': null,
  'endDate': null,
  'dueDate': null,
  'listId': 'list-1',
  'completed': false,
  'completedTime': null,
  'createdTime': 900,
  'modifiedTime': 1000,
  'sortOrder': 0,
  'deleted': false,
  'deletedTime': null,
};

/// base JSON 串；[overrides] 覆盖个别字段（如 `{'deleted': 1}`）。
String baseJson([Map<String, Object?>? overrides]) =>
    jsonEncode(<String, Object?>{...kTaskJson, ...?overrides});

/// 一条 op-log 流水（entityId 固定 'e1'）。
OpLogEntry opLog(String id, String op, {String entityType = 'list'}) =>
    OpLogEntry(
      id: id,
      entityType: entityType,
      entityId: 'e1',
      operation: op,
      changesJson: '[]',
      operatedTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
