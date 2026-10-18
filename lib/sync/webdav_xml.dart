/// WebDAV PROPFIND 多状态响应的极简 XML 解析。
///
/// 为什么手写而不用 xml 包：项目铁律不引入新依赖（pubspec 无 xml/data_xml）。
/// WebDAV 的多状态响应结构固定（multistatus > response > href + propstat >
/// prop > getetag/getcontentlength/getlastmodified），用一个宽容的标签扫描器
/// 足够，且天然免疫前缀差异（坚果云可能用 d: / D: / 无前缀，测试样本按
/// 真实形状构造）。
///
/// 设计取舍：
/// - 只找「本地名」，忽略命名空间前缀（`<d:getetag/>`、`<getetag/>`、
///   `<D:getetag/>` 都识别），因为坚果云的 PROPFIND 响应前缀不保证一致；
/// - 不处理属性转义之外的其他 XML 特性（PI、DOCTYPE 不应出现在 PROPFIND 里，
///   出现则当纯文本跳过即可）；
/// - href 是百分号编码的（坚果云对非 ASCII 目录名实测返回
///   `/dav/%e6%88%91%e7%9a%84%e5%9d%9a%e6%9e%9c%e4%ba%91/`），此处**不解码**，
///   保留原样，由 [WebDavBackend] 与自身编码后的 URL 做字符串级比对。
library;

import 'dart:io' show HttpDate;

/// multistatus 里的一条 response（一个资源）。
class WebDavPropStatEntry {
  const WebDavPropStatEntry({
    required this.href,
    this.etag,
    this.contentLength,
    this.lastModified,
    this.isDirectory = false,
  });

  /// 资源 URI 路径（百分号编码原样，未解码）。
  final String href;

  /// getetag 值；已剥去两端引号（坚果云 etag 是裸值，但防御性剥引号统一形状）。
  final String? etag;

  /// getcontentlength（仅文件；目录无此属性）。
  final int? contentLength;

  /// getlastmodified 解析结果（RFC 1123 HTTP-date；解析失败为 null）。
  final DateTime? lastModified;

  /// collection（目录）标记：`<d:collection/>` 或 `<d:resourcetype><d:collection/></d:resourcetype>`。
  final bool isDirectory;
}

/// 解析 207 multistatus 响应体，返回全部 response 条目。
///
/// 实测陷阱④：坚果云只有用 `<d:allprop/>` 或 `<d:propname/>` 发 PROPFIND
/// 才稳定返回 getetag；解析侧与此无关，只要响应里有就取。
List<WebDavPropStatEntry> parseMultistatus(String xml) {
  final entries = <WebDavPropStatEntry>[];
  var cursor = 0;
  while (true) {
    final rs = _findTagStart(xml, 'response', cursor);
    if (rs == null) {
      break;
    }
    final re = _findTagEnd(xml, 'response', rs);
    // 闭合标签缺失（截断响应）时跳过该条目，不让整次解析崩掉。
    if (re == null) {
      break;
    }
    final chunk = xml.substring(rs, re);
    entries.add(_parseResponse(chunk));
    cursor = re;
  }
  return entries;
}

WebDavPropStatEntry _parseResponse(String chunk) {
  // href 缺失的 response 无从定位，视为不可用条目。
  final href = _readSimpleText(chunk, 'href');
  if (href == null) {
    return const WebDavPropStatEntry(href: '');
  }

  // getcontentlength / getlastmodified / getetag 可能分散在多个 propstat 块
  // （200 与 404 状态各一块），所以在整段 response 里找，找到第一个非空值。
  final etagRaw = _readSimpleText(chunk, 'getetag');
  final lenText = _readSimpleText(chunk, 'getcontentlength');
  final modText = _readSimpleText(chunk, 'getlastmodified');

  return WebDavPropStatEntry(
    href: href,
    etag: etagRaw == null ? null : _stripQuotes(etagRaw),
    contentLength: lenText == null ? null : int.tryParse(lenText.trim()),
    lastModified: modText == null ? null : _parseHttpDate(modText.trim()),
    // collection 是空元素标记，出现在 resourcetype 内即视为目录。
    isDirectory: RegExp(r'<[\w.-]*:?collection\s*/?>').hasMatch(chunk),
  );
}

