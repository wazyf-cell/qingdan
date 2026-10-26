/// 考试条目三个 id 的解析：`courseId` / `classId` / `examId`（纯函数）。
///
/// 从 `chaoxing_exam.dart` 拆出（单文件 300 行红线）。取值顺序照油猴脚本
/// `扩展/作业列表.js` :861-878：`go('…')` 地址 → `refer` 参数 → 直接在整段
/// HTML 上正则；额外扫所有 `<a>` 与 `data` / 隐藏 input / 行内 JS。
library;

import 'chaoxing_html.dart';

final RegExp _kAnchor = RegExp(r'<a\b([^>]*)>');
final RegExp _kGo = RegExp('''go\\(\\s*['"]([^'"]+)['"]''');

/// 从一行 / 一张卡片 / 一段地址里取三个 id；缺的返回空串。
Map<String, String> examIdsOf(String html) {
  final Map<String, String> out = <String, String>{
    'courseId': '',
    'classId': '',
    'examId': '',
  };
  for (final RegExpMatch anchor in _kAnchor.allMatches(html)) {
    final String attrs = anchor.group(1)!;
    final String raw = _kGo.firstMatch(attrOf(attrs, 'onclick'))?.group(1) ??
        attrOf(attrs, 'href');
    _merge(out, _idsFromRaw(raw));
  }
  // `li[data]`、隐藏 input、行内 JS：只补还空着的项，不覆盖操作链接里的值。
  _merge(out, _idsFromRaw(html));
  return out;
}

/// 一串地址（或整段 HTML）里的三个 id；`refer` 优先，其次外层参数，
/// 最后在整串上直接正则。
Map<String, String> _idsFromRaw(String raw) {
  final Map<String, String> outer = queryOf(raw);
  String refer = outer['refer'] ?? '';
  // refer 可能被整体二次转义（脚本 :867 又 decode 了一次）：解完还剩
  // %3D/%26 就再解一次。解不动保持原样，后面还有正则退路。
  if (refer.contains('%3D') || refer.contains('%26')) {
    try {
      refer = Uri.decodeFull(refer);
    } catch (_) {}
  }
  final Map<String, String> inner = queryOf(refer);
  return <String, String>{
    'courseId': _pick(
      <String?>[
        inner['courseId'],
        inner['courseid'],
        outer['courseId'],
        outer['courseid'],
        outer['moocId'],
        outer['moocid'],
      ],
      raw,
      <String>['courseId', 'courseid', 'moocId', 'moocid'],
    ),
    'classId': _pick(
      <String?>[
        inner['classId'],
        inner['classid'],
        inner['clazzid'],
        outer['classId'],
        outer['classid'],
        outer['clazzid'],
      ],
      raw,
      <String>['classId', 'classid', 'clazzid'],
    ),
    'examId': _pick(
      <String?>[
        inner['examId'],
        inner['examid'],
        inner['taskrefId'],
        inner['taskrefid'],
        outer['examId'],
        outer['examid'],
        outer['taskrefId'],
        outer['taskrefid'],
      ],
      raw,
      <String>['examId', 'examid', 'taskrefId', 'taskrefid'],
    ),
  };
}

/// 取值优先序：refer 里的 > 外层地址里的 > 在整串上正则到的。
String _pick(List<String?> values, String blob, List<String> names) {
  for (final String? v in values) {
    if (v != null && v.isNotEmpty) return v;
  }
  for (final String name in names) {
    final RegExpMatch? m =
        RegExp('\\b$name=(\\d+)', caseSensitive: false).firstMatch(blob);
    if (m != null) return m.group(1)!;
  }
  return '';
}

void _merge(Map<String, String> out, Map<String, String> add) {
  for (final String key in out.keys.toList()) {
    if (out[key]!.isEmpty && (add[key] ?? '').isNotEmpty) {
      out[key] = add[key]!;
    }
  }
}

/// 第一个非空值；用于 `p[...]` / 整卡扫描结果的合并。
String firstNonEmpty(List<String?> values) {
  for (final String? v in values) {
    if (v != null && v.isNotEmpty) return v;
  }
  return '';
}
