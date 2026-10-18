/// 同步后端的「哑存储」抽象接口。
///
/// 设计立场：云盘只当哑存储用，不依赖任何服务端语义（不建库、不解析内容）。
/// 接口形状来自方案设计 §5.2，已定稿；后续 WebDAV 等第二个实现必须对接同名方法。
library;

/// 远端对象摘要（[SyncBackend.list] 的返回项）。
class RemoteObject {
  const RemoteObject({
    required this.path,
    required this.size,
    this.etag,
    this.modifiedAt,
  });

  /// 相对 namespace 的对象路径，统一用 `/` 分隔。
  final String path;

  /// 内容派生的实体标签；本地实现为 sha256 十六进制前 16 位。
  final String? etag;

  /// 对象字节数。
  final int size;

  /// 最后修改时间（可能为 null，视后端能力而定）。
  final DateTime? modifiedAt;
}

/// 后端能力声明：同步引擎据此决定用哪些路径（如能否走条件写）。
class BackendCapabilities {
  const BackendCapabilities({
    required this.supportsConditionalWrite,
    required this.supportsList,
    required this.supportsRangeRead,
  });

  /// 是否支持 If-Match 条件写（CAS）。
  final bool supportsConditionalWrite;

  /// 是否支持列目录。
  final bool supportsList;

  /// 是否支持范围读（Range GET）。
  final bool supportsRangeRead;
}

/// 条件写失败（etag 不匹配或目标不存在），对应真实云盘的 HTTP 412。
class PreconditionFailedException implements Exception {
  const PreconditionFailedException({
    required this.path,
    this.expectedEtag,
    this.actualEtag,
  });

  /// 发生冲突的对象路径。
  final String path;

  /// 调用方期望的 etag（即 ifMatchEtag）。
  final String? expectedEtag;

  /// 服务端当前实际 etag；对象不存在时为 null。
  final String? actualEtag;

  @override
  String toString() =>
      'PreconditionFailedException(path: $path, expected: $expectedEtag, '
      'actual: $actualEtag)';
}

/// 读取/删除不存在的对象时抛出（不含条件写场景，那是 412）。
///
/// 选择自定义异常而非 dart:io 的 FileSystemException：FileSystemException
/// 必须携带 message/path/osError，语义偏「IO 出错」；「对象不存在」是同步
/// 流程里的正常分支（如对端已删），需要可被精确 catch。
class ObjectNotFoundException implements Exception {
  const ObjectNotFoundException(this.path);

  /// 不存在的对象路径。
  final String path;

  @override
  String toString() => 'ObjectNotFoundException(path: $path)';
}

/// 配置层面失败：地址或凭据根本不可用，重试无意义，必须改配置。
///
/// 典型场景：baseUrl 指向的根目录不存在（且服务端不允许 MKCOL 建它），
/// 或凭据错误。与 [PreconditionFailedException] 的区别：那是数据层冲突
/// （可收敛重试），本异常是环境层故障（fail-fast，文案直接给用户看）。
class SyncConfigException implements Exception {
  const SyncConfigException({
    required this.baseUrl,
    required this.statusCode,
    required this.hint,
  });

  /// 出问题的完整 baseUrl 原文（用户据此核对地址）。
  final String baseUrl;

  /// 触发失败的 HTTP 状态码（无网络语义时可为 0，如本地不可写）。
  final int statusCode;

  /// 给用户的修复提示。
  final String hint;

  @override
  String toString() =>
      'SyncConfigException：同步地址配置不可用（HTTP $statusCode）\n'
      'baseUrl: $baseUrl\n'
      '$hint';
}

/// 哑存储后端：云盘只当哑存储，不依赖任何服务端语义。
abstract class SyncBackend {
  /// 同步开始前的就绪检查：确认目标根目录存在（不存在则创建）。
  ///
  /// 抛 [SyncConfigException] 表示地址/凭据配错，引擎应在做任何数据
  /// 请求之前 fail-fast。默认空实现：本地文件夹后端的根在构造期就
  /// 已确定可写，无需检查。
  Future<void> ensureReady() async {}

  /// 列出 namespace 下的全部对象。
  Future<List<RemoteObject>> list(String namespace);

  /// 读取对象内容与 etag；对象不存在抛 [ObjectNotFoundException]。
  Future<({List<int> bytes, String? etag})> get(String path);

  /// 写入对象；传了 [ifMatchEtag] 时做条件写（CAS），不匹配抛
  /// [PreconditionFailedException]。返回新对象的 etag。
  Future<String?> put(String path, List<int> bytes, {String? ifMatchEtag});

  /// 删除对象；传了 [ifMatchEtag] 时做条件删，不匹配抛
  /// [PreconditionFailedException]。
  Future<void> delete(String path, {String? ifMatchEtag});

  /// 能力声明。
  Future<BackendCapabilities> capabilities();
}