/// 读 `<tag>text</tag>` 的文本；自闭合/缺失返回 null。
/// 同时取 CDATA 与普通文本，实体只处理最常见的三种（PROPFIND 文本里
/// href 可能含 &amp; 等）。
String? _readSimpleText(String xml, String localName) {
  final open = _findTagStart(xml, localName, 0);
  if (open == null) {
    return null;
  }
  final gt = xml.indexOf('>', open);
  if (gt < 0) {
    return null;
  }
  // 自闭合 <tag/> 无文本。
  if (xml[gt - 1] == '/') {
    return null;
  }
  final close = _findCloseStart(xml, localName, gt + 1);
  if (close == null) {
    return null;
  }
  var text = xml.substring(gt + 1, close);
  final cdata = RegExp(r'<!\[CDATA\[(.*)\]\]>', dotAll: true).firstMatch(text);
  if (cdata != null) {
    text = cdata.group(1)!;
  }
  return text
      .replaceAllMapped(
        RegExp(r'&(amp|lt|gt|quot|apos|#x?[0-9a-fA-F]+|#x?[0-9]+);'),
        (m) {
          final e = m.group(1)!;
          switch (e) {
            case 'amp':
              return '&';
            case 'lt':
              return '<';
            case 'gt':
              return '>';
            case 'quot':
              return '"';
            case 'apos':
              return "'";
            default:
              // 数字实体（#123 / #x1F600）。
              if (e.startsWith('#x') || e.startsWith('#X')) {
                final cp = int.tryParse(e.substring(2), radix: 16);
                return cp == null ? m.group(0)! : String.fromCharCode(cp);
              }
              if (e.startsWith('#')) {
                final cp = int.tryParse(e.substring(1));
                return cp == null ? m.group(0)! : String.fromCharCode(cp);
              }
              return m.group(0)!;
          }
        },
      )
      .trim();
}

/// 找 `<prefix:localName ...>` 或 `<localName ...>` 的开头。
/// 排除 `</` 结束标签与 XML 注释（`<!--`）。
int? _findTagStart(String xml, String localName, int from) {
  final pattern = RegExp('<([\\w.-]*:)?$localName(?=[\\s>/])');
  final m = pattern.firstMatch(xml.substring(from));
  if (m == null) {
    return null;
  }
  final idx = from + m.start;
  if (idx + 1 < xml.length && xml[idx + 1] == '/') {
    return null; // 是结束标签
  }
  return idx;
}

/// 找 `</prefix:localName>` 之后的下标（闭合标签 `>` 之后）。
/// 用于 parseMultistatus 推进游标；必须匹配同名闭合标签，不能找任意
/// `</`——response 内部嵌套 href/propstat 等更早出现的闭合标签会截断扫描。
int? _findTagEnd(String xml, String localName, int from) {
  final m =
      RegExp('</([\\w.-]*:)?$localName\\s*>').firstMatch(xml.substring(from));
  if (m == null) {
    return null;
  }
  return from + m.end;
}

/// 找 `</prefix:localName>` 的**起始**下标（`<` 处）。
/// 取标签文本用它：文本 = 开标签之后到闭标签之前的区间；
/// 若误用闭合标签末尾，文本会带上 `</tag>` 本身（实测踩过的坑）。
int? _findCloseStart(String xml, String localName, int from) {
  final m =
      RegExp('</([\\w.-]*:)?$localName\\s*>').firstMatch(xml.substring(from));
  return m == null ? null : from + m.start;
}

/// 剥掉 ETag 两端引号（单双引号与 W/ 前缀统一处理）。
/// 实测陷阱①：坚果云 If-Match 只接受**不带引号的裸 etag**，任何引号形式
/// 都返回 412，与真并发冲突表现完全相同，极易误诊——所以在本后端唯一
/// 出口处统一剥，保证后续 If-Match 永远是裸值。
String _stripQuotes(String etag) {
  var v = etag.trim();
  if (v.startsWith('W/') || v.startsWith('w/')) {
    v = v.substring(2);
  }
  if (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    v = v.substring(1, v.length - 1);
  }
  return v;
}

