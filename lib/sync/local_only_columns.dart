/// 设备本地列剔除表（同步侧唯一真源）。
///
/// 单独成文件是因为 `sync_serializer.dart` 与 `intent_resolver.dart` 互相 import
/// 会绕成环，而两侧都要用这张表。
library;

/// 设备本地列（snake_case）：**上云时剔除**，与 `task_tags` 不同步同一待遇。
///
/// - `import_batch_id`：批次表本身不同步，这列上了云也没人能把行落库（必 787）；
/// - `is_active`（M6-D）：「哪个学期是当前学期」是**这台设备自己的视图**——
///   手机上翻一眼上学期，Windows 跟着变，等于两台设备互抢当前学期。
/// 只有 semester 表有 `is_active`、只有 course 表有 `import_batch_id`，
/// 所以按列名全局剔除与「按实体类型剔除」在这里等价，不必把类型参数穿透四个调用点。
const Set<String> kLocalOnlyRowColumns = <String>{'import_batch_id', 'is_active'};

/// [kLocalOnlyRowColumns] 的 camelCase 镜像（同步 JSON 用的键名）。
/// **两侧必须成对**：只剔一侧会让对端插入时缺列或多列（`import_batch_id` 踩过）。
const Set<String> kLocalOnlyJsonKeys = <String>{'importBatchId', 'isActive'};

