/// 学习通 HTML 页解析的共用小工具（纯函数，无 IO）。
///
/// 抄的是油猴脚本 `扩展/作业列表.js`（上游 https://github.com/Cooanyh/chaoxing-list，
/// AGPL-3.0-or-later）里由 DOM 免费提供的三件事——`getAttribute` /
/// `textContent` / `new URL(x).searchParams`：我们只用正则切 HTML（项目没引
/// html 包，也不为一个属性解析新增依赖），所以这三件必须自己实现，且**三个解析器
/// （作业 `chaoxing_homework.dart` / 考试 `chaoxing_exam.dart` / 以后日历那页）
/// 共用一份**，各写一份迟早漂移（`&amp;` 少解一次，标题就会显示成 `A&amp;B`）。
///
/// 只处理超星页面真会出现的实体，不做全集：`&amp; &lt; &gt; &quot; &#39; &nbsp;`。
library;

/// HTML 实体还原（顺序不能反：先 `&amp;` 会把 `&amp;lt;` 折成 `<`）。
String unescapeHtml(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

final RegExp _kTags = RegExp(r'<[^>]*>');
final RegExp _kSpace = RegExp(r'\s+');

/// 一段 HTML 的 `textContent`：剥掉标签、还原实体、空白压成单个空格再 trim。
///
/// 表格单元格里常见 `<br>` 与换行缩进（脚本 :843-849 用的是 `textContent.trim()`，
/// 浏览器会把连续空白折成一根空格），这里同形，否则「2026-10-11 08:00」会被
/// 抓成带一堆换行的串，日期正则照样命中但相邻两个时刻之间可能只剩不下分隔符。
String htmlText(String html) =>
    unescapeHtml(html.replaceAll(_kTags, ' ')).replaceAll(_kSpace, ' ').trim();

/// 从一个开始标签的属性串里取属性值（等价于 `el.getAttribute(name)`）。
///
/// `[head]` 是 `<li …>` / `<a …>` 里标签名之后、`>` 之前那段。属性顺序不限、
/// 可缺省；单引号写法也认（超星自己两种都用过）。
String attrOf(String head, String name) {
  final RegExpMatch? m =
      RegExp('''\\b$name\\s*=\\s*(?:"([^"]*)"|'([^']*)')''').firstMatch(head);
  if (m == null) return '';
  return unescapeHtml(m.group(1) ?? m.group(2) ?? '');
}

/// URL 的查询参数（等价于 `new URL(x).searchParams`）。
///
/// 绝对地址、`/开头的相对路径`、裸查询串三种都吃：考试卡片页的 `li[data]` 是
/// 绝对地址，脚本 :819 遇到 `/` 开头还要补 origin，其实只为了拿 query，
/// 这里直接取 `?` 之后的部分，省掉那次拼接。
Map<String, String> queryOf(String url) {
  if (url.isEmpty) return const <String, String>{};
  final int i = url.indexOf('?');
  String query = i < 0 ? url : url.substring(i + 1);
  final int hash = query.indexOf('#'); // 片段不算参数（URL_EXAM :463 就带一个）
  if (hash >= 0) query = query.substring(0, hash);
  if (query.isEmpty) return const <String, String>{};
  try {
    // splitQueryString 遇到半截百分号转义（`%ZZ`）会抛：一行坏参数不该让整页丢。
    return Uri.splitQueryString(query);
  } catch (_) {
    return const <String, String>{};
  }
}

/// 第一个能用的值：按 [names] 的顺序取 [params] 里第一个非空项。
String firstOf(Map<String, String> params, List<String> names) {
  for (final String n in names) {
    final String v = params[n] ?? '';
    if (v.isNotEmpty) return v;
  }
  return '';
}
