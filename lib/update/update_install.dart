/// 更新包的选择与校验（纯函数，无 IO）：挑哪一份 APK、期望的 sha256、签名比对。
library;

import 'update_checker.dart';

/// ABI 到资产文件名里那一段的映射。Flutter `--split-per-abi` 的产物叫
/// `qingdan-1.0.4-arm64-v8a.apk`，与 `Build.SUPPORTED_ABIS` 的首项同名。
///
/// 顺序即优先级：`arm64-v8a` 是现在绝大多数手机；`x86_64` 只给模拟器。
const List<String> kAbiPreference = <String>['arm64-v8a', 'armeabi-v7a', 'x86_64'];

/// 把系统给的 ABI 名归一到发布页里的三段之一；认不出返回 null。
String? normalizeAbi(String? raw) {
  final String s = (raw ?? '').trim().toLowerCase();
  if (s.contains('arm64') || s.contains('aarch64')) return 'arm64-v8a';
  if (s.contains('x86_64') || s == 'x64') return 'x86_64';
  if (s.contains('armeabi') || s == 'arm') return 'armeabi-v7a';
  return null;
}

/// 从发布页资产里挑出这台设备能装的那一个。
///
/// 找不到精确匹配时**只有「发布页只发了一个 APK」才退回它**——多份包里瞎挑一个
/// 会把 arm64 的包装到 v7a 设备上，安装器只会给一句英文错误。
ReleaseAsset? pickApkAsset(List<ReleaseAsset> assets, String? abi) {
  final List<ReleaseAsset> apks = assets
      .where((ReleaseAsset a) =>
          a.url.isNotEmpty && a.name.toLowerCase().endsWith('.apk'))
      .toList(growable: false);
  if (apks.isEmpty) return null;
  final String? want = normalizeAbi(abi);
  if (want != null) {
    for (final ReleaseAsset a in apks) {
      if (a.name.toLowerCase().contains(want)) return a;
    }
  }
  return apks.length == 1 ? apks.single : null;
}

/// 校验和文件（`qingdan-1.0.3-sha256sums.txt`）。
ReleaseAsset? sha256Asset(List<ReleaseAsset> assets) {
  for (final ReleaseAsset a in assets) {
    if (a.name.toLowerCase().contains('sha256sums')) return a;
  }
  return null;
}

/// 从 `sha256sums.txt` 的正文里取某个文件的哈希；没有就返回 null（跳过校验）。
///
/// 两种行都要认：`hash  name`（sha256sum 默认）与 `hash *name`（二进制模式标记）。
String? expectedSha256(String sumsText, String fileName) {
  for (final String line in sumsText.split('\n')) {
    final RegExpMatch? m =
        RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
    if (m == null) continue;
    if (m.group(2)?.trim() == fileName) return m.group(1)!.toLowerCase();
  }
  return null;
}

/// 签名比对：两边都是小写十六进制。任一为空都算「比不了」，按不一致处理——
/// 宁可不进安装器，也不要让用户吃一次 `UPDATE_INCOMPATIBLE` 的英文报错。
bool signaturesMatch(String? installed, String? apk) {
  if (installed == null || apk == null) return false;
  final String a = installed.trim().toLowerCase();
  final String b = apk.trim().toLowerCase();
  return a.isNotEmpty && a == b;
}

/// 人话版文件大小：进度条旁边只放一位小数。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final double kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
