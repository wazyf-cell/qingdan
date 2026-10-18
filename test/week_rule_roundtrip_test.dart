import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/week_rule.dart';

/// 周次解析的**往返恒等**与超集等价测试（`方案设计-课表域.md` §3.3.5 强制项）。
///
/// 基线是 WakeUp 解析器实际支持的五种写法（§3.3.1）；本项目的超集放宽只允许
/// 放宽**输入**，不得改写展开结果——所以每个超集用例都对着权威写法断言同一集合。
void main() {
  const int total = 16;

  WeekRuleOutcome outcome(String raw) =>
      parseWeekRule(raw, totalWeeks: total);
  List<int> weeks(String raw) => outcome(raw).weeks;

  group('权威写法（WakeUp 基线）：format(parse(x)) == x', () {
    test('单值 N', () {
      expect(weeks('3'), <int>[3]);
      expect(formatWeekRule(outcome('3')), '3');
    });

    test('闭区间 A-B', () {
      expect(weeks('1-5'), <int>[1, 2, 3, 4, 5]);
      expect(formatWeekRule(outcome('1-5')), '1-5');
    });

    test('A-B单 = 绝对奇数周号（不是「从起始周每隔一周」）', () {
      // 这是 §3.3.1 的确证点：`8-12单` 必须是 9、11，而不是 8、10、12。
      expect(weeks('8-12单'), <int>[9, 11]);
      expect(formatWeekRule(outcome('8-12单')), '8-12单');
      expect(formatWeekRule(outcome('7-11单')), '7-11单');
    });

    test('A-B双 = 绝对偶数周号', () {
      expect(weeks('12-16双'), <int>[12, 14, 16]);
      expect(formatWeekRule(outcome('12-16双')), '12-16双');
    });

    test('A月B日（Excel 日期污染）与 A-B 展开相同', () {
      // 用户在 Excel 里写 `3-15` 会被自动转成日期，读回来就是 `3月15日`。
      expect(weeks('3月15日'), weeks('3-15'));
      expect(weeks('3月15日'), List<int>.generate(13, (int i) => i + 3));
      expect(weeks('3月15'), weeks('3-15'));
    });
  });

  group('样本三种写法（`相关来源或素材/课表模板.xlsx` 实测内容）', () {
    test('高等数学：1-5、7-11单、12-16双', () {
      expect(weeks('1-5、7-11单、12-16双'),
          <int>[1, 2, 3, 4, 5, 7, 9, 11, 12, 14, 16]);
      expect(formatWeekRule(outcome('1-5、7-11单、12-16双')),
          '1-5、7-11单、12-16双');
    });

    test('线性代数：1-16 全学期', () {
      expect(weeks('1-16'), List<int>.generate(total, (int i) => i + 1));
      expect(formatWeekRule(outcome('1-16')), '1-16');
    });

    test('大学英语：2、5、8 离散周', () {
      expect(weeks('2、5、8'), <int>[2, 5, 8]);
      expect(formatWeekRule(outcome('2、5、8')), '2、5、8');
    });
  });

  group('超集写法：展开结果必须与权威写法一致', () {
    test('单值的四种写法', () {
      for (final String t in <String>['3', '第3周', '第3', '3周']) {
        expect(weeks(t), <int>[3], reason: '输入「$t」应得 [3]');
      }
    });

    test('范围连接符（半角/全角/破折号/中文）', () {
      final List<int> expected = List<int>.generate(16, (int i) => i + 1);
      for (final String t in <String>[
        '1-16', '1~16', '1－16', '1～16', '1—16', '1–16', '1至16', '1到16',
        '第1-16周', '1-16周',
      ]) {
        expect(weeks(t), expected, reason: '输入「$t」应得 1..16');
      }
    });

    test('单/双后缀的六种写法', () {
      for (final String t in <String>['7-11单', '7-11单周', '7-11（单）']) {
        expect(weeks(t), <int>[7, 9, 11], reason: '输入「$t」');
      }
      for (final String t in <String>['12-16双', '12-16双周', '12-16（双）']) {
        expect(weeks(t), <int>[12, 14, 16], reason: '输入「$t」');
      }
    });

    test('分隔符超集（权威只有顿号，其余是放宽）', () {
      for (final String sep in <String>[
        '、', ',', '，', ';', '；', ' ', '  ', '·', '/', '\n',
      ]) {
        expect(weeks('1$sep' '3'), <int>[1, 3], reason: '分隔符「$sep」');
      }
    });

    test('全角数字先归一为半角', () {
      expect(weeks('３'), <int>[3]);
      expect(weeks('１１'), <int>[11]);
    });

    test('整体关键词', () {
      expect(weeks('单周'), <int>[1, 3, 5, 7, 9, 11, 13, 15]);
      expect(weeks('双周'), <int>[2, 4, 6, 8, 10, 12, 14, 16]);
      final List<int> all = List<int>.generate(total, (int i) => i + 1);
      for (final String t in <String>['全周', '每周', '全部', 'all', 'ALL']) {
        expect(weeks(t), all, reason: '输入「$t」');
      }
    });
  });

  test('空周次不报错：按全学期填充并给出警告（§3.3.5）', () {
    final WeekRuleOutcome r = outcome('');
    expect(r.weeks, List<int>.generate(total, (int i) => i + 1));
    expect(r.warning, WeekRuleWarning.emptyFilledAllWeeks);
    expect(outcome('   ').warning, WeekRuleWarning.emptyFilledAllWeeks);
  });

  test('输出恒为排序 + 去重（渲染与 UID 都依赖它，§6.3.3）', () {
    expect(weeks('5、3、5、1'), <int>[1, 3, 5]);
    expect(weeks('1-4、3-6'), <int>[1, 2, 3, 4, 5, 6]);
  });

  test('formatWeeks 从库里的周次列表还原展示写法', () {
    expect(formatWeeks(<int>[1, 2, 3, 4, 5, 7, 9, 11, 12, 14, 16]),
        '1-5、7-11单、12-16双');
    expect(formatWeeks(<int>[2, 5, 8]), '2、5、8');
    expect(formatWeeks(<int>[3]), '3');
    expect(formatWeeks(<int>[]), '');
  });
}
