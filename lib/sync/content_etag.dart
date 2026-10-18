/// 内容派生 etag：sha256(bytes) 十六进制前 16 位。
///
/// 与 `local_folder_backend.dart` 内置的 sha256Etag 是同一算法的拷贝。
/// 为什么不合用：本次任务规矩不允许修改 local_folder_backend.dart，只能
/// 在此复制一份；后续若允许重构，应让两处共用本文件。
/// WebDAV 后端只在「PUT 后 PROPFIND 拿不到 etag」的兜底路径使用它
/// （见 webdav_backend.dart 陷阱③），以保持「put 返回内容派生 etag」
/// 与 LocalFolderBackend 一致的接口语义。
///
/// 为什么不用 package:crypto：项目铁律不引入新依赖（它只是传递依赖，
/// 未直接声明），内置纯 Dart SHA-256（仅用于小对象）。
library;

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
