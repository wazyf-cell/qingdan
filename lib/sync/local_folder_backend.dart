/// 本地文件夹实现的 [SyncBackend]：把 root 目录当哑存储。
///
/// 设计立场：它的意义在于**比真实云盘更严格地模拟 CAS 语义**——
/// 真实坚果云在 If-Match 不匹配时返回 412 拒绝（已实测），所以本地实现
/// 绝不放水：etag 对不上就抛 [PreconditionFailedException]，不许静默覆盖。
/// 本地后端一旦宽松，双端测试会绿，接上真云盘才炸，测试就失去意义。
library;

import 'dart:io';
import 'dart:math';

import 'sync_backend.dart';

/// etag 派生：sha256(bytes) 十六进制前 16 位。
///
/// 为什么不用文件时间戳：内容相同则 etag 必须相同，「本地内容没变 →
/// 远端 etag 没变 → 无需重传」才成立；时间戳会让每次写都产生新 etag，
/// 同步永远认为有变化（死循环上传）。
///
/// 为什么不用 package:crypto：它是 pubspec.lock 里的传递依赖但未直接声明，
/// 项目规矩是不改 pubspec、不引入新依赖（depend_on_referenced_packages
/// lint 也会拦截），所以内置一个纯 Dart 的 SHA-256（仅用于小对象，够用）。
const List<int> _sha256K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, //
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, //
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, //
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, //
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, //
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, //
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, //
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, //
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, //
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, //
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, //
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, //
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, //
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, //
];

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

/// 返回 sha256(bytes) 的十六进制前 16 位（即内容派生 etag）。
String sha256Etag(List<int> data) {
  final int bitLen = data.length * 8;
  final bytes = List<int>.from(data)..add(0x80);
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  for (int i = 7; i >= 0; i--) {
    bytes.add((bitLen >> (8 * i)) & 0xFF);
  }
  var h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19, //
  ];
  for (int off = 0; off < bytes.length; off += 64) {
    final w = List<int>.filled(64, 0);
    for (int i = 0; i < 16; i++) {
      final b = off + 4 * i;
      w[i] =
          (bytes[b] << 24) | (bytes[b + 1] << 16) | (bytes[b + 2] << 8) |
          bytes[b + 3];
    }
    for (int i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final t1 = (hh + s1 + ch + _sha256K[i] + w[i]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xFFFFFFFF;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xFFFFFFFF;
    }
    h[0] = (h[0] + a) & 0xFFFFFFFF;
    h[1] = (h[1] + b) & 0xFFFFFFFF;
    h[2] = (h[2] + c) & 0xFFFFFFFF;
    h[3] = (h[3] + d) & 0xFFFFFFFF;
    h[4] = (h[4] + e) & 0xFFFFFFFF;
    h[5] = (h[5] + f) & 0xFFFFFFFF;
    h[6] = (h[6] + g) & 0xFFFFFFFF;
    h[7] = (h[7] + hh) & 0xFFFFFFFF;
  }
  final hex = h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
  return hex.substring(0, 16);
}

/// 本地文件夹后端。所有对象路径都是相对 [root] 的 `/` 分隔相对路径；
/// `..` 逃逸直接抛 ArgumentError，绝不静默处理。
///
/// 为什么没有 namespacePrefix 构造参数：`SyncBackend` 的接口形状（方案设计
/// §5.2）已经把命名空间表达成 [list] 的方法参数，对象路径 [get]/[put]/[delete]
/// 也都是完整相对路径——要分租户直接在 path 里带上目录名即可（如
/// `tenant1/data/a.json`）。若再加一层构造期前缀，同一个概念就有了两个来源，
/// 且会引出「前缀的 `..` 算不算逃逸」这个没有正确答案的问题（前缀先拼进来时
/// `tenant1/../x` 会被规范化成 `x`，既没出界、又越过了租户边界）。
class LocalFolderBackend implements SyncBackend {
  LocalFolderBackend(this.root);

  final Directory root;

  /// 把接口层的 path 解析成 root 内的 File。
  ///
  /// 防目录穿越：path 将来由实体 id + hash 前缀生成，虽现在可控，但接口
  /// 是公开的，必须保证拼出的路径仍在 root 内。这里手工规范化分段：
  /// `.` 跳过、`..` 回退一层，一旦回退出界立即抛 ArgumentError。
  /// 不用 canonicalize/resolveSymbolicLinks，因为目标文件可能尚不存在。
  File _resolve(String path) {
    final segments = _normalize(path);
    return File(_fromSegments(segments));
  }

