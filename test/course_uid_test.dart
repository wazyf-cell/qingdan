import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course_uid.dart';

/// 课程 UID 与配色索引测试（§3.5 + §6.3.3）。
///
/// 关注点只有一个：**跨设备稳定**。UID 算得不一致，同步后同一门课会变成两条。
void main() {
  String uid({
    String name = '高等数学',
    int weekday = 2,
    int start = 3,
    int end = 4,
    List<int> weeks = const <int>[1, 2, 3],
  }) =>
      courseUidOf(
        name: name,
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
      );

  group('normalizeCourseName 四步各自生效', () {
    test('① trim', () {
      expect(normalizeCourseName('  高等数学  '), '高等数学');
    });

    test('② 去全部空白（不只是首尾）', () {
      expect(normalizeCourseName('高等 数学\t程序设计'), '高等数学程序设计');
    });

    test('③ 全角转半角', () {
      expect(normalizeCourseName('ＥＮＧ'), 'eng');
      expect(normalizeCourseName('英语 １０１'), '英语101');
    });

    test('④ 转小写', () {
      expect(normalizeCourseName('Advanced Math'), 'advancedmath');
    });

    test('四步合起来：写法不同必须算出同一个 UID', () {
      expect(normalizeCourseName('  English 101 '), 'english101');
      expect(normalizeCourseName('ＥＮＧＬＩＳＨ　１０１'), 'english101');
      expect(uid(name: '  English 101 '), uid(name: 'ＥＮＧＬＩＳＨ　１０１'));
      expect(uid(name: 'English  101'), uid(name: 'english101'));
    });
  });

  test('weeks 参与哈希前排序去重：乱序与重复都算同一个 UID', () {
    expect(uid(weeks: <int>[3, 1, 2]), uid(weeks: <int>[1, 2, 3]));
    expect(uid(weeks: <int>[1, 1, 2, 2, 3]), uid(weeks: <int>[1, 2, 3]));
  });

  test('周次必须进 UID：同槽不同周次的两门课不得合并（§3.5 样本第 2、3 行）', () {
    final String linearAlgebra =
        uid(name: '线性代数', weekday: 2, start: 3, end: 4, weeks: <int>[1, 2, 3]);
    final String english =
        uid(name: '大学英语', weekday: 2, start: 3, end: 4, weeks: <int>[2, 5, 8]);
    expect(linearAlgebra, isNot(english));
    // 同名同槽、只有周次不同 —— 也必须分开。
    expect(uid(weeks: <int>[1, 2]), isNot(uid(weeks: <int>[3, 4])));
  });

  test('键的每个分量都影响结果', () {
    final String base = uid();
    expect(uid(weekday: 3), isNot(base));
    expect(uid(start: 1), isNot(base));
    expect(uid(end: 5), isNot(base));
    expect(uid(name: '别的课'), isNot(base));
  });

  test('UID 是 40 位十六进制 sha1，且同输入恒定', () {
    final String first = uid();
    expect(first, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(uid(), first);
  });

  group('配色索引跨设备稳定且落在调色板内', () {
    test('同一课名恒定同色', () {
      expect(courseColorIndex('高等数学'), courseColorIndex('高等数学'));
      expect(courseColorIndex(' 高等 数学 '), courseColorIndex('高等数学'));
    });

    test('取值范围 0..7', () {
      for (final String name in <String>[
        '高等数学', '线性代数', '大学英语', '体育', '形势与政策',
        '数据结构', '操作系统', '计算机网络', '毛概', '实验课',
      ]) {
        expect(courseColorIndex(name), inInclusiveRange(0, kCoursePaletteSize - 1),
            reason: name);
      }
    });
    test('颜色绝不进 UID（M6-D §五.4）：改配色不该让下次导入认成另一门课', () {
      final List<int> weeks = <int>[1, 2, 3];
      final String first = uid();
      expect(
          courseUidOf(
              name: '高等数学',
              weekday: 2,
              startSection: 3,
              endSection: 4,
              weeks: weeks),
          first,
          reason: '同一套字段必须算出同一个键');
      // `courseUidOf` 的入参里**没有颜色**：颜色是 `Course` 上的可空列，只影响
      // 渲染。哪天有人给 UID 加输入字段，上面这条会先变红。
    });
  });
}
