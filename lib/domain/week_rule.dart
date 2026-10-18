/// 周次解析（F29 核心）。
///
/// 语义基线来自参考项目 WakeUp 的导入解析器：
/// `F:\Code\APK-MCP\3-Wakeup\app\src\main\java\...\CSVParser.kt`（类 `CSVParser`，
/// 参考行号 L11-L57：顿号切分 L19、`单` 判定 L25-28、`双` L29-32、
/// `A月B日` 兜底 L38-42、纯数字 L43-47、范围 L33-36），
/// 绝对奇偶语义确证见 `bean\CourseBean.kt:26-39`（`inWeek`）。
/// 本项目在**输入层**做超集放宽、**语义层**与之一致，差异清单见
/// `开发文档/02-方案设计/方案设计-课表域.md` §3.3.2 / §3.3.3。
///
/// 规则段（[WeekSegment]）只是解析器内部的中间表示，**永不落库**；
/// 落库前一律展开为 `List<int>`（§2.4 定案）。
library;

/// 周次奇偶。[odd] 表示**绝对奇数周号**（`week % 2 == 1`），不是「每隔一周」。
enum WeekParity { all, odd, even }

/// 一段周次规则：闭区间 [start, end] 内按 [parity] 取周。
class WeekSegment {
  const WeekSegment(this.start, this.end, this.parity);

  final int start;
  final int end;
  final WeekParity parity;

  /// 展开为具体周次（升序）。
  List<int> expand() => <int>[
        for (int w = start; w <= end; w++)
          if (parity == WeekParity.all ||
              (parity == WeekParity.odd && w.isOdd) ||
              (parity == WeekParity.even && w.isEven))
            w,
      ];
}

/// 解析失败的结构化错误：**任何**失败路径都抛它，绝不返回空列表冒充「没有课」。
/// [badText] 是出错那一段的原文，供人工校正界面（§4.3）直接展示。
class WeekRuleFormatException implements Exception {
  const WeekRuleFormatException(this.badText, this.reason);

  final String badText;
  final String reason;

  @override
  String toString() => '周次解析失败「$badText」：$reason';
}

/// 解析产出的非致命问题。
enum WeekRuleWarning {
  /// 周次整列为空 → 已按全学期 `1..totalWeeks` 填充（§3.3.5）。
  emptyFilledAllWeeks,
}

/// 解析结果：展开并排序去重后的周次 + 警告。
class WeekRuleOutcome {
  const WeekRuleOutcome(this.weeks, this.segments, this.warning);

  final List<int> weeks;
  final List<WeekSegment> segments;
  final WeekRuleWarning? warning;
}

