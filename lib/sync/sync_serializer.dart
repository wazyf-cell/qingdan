/// 同步序列化层：实体表行 ↔ 云端 JSON、云端路径生成（SyncEngine 的 IO 映射层）。
///
/// 从 sync_engine.dart 拆出的职责：引擎只做流程编排，本文件集中「JSON 长什么样、
/// 放在云端哪个路径」这两个纯映射规则，便于独立审查与测试。
library;

import 'dart:convert';

import 'intent_resolver.dart' show SyncIntent;

// 剔除表单独成文件：`intent_resolver` 与本文件互相 import 会绕成环。
export 'local_only_columns.dart';

/// 实体类型 → 业务表名的静态映射（读库用）。
const Map<String, String> kEntityTable = <String, String>{
  'semester': 'semesters',
  'timetable': 'timetables',
  'time_detail': 'time_details',
  'course': 'courses',
  'task': 'tasks',
  'list': 'lists',
  'subtask': 'subtasks',
  'tag': 'tags',
};

/// 引擎按此顺序处理各实体类型：父实体先落库，外键（如 subtask.task_id）
/// 才有可引用的行。
///
/// **顺序由外键依赖图决定，不能随意调整**（2026-10-09 S6 真机实测修复）：
/// - `tasks.list_id` → `lists(id)`：**清单必须先于任务**
/// - `subtasks.task_id` → `tasks(id)`：任务先于子任务
/// - `task_tags.task_id/tag_id` → `tasks(id)`/`tags(id)`：标签在两者之后
///
/// 原顺序是 `['task', 'list', ...]` —— 任务排在清单之前，**与这行注释
/// 自相矛盾**。离线测试全程没抓到，因为夹具里的任务 `list_id` 恒为
/// `null`（外键为 NULL 时不校验），**只要有归属清单的任务跨设备同步就必炸**
/// `SqliteException(787): FOREIGN KEY constraint failed`。真机 S6 首次
/// 同步即命中。
///
/// **M4a S6 加课表四类，顺序同理**：`timetables.semester_id` 与
/// `courses.semester_id` → `semesters(id)`，`time_details.timetable_id` →
/// `timetables(id)`，所以 `semester → timetable → time_detail → course`
/// 必须整体排在 `list` 之前。`import_batches` 与 `task_tags` 一样**不同步**
/// （2026-10-10 定案 3：本地簿记），因此 `courses.import_batch_id` 在序列化
/// 两侧都要剔除，否则接收端落库必 787。
const List<String> kEntityTypes = <String>[
  'semester',
  'timetable',
  'time_detail',
  'course',
  'list',
  'task',
  'subtask',
  'tag',
];

/// 云端对象路径：`entities/<类型>/<id>.json`。
///
/// **扁平布局（2026-09-30 真机实测后改）**：原设计是
/// `entities/<类型>/<hash 前缀>/<id>.json`（方案设计 §5.2），hash 前缀用来
/// 防止单目录对象数过多。**真机实测推翻了它**：
///
/// 坚果云**不支持 `Depth: infinity`** —— 实测 `Depth: 1` 与 `Depth: infinity`
/// 返回完全相同的两条 href（目录自身 + 直接子目录），**不递归**。而原布局是
/// 三层，实体文件在第三层，**`list()` 永远看不到它们**，恒定返回空列表。
///
/// 后果是静默的：引擎会认为「云端没有实体」，把本地全部当新增上传，
/// 双端永远无法收敛。离线测试测不出来——`LocalFolderBackend` 用
/// `Directory.list(recursive: true)`，真递归，与布局无关。
///
/// 改用扁平布局后，`list()` 用 `Depth: 1` 一次即可列全（实测：单目录 300 个
/// 文件一次返回 301 条，219 KB，无截断、无分页标记）。容量风险仍在官方
/// 单次 750 条上限处，但自用规模远低于此；真的超限时再按 hash 分桶。
String entityRemotePath(String entityType, String entityId) =>
    'entities/$entityType/$entityId.json';

/// 墓碑路径：`tombstones/<id>.json`。内容只需类型与时间，id 已在文件名里。
///
/// 墓碑一直是扁平的——它才是「对」的写法，实体那侧现已对齐。
String tombstoneRemotePath(String entityId) => 'tombstones/$entityId.json';

/// 意图 payload → 云端 JSON 字节（UTF-8）。键排序后序列化：同一份数据
/// 无论由哪台设备、哪次运行产生，字节序列都一致 → etag 只由内容决定，
/// 「本地内容没变 → 无需重传」的幂等判断才可靠。
List<int> encodeEntityJson(Map<String, Object?> payload) {
  final List<String> keys = payload.keys.toList()..sort();
  final String body = jsonEncode(<String, Object?>{
    for (final String k in keys) k: payload[k],
  });
  return utf8.encode(body);
}

/// 云端 JSON 字节 → Map。损坏的 JSON 抛 FormatException 由引擎归入 errors。
Map<String, Object?> decodeEntityJson(List<int> bytes) =>
    (jsonDecode(utf8.decode(bytes)) as Map<Object?, Object?>)
        .cast<String, Object?>();

/// 上传前补齐运行时元数据（intent_resolver 注释里约定的：纯函数层拿不到
/// rev / deviceId，由引擎盖章）。写入 payload **副本**，不改传入对象。
Map<String, Object?> stampSyncMeta(
  SyncIntent intent, {
  required int rev,
  required String deviceId,
}) {
  final Map<String, Object?> payload = Map<String, Object?>.of(intent.payload!);
  payload['id'] = intent.entityId;
  payload['rev'] = rev;
  payload['deviceId'] = deviceId;
  return payload;
}

/// 墓碑 JSON：只记类型与删除时间，id 在路径里。不记 rev/deviceId——墓碑是
/// 「该实体已不存在」的最终声明，不需要参与合并，谁先写上谁生效。
List<int> encodeTombstoneJson({
  required String entityType,
  required int deletedAtMs,
}) {
  final String body = jsonEncode(<String, Object?>{
    'type': entityType,
    'deletedAt': deletedAtMs,
  });
  return utf8.encode(body);
}

/// 云端 JSON 字节 → Map（墓碑用，与实体同构）。
Map<String, Object?> decodeTombstoneJson(List<int> bytes) =>
    decodeEntityJson(bytes);
