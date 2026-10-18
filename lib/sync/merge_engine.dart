/// 三路合并引擎（方案设计 §5.4：A3 = op-log + 字段级 LWW + 三路合并）。
///
/// 纯函数、零 IO：不 import sqflite、不碰数据库、不做时区转换——时间字段存储
/// 一律 UTC，转换发生在同步边界，不在合并内。
///
/// 逐字段判定（四分支）：
/// - `remote == current` → 双方一致，取该值；
/// - `base == current`   → 本地未改，取远端；
/// - `base == remote`    → 远端未改，取本地；
/// - 否则 → 字段冲突，取 `modifiedTime` 较新的一方（字段级 LWW）。
///   `modifiedTime` 是实体级时间戳（任一字段变更即刷新，见 `lib/domain/task.dart`
///   的 `Task.modifiedTime` 注释），所以 LWW 按实体级比较、对每个冲突字段统一适用。
///
/// 特殊字段类型：
/// - 集合型（标签）：并集。与「并集 − 双方都删的」等价——删除以「元素缺失」
///   表示，双方都删的元素不在任何一侧（TickTick `mergeTags` 规则）。
/// - 累加型（番茄次数、打卡次数）：`remote + current − base`（TickTick
///   `mergePomodoroSummaries` 同款加法合并，不能用 LWW，否则两端各 +1 会变 +1）。
///   ⚠ 当前数据模型没有累加型字段，本规则为 M5 番茄钟/习惯预留，暂无调用方——
///   先以测试锁定行为，将来补字段时不用重推正确性。
///
/// 移植来源（只移植算法与规则，未照抄实现；Java → Dart 的空安全/集合语义已重写）：
/// `F:\Code\APK-MCP\9-Ticktick\Gradle\app\src\main\java\com\ticktick\task\sync\utils\TaskMergeUtils.java`
/// - `getStringVersion`（L278-286）：四分支判定；`preferUseRevised` 由
///   `revised.modifiedTime vs delta.modifiedTime` 决定——即字段级 LWW；
/// - `mergeTask`（L817-897）：逐字段合并骨架；
/// - `mergePomodoroSummaries`（L449-514）：累加型 `delta + revised − original`。
/// 未移植：`getRevisedTextByDiff` 的文本行级三方 diff 合并——本项目 title/note
/// 按整字段 LWW 决胜，粒度更粗但结果可预期，且避免移植 diff 依赖。
///
/// 两条硬约束（违反会死循环上传）：
/// 1. `rev` / `deviceId`（连同 `id` / `lastSyncedJson`）绝不参与合并判定——
///   两端 `rev` 永不相等，参与判定会让每次同步都判「有变更」→ 每次都上传；
/// 2. `sortOrder` 不参与（新设计中顺序走独立的 order 实体，方案设计 §5.3）。
/// 结果分类也只比较业务字段，元字段差异不影响结论（第二道闸）。
///
/// 与 intent_resolver 的共享边界待 S6 串联时统一（本文件不依赖 lib/sync 其他文件）。
library;

/// 合并结果类型（决定调用方后续动作）。
enum MergeOutcomeType {
  /// 业务字段上本地与远端已一致：无需落库也无需上传。
  /// `rev`/`deviceId` 等元字段变化不影响本判定——这是「死循环上传」的防线。
  unchanged,

  /// 远端有更新、本地无变更：本地直接采用远端状态，无需上传。
  takeRemote,

  /// 本地有更新（含 base == null 的本地权威路径）：以上传本地状态收尾。
  takeLocal,

  /// 逐字段合并产生了新状态：先落库再上传。
  merged,
}

/// 合并结果。
class MergeResult {
  const MergeResult({
    required this.type,
    required this.merged,
    required this.conflictedFields,
  });

  final MergeOutcomeType type;

  /// 合并后的完整实体 JSON。忽略字段一律取本地值（`rev`/`deviceId` 由调用方
  /// 在上传前盖章递增）；本地缺的忽略字段（如远端新引入的元字段）补远端值。
  final Map<String, Object?> merged;