/// 解析 [raw] 周次文本。[totalWeeks] 用于「空周次按全学期」的兜底。
///
/// 归一顺序（§3.3.2，不可随意调整）：trim → 全角转半角 → 去括号 →
/// 整体关键词判定 → 去「第/周/week」表意词 → 切段 → 逐段解析。
WeekRuleOutcome parseWeekRule(String raw, {required int totalWeeks}) {
  String text = toHalfWidth(raw).trim();
  if (text.isEmpty) {
    return WeekRuleOutcome(
      List<int>.generate(totalWeeks, (int i) => i + 1),
      <WeekSegment>[WeekSegment(1, totalWeeks, WeekParity.all)],
      WeekRuleWarning.emptyFilledAllWeeks,
    );
  }

  // 括号只作包裹符，去掉后才能匹配范围式（`7-11（单）` → `7-11单`）。
  text = text.replaceAll(RegExp(r'[（）()]'), '');

  final WeekSegment? keyword = _segmentIfKeyword(text, totalWeeks);
  if (keyword != null) {
    return WeekRuleOutcome(keyword.expand(), <WeekSegment>[keyword], null);
  }

  // 「周/第/week」在本实现里只是表意词，位置无关地剥掉（§3.3.2）。
  final String stripped =
      text.replaceAll(RegExp(r'第|周|[wW][eE][eE][kK]'), '');

  final List<String> parts = stripped
      .split(RegExp(r'[、,，;；·/\s]+'))
      .where((String p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    throw WeekRuleFormatException(raw, '切段后没有任何有效内容');
  }

  final List<WeekSegment> segments =
      parts.map(_parseSegment).toList(growable: false);
  final List<int> weeks = <int>{
    for (final WeekSegment s in segments) ...s.expand(),
  }.toList()
    ..sort();
  if (weeks.isEmpty) {
    throw WeekRuleFormatException(raw, '解析结果为空周次列表');
  }
  return WeekRuleOutcome(weeks, segments, null);
}

/// 范围连接符（§3.3.2 权威 `-` 之外放宽到全角与中文写法）。
final RegExp _rangePattern =
    RegExp(r'^(\d+)(?:[-~－～—–至到]+(\d+))?(单|双)?$');

/// 单段解析：先试范围、再试月日污染、最后当纯数字（§3.3.2 的顺序要求）。
WeekSegment _parseSegment(String part) {
  final String seg = part.trim();
  if (seg.isEmpty) {
    throw WeekRuleFormatException(part, '该段只剩表意词，没有周次数字');
  }

  final RegExpMatch? m = _rangePattern.firstMatch(seg);
  if (m != null) {
    final int start = int.parse(m.group(1)!);
    final String? endText = m.group(2);
    final String? parityText = m.group(3);
    _requirePositive(start, seg);
    if (endText == null) {
      // `5单` / `5双`：奇偶后缀必须跟在范围上（WakeUp 在此直接崩溃，§3.3.5-5）。
      if (parityText != null) {
        throw WeekRuleFormatException(
            seg, '「$parityText」必须跟在范围之后，如 7-11$parityText');
      }
      return WeekSegment(start, start, WeekParity.all);
    }
    final int end = int.parse(endText);
    _requirePositive(end, seg);
    if (start > end) {
      throw WeekRuleFormatException(seg, '范围倒序（不自动交换，避免猜错意图）');
    }
    final WeekParity parity = switch (parityText) {
      '单' => WeekParity.odd,
      '双' => WeekParity.even,
      _ => WeekParity.all,
    };
    return WeekSegment(start, end, parity);
  }

  // Excel 把 `3-15` 自动转成日期 → 单元格读回来是 `3月15日`（或 `3月15`）。
  final RegExpMatch? md =
      RegExp(r'^(\d+)月(\d+)日?$').firstMatch(seg);
  if (md != null) {
    final int start = int.parse(md.group(1)!);
    final int end = int.parse(md.group(2)!);
    _requirePositive(start, seg);
    _requirePositive(end, seg);
    if (start > end) {
      throw WeekRuleFormatException(seg, '日期污染形态范围倒序');
    }
    return WeekSegment(start, end, WeekParity.all);
  }

  throw WeekRuleFormatException(seg, '既不是数字、范围，也不是「A月B日」写法');
}

void _requirePositive(int value, String seg) {
  if (value <= 0) {
    throw WeekRuleFormatException(seg, '周次必须为正整数，出现 $value');
  }
}

/// 整体关键词写法（不含范围数字时的简写，§3.3.2）。
WeekSegment? _segmentIfKeyword(String text, int totalWeeks) {
  final String key = text.replaceAll(RegExp(r'\s'), '').toLowerCase();
  return switch (key) {
    '单周' || '单' => WeekSegment(1, totalWeeks, WeekParity.odd),
    '双周' || '双' => WeekSegment(1, totalWeeks, WeekParity.even),
    '全周' || '每周' || '全部' || 'all' =>
      WeekSegment(1, totalWeeks, WeekParity.all),
    _ => null,
  };
}

/// 全角数字/字母与常见全角标点 → 半角（§3.3.2 归一第一步）。
String toHalfWidth(String input) {
  final StringBuffer buf = StringBuffer();
  for (final int code in input.runes) {
    if (code >= 0xFF10 && code <= 0xFF19) {
      buf.writeCharCode(code - 0xFF10 + 0x30); // ０-９
    } else if (code >= 0xFF21 && code <= 0xFF3A) {
      buf.writeCharCode(code - 0xFF21 + 0x41); // 全角大写字母
    } else if (code >= 0xFF41 && code <= 0xFF5A) {
      buf.writeCharCode(code - 0xFF41 + 0x61); // 全角小写字母
    } else if (code == 0x3000) {
      buf.write(' '); // 全角空格
    } else {
      buf.writeCharCode(code);
    }
  }
  return buf.toString();
}

/// 由解析结果逐段还原紧凑写法，用于 §3.3.5 的**往返恒等**断言。
///
/// 必须走 [WeekRuleOutcome.segments] 而不是展开后的周次列表：`8-12单` 展开为
/// `9、11`，从列表反推只能得到 `9-11单`（同一集合的另一种写法），
/// 恒等断言会误判解析器出错。落库真源仍是 `List<int>`（§2.4），本函数只服务
/// 解析层的回归测试与「按原写法展示」。
String formatWeekRule(WeekRuleOutcome outcome) => outcome.segments
    .map((WeekSegment s) {
      final String parity = switch (s.parity) {
        WeekParity.odd => '单',
        WeekParity.even => '双',
        WeekParity.all => '',
      };
      return s.start == s.end ? '${s.start}$parity' : '${s.start}-${s.end}$parity';
    })
    .join('、');

/// 把周次列表格式回紧凑写法（连续段优先、其次同奇偶段），用于展示库里的 `weeks`。
///
/// 注意 `A月B日` 是输入层的兜底、不是规范写法，因此
/// `formatWeeks(parse('3月15日').weeks) == '3-15'`；该形态的恒等改由
/// 「与 `3-15` 展开结果相同」断言（见 test/week_rule_roundtrip_test.dart）。
String formatWeeks(List<int> weeks) {
  final List<int> sorted = <int>{...weeks}.toList()..sort();
  if (sorted.isEmpty) return '';
  final List<String> out = <String>[];
  int i = 0;
  while (i < sorted.length) {
    int j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    if (j > i) {
      out.add(sorted[i] == sorted[j]
          ? '${sorted[i]}'
          : '${sorted[i]}-${sorted[j]}');
      i = j + 1;
      continue;
    }
    // 连续段只有 1 个时，尝试同奇偶的步长 2 段。
    int k = i;
    while (k + 1 < sorted.length && sorted[k + 1] == sorted[k] + 2) {
      k++;
    }
    if (k > i) {
      final String parity = sorted[i].isOdd ? '单' : '双';
      out.add('${sorted[i]}-${sorted[k]}$parity');
      i = k + 1;
      continue;
    }
    out.add('${sorted[i]}');
    i++;
  }
  return out.join('、');
}
