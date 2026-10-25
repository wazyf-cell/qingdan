/// GitHub 发布说明 → 弹层可用纯文本（检测更新与启动自动检查共用）。
///
/// 新版发布页按 `## 更新内容` / `## 下载` / `## 覆盖安装说明` 分段，弹层只需要
/// 第一段；后面的下载与安装说明由界面自己负责，重复搬进来会把真正的改动挤下去。
library;

/// 发布说明的长度上限。GitHub 的 `body` 没有长度限制，长文会把弹层撑成墙。
const int kMaxNoteChars = 1200;

/// 只取「更新内容」段；老格式（没有这个标题）原样返回。
String updateNotesSection(String raw) {
  final List<String> lines = raw.split('\n');
  final RegExp heading = RegExp(r'^\s*#{1,6}\s+(.+?)\s*$');
  int start = -1;
  for (int i = 0; i < lines.length; i++) {
    final RegExpMatch? m = heading.firstMatch(lines[i]);
    if (m != null && m[1]!.trim() == '更新内容') {
      start = i + 1;
      break;
    }
  }
  if (start < 0) return raw;
  final List<String> kept = <String>[];
  for (int i = start; i < lines.length; i++) {
    if (heading.hasMatch(lines[i])) break;
    kept.add(lines[i]);
  }
  final String text = kept.join('\n').trim();
  return text.isEmpty ? raw : text;
}

/// 把 Markdown 发布说明压成纯文本（项目没有 Markdown 渲染器）。
String plainNotes(String raw) {
  if (raw.isEmpty) return raw;
  final StringBuffer out = StringBuffer();
  for (final String line in raw.split('\n')) {
    String l = line.trimRight();
    l = l.replaceFirst(RegExp(r'^\s*#{1,6}\s+'), ''); // 标题
    l = l.replaceFirst(RegExp(r'^\s*[-*]\s+'), '· '); // 无序列表
    l = l.replaceAll('**', '').replaceAll('`', ''); // 加粗 / 行内代码
    // 链接只留文字：URL 在弹层里既长又点不动。
    l = l.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1] ?? '');
    out.writeln(l);
  }
  return out.toString().trim();
}

/// 发布说明 → 弹层正文：只留更新内容、压成纯文本、截断。没有说明返回 null。
String? dialogReleaseNotes(String? raw) {
  final String text = plainNotes(updateNotesSection(raw?.trim() ?? ''));
  if (text.isEmpty) return null;
  if (text.length <= kMaxNoteChars) return text;
  int end = kMaxNoteChars;
  // 不把代理对（emoji 之类）劈成半个字符。
  final int last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return '${text.substring(0, end)}…';
}