  /// 发生真冲突、靠 modifiedTime LWW 决胜的业务字段（调试/日志用）。
  final List<String> conflictedFields;
}

/// 默认不参与合并判定的字段（可用 [mergeEntity] 的 `ignoredFields` 追加）。
/// - `rev` / `deviceId`：两端永不相等，参与判定 ⇒ 每次同步都上传 ⇒ 死循环；
/// - `sortOrder` / 旧列名 `sort_order`：顺序走独立 order 实体（§5.3），不是任务字段；
/// - `lastSyncedJson`：同步基线容器本身，不是业务字段。
const Set<String> kDefaultIgnoredFields = <String>{
  'id',
  'rev',
  'deviceId',
  'sortOrder',
  'sort_order',
  'lastSyncedJson',
};

/// LWW 决胜时间戳字段：实体级 modifiedTime（UTC 毫秒，见 `Task.toJson`）。
const String kModifiedTimeField = 'modifiedTime';

/// 三路合并。
///
/// [base] 为 null（从未同步过，M2 上线时唯一真实路径）时按「本地权威」处理：
/// 业务字段上只要双方不一致就取本地。实现上等价于把 base 视作 remote——这使
/// 「base == remote → 取本地」恒成立。注意不能按字面把 base 视作 current：那会让
/// 「base == current → 取远端」恒成立，首次同步变成用远端覆盖本地，方向恰好相反。
///
/// [setFields] 集合型字段名；[additiveFields] 累加型字段名；[ignoredFields] 在
/// [kDefaultIgnoredFields] 之上追加的不参与判定字段。
MergeResult mergeEntity({
  required Map<String, Object?> current,
  required Map<String, Object?> remote,
  required Map<String, Object?>? base,
  Set<String>? setFields,
  Set<String>? additiveFields,
  Set<String>? ignoredFields,
}) {
  final Set<String> ignore = <String>{
    ...kDefaultIgnoredFields,
    ...?ignoredFields,
  };
  // base == null → base := remote（等价实现「本地权威」，见函数注释）。
  final Map<String, Object?> effBase = base ?? remote;
  // LWW 决胜只看两端的实体级 modifiedTime，整个合并过程取一次。
  final bool remoteNewer = _remoteNewer(current, remote);

  final Set<String> keys = <String>{
    ...current.keys,
    ...remote.keys,
    ...effBase.keys,
  }..removeAll(ignore);

  final Map<String, Object?> merged = <String, Object?>{};
  final List<String> conflicted = <String>[];
  for (final String key in keys) {
    final Object? value = _mergeField(
      key: key,
      b: _get(effBase, key),
      c: _get(current, key),
      r: _get(remote, key),
      current: current,
      remote: remote,
      remoteNewer: remoteNewer,
      setFields: setFields,
      additiveFields: additiveFields,
      conflicted: conflicted,
    );
    if (!identical(value, _absent)) merged[key] = value;
  }
  // 元字段不参与判定，输出一律取本地值。
  for (final String key in ignore) {
    if (current.containsKey(key)) {
      merged[key] = current[key];
    } else if (remote.containsKey(key)) {
      merged[key] = remote[key];
    }
  }

  // 分类只比较业务字段（keys），元字段差异不得影响结论。
  final bool sameAsCurrent = _businessEquals(merged, current, keys);
  final bool sameAsRemote = _businessEquals(merged, remote, keys);
  final MergeOutcomeType type;
  if (sameAsCurrent && sameAsRemote) {
    type = MergeOutcomeType.unchanged;
  } else if (sameAsRemote) {
    type = MergeOutcomeType.takeRemote;
  } else if (sameAsCurrent) {
    type = MergeOutcomeType.takeLocal;
  } else {
    type = MergeOutcomeType.merged;
  }
  return MergeResult(
    type: type,
    merged: merged,
    conflictedFields: conflicted,
  );
}

/// 「键缺失」与 null 是两种状态：null 是显式值，缺失是键不存在。
class _Absent {
  const _Absent();
}

const Object _absent = _Absent();