/// RFC 1123 HTTP-date：`Mon, 28 Sep 2026 05:12:23 GMT`。
/// 坚果云 getlastmodified 是秒级精度（实测）。
DateTime? _parseHttpDate(String s) {
  try {
    return HttpDate.parse(s);
  } on FormatException {
    return null;
  }
}

/// 把 XML 文本里的中文等非 ASCII/保留字符做百分号编码（WebDAV href 风格）。
/// 与 [_decodeSeg] 互为逆运算（编码在 URL 拼接侧，解码在响应解析侧）。
String percentEncodeSegment(String segment) => Uri.encodeComponent(segment);

/// 百分号解码；非法转义（如裸 `%`）时原样返回，不抛。
/// 测试辅助与 URL 拼接用之外，也是 [resolveObjects] 的比对前置步骤。
String decodeSeg(String s) {
  try {
    return Uri.decodeComponent(s);
  } on ArgumentError {
    return s;
  }
}

/// 把 multistatus 条目解析成「相对 namespace 的路径 + 原始条目」。
///
/// 坚果云 href 是百分号编码的绝对路径（含 baseUrl 的 `/dav/` 前缀），例如
/// `/dav/%e6%88%91%e7%9a%84%e5%9d%9a%e6%9e%9c%e4%ba%91/a.json`。剥掉 [basePath]
/// 后剩下的就是「含 namespace 在内」的相对段——与 LocalFolderBackend 语义一致
/// （`list('entities')` 返回 `entities/...`）。比对在解码后进行，免疫 `%e6`
/// 小写/大写编码差异。
///
/// **返回中间结构而非 `RemoteObject`**：`RemoteObject` 定义在接口层
/// （sync_backend.dart），本文件是纯文本工具，不应反向依赖接口层。
/// 由 backend 负责组装。
///
/// 过滤规则：目录条目跳过（namespace 目录自身也是 collection）；
/// 不在 [basePath] 之下、恰为 [basePath] 根、在 namespace 前缀之外的条目跳过。
List<({String path, WebDavPropStatEntry entry})> resolveObjects({
  required List<WebDavPropStatEntry> entries,
  required String basePath,
  required String namespace,
}) {
  final baseDecoded = decodeSeg(basePath);
  final marker = baseDecoded.endsWith('/') ? baseDecoded : '$baseDecoded/';
  // namespace 前缀过滤：Depth:infinity 的 PROPFIND 语义上只回子树，但显式
  // 过滤与 LocalFolderBackend 行为一致，也防服务端越界返回。
  final nsSegments = namespace
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .toList();
  final nsPrefix = nsSegments.isEmpty
      ? ''
      : '${nsSegments.map(decodeSeg).join('/')}/';
  final out = <({String path, WebDavPropStatEntry entry})>[];
  for (final e in entries) {
    if (e.isDirectory) {
      continue; // 集合（目录）不是对象
    }
    final decH = decodeSeg(e.href);
    final idx = decH.indexOf(marker);
    if (idx < 0) {
      continue; // 不在 baseUrl 之下，防御性跳过
    }
    final rest = decH.substring(idx + marker.length);
    if (rest.isEmpty) {
      continue; // 是 baseUrl 根自身
    }
    if (nsPrefix.isNotEmpty && !rest.startsWith(nsPrefix)) {
      // nsPrefix 以 / 结尾：namespace 目录自身（'entities' 无尾斜杠）
      // 天然不匹配，无需单独排除。
      continue; // namespace 前缀之外（如 list('entities') 时的 other.json）
    }
    final relSegments = rest.split('/').where((s) => s.isNotEmpty).toList();
    if (relSegments.isEmpty) {
      continue;
    }
    out.add((path: relSegments.join('/'), entry: e));
  }
  return out;
}
