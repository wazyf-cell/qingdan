import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/week_rule.dart';

/// 周次解析的**必须报错**路径（§3.3.5「应当报错而不是猜测」五种 + 边界）。
///
/// 设计立场：错猜的代价是用户课表**悄悄缺课**，所以这些输入一律抛
/// [WeekRuleFormatException] 并携带原文，**绝不允许 catch 后返回空列表**
/// （§6.3.1 点名的头号 bug 源）。
void main() {
  const int total = 16;

  WeekRuleFormatException errorOf(String raw) {
    try {
      parseWeekRule(raw, totalWeeks: total);
    } on WeekRuleFormatException catch (e) {
      return e;
    }
    throw StateError('输入「$raw」本应报错，却解析成功');
  }

  List<int> weeks(String raw) =>
      parseWeekRule(raw, totalWeeks: total).weeks;

  test('1 切段后存在既非数字、范围、月日的乱段', () {
    final WeekRuleFormatException e = errorOf('1-5、约、7-11单');
    expect(e.badText, contains('约'));
    expect(e.toString(), contains('周次解析失败'));
  });

  test('2 范围倒序报错，且绝不自动交换', () {
    expect(errorOf('16-1').reason, contains('倒序'));
    // 交换会掩盖用户真实意图，所以这里连「悄悄变成 1..16」都不允许发生。
    expect(() => weeks('16-1'), throwsA(isA<WeekRuleFormatException>()));
    expect(() => weeks('12-16双、9-3'), throwsA(isA<WeekRuleFormatException>()));
  });

  test('3 出现 0 或负数', () {
    expect(errorOf('0').reason, contains('正整数'));
    expect(errorOf('1-0').reason, contains('正整数'));
    expect(() => weeks('-3'), throwsA(isA<WeekRuleFormatException>()));
  });

  test('4 解析结果为空（切完没有任何有效数字）', () {
    expect(errorOf('abc').badText, isNotEmpty);
    expect(errorOf('第周').reason, contains('任何有效内容'));
    expect(errorOf('、').badText, isNotNull);
  });

  test('5 单/双 出现在单值之后（WakeUp 在此直接崩溃）', () {
    expect(errorOf('5单').reason, contains('范围'));
    expect(errorOf('7、11双').reason, contains('范围'));
  });

  test('错误对象必须可分类：不是通用 Exception 的兜底', () {
    expect(errorOf('16-1'), isA<WeekRuleFormatException>());
    // 结构化错误要能直接喂给校正界面，所以原文字段必须非空。
    for (final String raw in <String>['约', '16-1', '0', 'abc', '5单']) {
      expect(errorOf(raw).badText, isNotEmpty, reason: raw);
    }
  });

  test('不报错的边界：多余分隔符按「连续算一个」处理', () {
    expect(weeks('1-5、'), <int>[1, 2, 3, 4, 5]);
    expect(weeks('、1-5'), <int>[1, 2, 3, 4, 5]);
    expect(weeks('1-5、、7'), <int>[1, 2, 3, 4, 5, 7]);
    expect(weeks(' 1-2 '), <int>[1, 2]);
  });

  test('周次超出学期总周数不在解析层报错（交给 §3.4 三选一）', () {
    expect(() => weeks('1-30'), returnsNormally);
    expect(weeks('20-25'), <int>[20, 21, 22, 23, 24, 25]);
  });
}
