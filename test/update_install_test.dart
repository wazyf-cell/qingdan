import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/update/update_checker.dart';
import 'package:qingdan/update/update_install.dart';

/// 应用内更新的纯逻辑：挑哪份 APK、校验和怎么对、签名怎么比。
///
/// 这几条都在离线测试里钉死：真机上只该验证「下载 + 调起安装器」这一段，
/// 挑错包或比错签名不该等真机才发现。
void main() {
  ReleaseAsset apk(String name) =>
      ReleaseAsset(name: name, url: 'https://example.com/$name', size: 100);

  group('ABI 归一', () {
    test('系统给的名字 → 发布页里的三段', () {
      expect(normalizeAbi('arm64-v8a'), 'arm64-v8a');
      expect(normalizeAbi('aarch64'), 'arm64-v8a');
      expect(normalizeAbi('armeabi-v7a'), 'armeabi-v7a');
      expect(normalizeAbi('arm'), 'armeabi-v7a');
      expect(normalizeAbi('x86_64'), 'x86_64');
      expect(normalizeAbi('unknown'), isNull);
      expect(normalizeAbi(null), isNull);
    });
  });

  group('挑 APK', () {
    final List<ReleaseAsset> three = <ReleaseAsset>[
      apk('qingdan-1.0.4-arm64-v8a.apk'),
      apk('qingdan-1.0.4-armeabi-v7a.apk'),
      apk('qingdan-1.0.4-x86_64.apk'),
      ReleaseAsset(
          name: 'qingdan-1.0.4-sha256sums.txt',
          url: 'https://example.com/sums',
          size: 281),
    ];

    test('按 ABI 精确挑，不挑到别家的包', () {
      expect(pickApkAsset(three, 'arm64-v8a')?.name,
          'qingdan-1.0.4-arm64-v8a.apk');
      expect(pickApkAsset(three, 'armeabi-v7a')?.name,
          'qingdan-1.0.4-armeabi-v7a.apk');
      expect(pickApkAsset(three, 'x86_64')?.name, 'qingdan-1.0.4-x86_64.apk');
    });

    test('多份包里认不出本机 ABI → 不猜，返回 null', () {
      expect(pickApkAsset(three, null), isNull);
      expect(pickApkAsset(three, 'riscv64'), isNull,
          reason: '瞎挑一份会把 arm64 包装到 32 位设备上，安装器只给英文报错');
    });

    test('发布页只有一份 APK → 退回它（通用包）', () {
      expect(pickApkAsset(<ReleaseAsset>[apk('qingdan-1.0.4.apk')], null)?.name,
          'qingdan-1.0.4.apk');
    });

    test('没有任何 APK → null', () {
      expect(pickApkAsset(<ReleaseAsset>[], 'arm64-v8a'), isNull);
      expect(
          pickApkAsset(<ReleaseAsset>[apk('notes.txt')], 'arm64-v8a'), isNull);
    });
  });

  group('校验和', () {
    test('认出 sha256sums 文件（不分大小写）', () {
      expect(
          sha256Asset(<ReleaseAsset>[
            apk('a.apk'),
            ReleaseAsset(name: 'SHA256SUMS.txt', url: 'u'),
          ])?.name,
          'SHA256SUMS.txt');
      expect(sha256Asset(<ReleaseAsset>[apk('a.apk')]), isNull);
    });

    test('两种行格式都能取到指定文件', () {
      final String a = 'a' * 64, b = 'b' * 64;
      final String sums = '$a  qingdan-1.0.4-arm64-v8a.apk\n'
          '$b *qingdan-1.0.4-x86_64.apk\n';
      expect(expectedSha256(sums, 'qingdan-1.0.4-arm64-v8a.apk'), a);
      expect(expectedSha256(sums, 'qingdan-1.0.4-x86_64.apk'), b);
      expect(expectedSha256(sums, 'missing.apk'), isNull);
      expect(expectedSha256('不是校验和', 'a.apk'), isNull);
    });
  });

  group('签名比对', () {
    test('大小写无关，相等才通过', () {
      expect(signaturesMatch('ABCDEF', 'abcdef'), isTrue);
      expect(signaturesMatch('  abcdef  ', 'abcdef'), isTrue);
      expect(signaturesMatch('abcdef', 'abcdee'), isFalse);
    });

    test('任一侧读不到 → 一律按不一致：宁可不进安装器', () {
      expect(signaturesMatch(null, 'abcdef'), isFalse);
      expect(signaturesMatch('abcdef', null), isFalse);
      expect(signaturesMatch('', ''), isFalse);
    });
  });

  test('文件大小：一位小数就够', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2 KB');
    expect(formatBytes(24692366), '23.5 MB');
  });
}