  Directory _dirOf(String namespace) {
    final segments = _normalize(namespace);
    return Directory(_fromSegments(segments));
  }

  /// 规范化相对路径：返回安全分段；逃逸出根目录抛 ArgumentError。
  List<String> _normalize(String path) {
    final raw = path.replaceAll('\\', '/').split('/');
    final out = <String>[];
    for (final seg in raw) {
      if (seg.isEmpty || seg == '.') {
        continue;
      }
      if (seg == '..') {
        if (out.isEmpty) {
          // ../xxx 或对 root 本身做 .. 都视为逃逸。
          throw ArgumentError('路径逃逸出存储根目录: $path');
        }
        out.removeLast();
        continue;
      }
      if (seg.endsWith(':') || seg.contains(':')) {
        // 拦截 Windows 盘符（C: 等）等绝对路径成分。
        throw ArgumentError('路径含非法成分（疑似绝对路径）: $path');
      }
      out.add(seg);
    }
    if (out.isEmpty) {
      throw ArgumentError('路径为空或未指向任何对象: $path');
    }
    return out;
  }

  String _fromSegments(List<String> segments) =>
      [root.path, ...segments].join(Platform.pathSeparator);

  @override
  Future<List<RemoteObject>> list(String namespace) async {
    final dir = _dirOf(namespace);
    if (!dir.existsSync()) {
      return const [];
    }
    final prefixSegments = _normalize(namespace);
    final objects = <RemoteObject>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final rel = entity.path
          .substring(dir.path.length + 1)
          .replaceAll('\\', '/');
      final bytes = await entity.readAsBytes();
      final stat = await entity.stat();
      objects.add(
        RemoteObject(
          path: [...prefixSegments, ...rel.split('/')].join('/'),
          etag: sha256Etag(bytes),
          size: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    return objects;
  }

  @override
  Future<({List<int> bytes, String? etag})> get(String path) async {
    final file = _resolve(path);
    if (!file.existsSync()) {
      throw ObjectNotFoundException(path);
    }
    final bytes = await file.readAsBytes();
    return (bytes: bytes, etag: sha256Etag(bytes));
  }

  @override
  Future<String?> put(String path, List<int> bytes, {String? ifMatchEtag}) async {
    final file = _resolve(path);

    // ---- CAS（条件写）核心：严格模拟真实云盘 412 语义，绝不放水 ----
    // 传了 ifMatchEtag 时：文件不存在 → 412；当前 etag 与期望不符 → 412。
    // 与真云盘一致，宽松实现会让双端测试漏掉同步逻辑的并发 bug。
    if (ifMatchEtag != null) {
      final current = await _currentEtagOrNull(file);
      if (current == null || current != ifMatchEtag) {
        throw PreconditionFailedException(
          path: path,
          expectedEtag: ifMatchEtag,
          actualEtag: current,
        );
      }
    }

    // put 必须自动创建父目录：真云盘要逐级 MKCOL 预创建（已实测），那是
    // WebDAV 后端的负担；本地后端自动建目录，测试更省事。
    final parent = file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    // 原子写：先写同目录临时文件，再 rename，避免半截 JSON。
    final tmp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-'
      '${Random().nextInt(1 << 32)}',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      // Windows 下 rename 不覆盖已存在目标时可能报错，删旧后重试一次。
      if (file.existsSync()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    }
    return sha256Etag(bytes);
  }

  Future<String?> _currentEtagOrNull(File file) async {
    if (!file.existsSync()) {
      return null;
    }
    return sha256Etag(await file.readAsBytes());
  }

  @override
  Future<void> delete(String path, {String? ifMatchEtag}) async {
    final file = _resolve(path);
    if (ifMatchEtag != null) {
      // 条件删与条件写同一套 412 语义：不存在或 etag 不符都拒绝。
      final current = await _currentEtagOrNull(file);
      if (current == null || current != ifMatchEtag) {
        throw PreconditionFailedException(
          path: path,
          expectedEtag: ifMatchEtag,
          actualEtag: current,
        );
      }
    }
    if (!file.existsSync()) {
      throw ObjectNotFoundException(path);
    }
    await file.delete();
  }

  @override
  Future<void> ensureReady() async {} // 根即构造参数目录，无就绪概念。

  @override
  Future<BackendCapabilities> capabilities() async {
    return const BackendCapabilities(
      supportsConditionalWrite: true,
      supportsList: true,
      supportsRangeRead: false,
    );
  }
}
