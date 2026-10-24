import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/update/release_notes.dart';

/// 更新说明表的内容与查表规则。
///
/// 文案本身没有逻辑，但它是**给人看的唯一来源**：这里钉住的是「哪几条必须说到」，
/// 不是每个字——以后润色措辞不必改测试，把某一条整段删掉才应该红。
void main() {
  test('1.0.3 的说明是五行要点，覆盖本轮全部改动', () {
    final String notes = releaseNotesFor('1.0.3')!;
    final List<String> lines = notes.split('\n');
    expect(lines.length, 5);
    for (final String line in lines) {
      // 项目里没有 Markdown 渲染器，列表只能靠行首符号，写成 `- ` 或 `* ` 会不一致。
      expect(line, startsWith('· '), reason: line);
    }
    expect(notes, contains('学习通刷新变快'));
    expect(notes, contains('22:20 更新'));
    expect(notes, contains('刷新失败不再静默变成空列表'));
    expect(notes, contains('本次更新内容'));
    expect(notes, contains('检测更新弹层里会显示这一版的更新说明'));
  });

  test('1.0.8 的说明覆盖两个刷新缺陷', () {
    final String notes = releaseNotesFor('1.0.8')!;
    expect(notes.split('\n').first, '更新内容');
    expect(notes, contains('角标'));
    expect(notes, contains('学期列表'));
    expect(notes, contains('下载'));
  });

  test('1.0.7 起按「更新内容 / 下载」两段写', () {
    final String notes = releaseNotesFor('1.0.7')!;
    final List<String> lines = notes.split('\n');
    expect(lines.first, '更新内容');
    expect(lines, contains('下载'));
    expect(notes, contains('上次刷新时间'));
    expect(notes, contains('重试'));
    expect(notes, contains('下载并安装'));
  });

  test('1.0.2 的说明说清设置里多了哪两个入口，以及不自己装包', () {
    final String notes = releaseNotesFor('1.0.2')!;
    expect(notes, contains('设置 → 通用'));
    expect(notes, contains('检测更新'));
    expect(notes, contains('GitHub 仓库'));
    // 这是这个功能的边界：Android 覆盖安装要求签名一致，换签名要先卸载、卸载清库。
    expect(notes, contains('不会自己下载'));
  });

  test('没有写说明的版本返回 null，界面才能退到「没有附说明」', () {
    expect(releaseNotesFor('9.9.9'), isNull);
    expect(releaseNotesFor(''), isNull);
  });

  test('带 v 前缀或 +build 的版本号也查得到', () {
    expect(releaseNotesFor('v1.0.3'), releaseNotesFor('1.0.3'));
    expect(releaseNotesFor('1.0.3+7'), releaseNotesFor('1.0.3'));
    expect(releaseNotesFor(' v1.0.2+12 '), releaseNotesFor('1.0.2'));
  });

  test('表里的键都是三段式版本号：写成 v1.0.3 就永远匹配不上', () {
    for (final String key in kReleaseNotes.keys) {
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(key), isTrue, reason: key);
    }
  });
}