/// 累加型字段遇到非数值时的回退标记：交回普通四分支/LWW 判定。
class _NotAddable {
  const _NotAddable();
}

const Object _notAddable = _NotAddable();

Object? _get(Map<String, Object?> map, String key) =>
    map.containsKey(key) ? map[key] : _absent;

bool _eq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (identical(a, _absent) || identical(b, _absent)) return false;
  return _deepEquals(a, b);
}

/// JSON 值的深比较（Map/List 逐元素，标量用 ==）。
bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final Object? k in a.keys) {
      if (!b.containsKey(k) || !_deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// 单字段合并。集合/累加分支必须排在「双方一致」之前：两端同时 +1 后
/// current == remote，若先命中一致分支就退化了 LWW，加法合并失效。
Object? _mergeField({
  required String key,
  required Object? b,
  required Object? c,
  required Object? r,
  required Map<String, Object?> current,
  required Map<String, Object?> remote,
  required bool remoteNewer,
  required Set<String>? setFields,
  required Set<String>? additiveFields,
  required List<String> conflicted,
}) {
  if (setFields != null && setFields.contains(key)) return _unionLists(c, r);
  if (additiveFields != null && additiveFields.contains(key)) {
    final Object? sum = _tryAdditive(b, c, r);
    if (!identical(sum, _notAddable)) return sum;
  }
  if (_eq(c, r)) return c; // 双方一致
  if (_eq(b, c)) return r; // 本地未改 → 取远端
  if (_eq(b, r)) return c; // 远端未改 → 取本地
  // modifiedTime 是 LWW 决胜时间戳本身，两端实体级时间几乎必不相等——若计入
  // conflictedFields 会让每次真冲突都多报一条噪音，故它参与值合并但不作为
  // 「冲突内容字段」上报。
  if (key != kModifiedTimeField) conflicted.add(key);
  return remoteNewer ? r : c;
}

/// 集合并集：保留本地顺序、追加远端新增（去重按深比较）。
/// 「并集 − 双方都删的」与纯并集等价：删除以缺失表示，双方都删的元素
/// 不在任何一侧。
List<Object?> _unionLists(Object? c, Object? r) {
  final List<Object?> out =
      c is List<Object?> ? List<Object?>.of(c) : <Object?>[];
  if (r is List<Object?>) {
    for (final Object? e in r) {
      if (!out.any((Object? x) => _deepEquals(x, e))) out.add(e);
    }
  }
  return out;
}

/// 累加型：`remote + current − base`，缺席/null 按 0 计。三方皆空则维持现状；
/// 任一方是「有值但非数值」时回退 [Object] 普通判定（不强行相加）。
Object? _tryAdditive(Object? b, Object? c, Object? r) {
  for (final Object? v in <Object?>[b, c, r]) {
    if (!identical(v, _absent) && v != null && v is! num) return _notAddable;
  }
  final bool emptyB = identical(b, _absent) || b == null;
  final bool emptyC = identical(c, _absent) || c == null;
  final bool emptyR = identical(r, _absent) || r == null;
  if (emptyB && emptyC && emptyR) return c;
  return (_asInt(c) ?? 0) + (_asInt(r) ?? 0) - (_asInt(b) ?? 0);
}

int? _asInt(Object? v) => (identical(v, _absent) || v == null) ? null : (v as num).toInt();

/// LWW 决胜：远端 modifiedTime 更新 → 远端胜；拿不出时间或相等 → 本地胜
/// （与 base==null 的本地权威同向，保守少覆盖）。
bool _remoteNewer(Map<String, Object?> current, Map<String, Object?> remote) {
  final int? local = _asInt(current[kModifiedTimeField]);
  final int? other = _asInt(remote[kModifiedTimeField]);
  if (other == null) return false;
  if (local == null) return true;
  return other > local;
}

/// 只比较业务键（[keys]）上的值，用于结果分类。
bool _businessEquals(
  Map<String, Object?> merged,
  Map<String, Object?> side,
  Set<String> keys,
) {
  for (final String key in keys) {
    if (!_eq(_get(merged, key), _get(side, key))) return false;
  }
  return true;
}
