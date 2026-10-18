/// 时间戳换算工具（领域层共用）。
///
/// 存储约定（需求规格书 §四）：所有时间戳以 UTC 毫秒整数落库，
/// 展示时按本地时区换算；同步边界做时区归一。
/// 领域模型字段用 `DateTime`（UTC），DAO/JSON 映射层负责与毫秒整数互转。
library;

/// [DateTime] → UTC 毫秒时间戳；null 透传 null（可空列）。
int? dateTimeToMs(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;

/// UTC 毫秒时间戳 → [DateTime]（UTC）；null 透传 null。
DateTime? msToDateTime(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
