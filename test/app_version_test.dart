import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/about_section.dart';
import 'package:qingdan/update/release_notes.dart';

/// 版本号对账（M6-C 计划文档承诺过这条测试，但一直没建文件——
/// `about_section.dart` 的注释还写着「改了 pubspec 忘了改这里，这条测试就红」，
/// 而它当时是空的。补上，并把「关于」页与「检查更新」两处展示一起钉住。）
void main() {
  /// pubspec 的 `version: 1.0.1+2` → 取 `+` 之前的 SemVer 主串。
  String pubspecVersion() {
    final String spec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
            .firstMatch(spec);
    expect(m, isNotNull, reason: 'pubspec.yaml 里没找到 version: 主.次.修订');
    return m!.group(1)!;
  }

  test('kAppVersion 必须与 pubspec 的 version 一致', () {
    expect(kAppVersion, pubspecVersion(),
        reason: '「关于」页与「检查更新」显示的是 kAppVersion；它和 pubspec 漂开，'
            '用户就没法分辨自己装的是哪一个包（2026-10-19 要发安卓包时撞上的）。');
  });

  test('版本号是三段 SemVer，比较逻辑将来按段比不会错', () {
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kAppVersion), isTrue,
        reason: kAppVersion);
  });

  /// 发版时「改了版本号、忘了写更新说明」的代价是升级后弹一个空框
  /// （「本次更新没有附说明」），那比不弹更让人困惑——所以在这里把它变成红色。
  test('当前版本必须有非空的更新说明', () {
    final String? notes = releaseNotesFor(kAppVersion);
    expect(notes, isNotNull,
        reason: 'lib/update/release_notes.dart 里没有 kReleaseNotes[$kAppVersion]；'
            '升版本时一起写上这一版改了什么。');
    expect(notes!.trim(), isNotEmpty);
  });
}
