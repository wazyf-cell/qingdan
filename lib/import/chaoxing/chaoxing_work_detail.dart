/// 作业题目页（`/work/phone/doHomeWork`）的 HTML 解析：抽正文与附件名。
///
/// **来源声明**（AGENTS.md 禁止事项要求逐文件标注）：这条链路**不是**从油猴脚本
/// `扩展/作业列表.js` 抄的——那个脚本全文没有取题目详情的接口，它的「查看」就是
/// `window.open(getHomeworkLink(item))`（:5619）打开课程中间页。本文件的地址与
/// DOM 形状来自 2026-10-19 用模拟器上的真实会话逐跳抓下来的四份页面样本
/// （`stu-work` 列表页 → `android/mtaskmsgspecial` 确认页 → `doHomeWork` 题目页，
/// 含一份「已过时效」的信息提示页作反例），没有拷贝任何第三方代码。
///
/// 三跳是必需的：列表页 `li[data]` 里那条地址带的是 `enc_task`，打开只会得到
/// 一个「开始时间 / 截止时间 / 共 N 道题，确定？」的确认页；真正的题目页地址
/// 连它自己的 `enc` 都藏在确认页 `jump()` 那个字符串字面量里，服务端每次现算，
/// 客户端算不出来。
///
/// 题目页的骨架（真样本，去掉样式后）：
/// ```html
/// <div class="pad30">
///   <div><span class="focusSpan" aria-label="1. 简答题"></span>
///        <h2 class="titType">1. 简答题</h2></div>
///   <div class="ans-cc timuStyle fontLabel workWrap"><span aria-label="题干"></span>
///     <p>请完成附件要求的习题…</p>
///     <div class="editor-iframe"><iframe class="attach-iframe"
///          filename="第四次作业.docx" filetype="docx" …></div>
///   </div><div id="redioContent"></div>
/// </div>
/// ```
/// 附件是**一个 iframe**，浏览器里由 `insertCloud.html` 那段脚本再渲染成可点的
/// 下载卡片；我们只要它的 `filename`，正好符合「显示一个不可点的文件名」的要求。
library;

import 'chaoxing_html.dart';

/// 一道题：序号 + 题型（服务端原文，如「简答题」「其它」「单选题」）+ 正文 + 附件名。
class ChaoxingQuestion {
  const ChaoxingQuestion({
    required this.index,
    required this.type,
    required this.text,
    this.attachments = const <String>[],
    this.imageCount = 0,
  });

  final int index;
  final String type;

  /// 题干纯文本（段落之间用 `\n` 分隔）。
  final String text;

  /// 附件文件名，按页面出现顺序、已去重。**只给名字**，下载地址不带。
  final List<String> attachments;

  /// 题干里的图片张数：正文抽得出字，抽不出图，界面要如实说一句。
  final int imageCount;
}

/// 一份作业的正文。空列表 = 这一页没抽到题（已提交、已过时效、或页面改版）。
class ChaoxingWorkDetail {
  const ChaoxingWorkDetail(this.questions);

  final List<ChaoxingQuestion> questions;

  bool get isEmpty => questions.isEmpty;
}

class ChaoxingWorkPage {
  /// 确认页 `jump()` 里的题目页地址。页面写的是 `location.origin + _CP_ + '/work/…'`，
  /// 所以相对形态要拿**确认页自己的** origin 与 `_CP_` 拼回去，不能写死域名
  /// （超星有 mooc1 / mooc1-api 两个前端，写死会在其中一个上 404）。
  static String? parseWorkUrl(String confirmHtml, {required String entryUrl}) {
    final String html = unescapeHtml(confirmHtml);
    final String? abs = RegExp('''["'](https?://[^"']*?/work/phone/doHomeWork[^"']*?)["']''')
        .firstMatch(html)
        ?.group(1);
    if (abs != null) return abs;
    final String? rel = RegExp('''["'](/work/phone/doHomeWork[^"']*?)["']''')
        .firstMatch(html)
        ?.group(1);
    if (rel == null) return null;
    final String cp = RegExp('''_CP_\\s*=\\s*["']([^"']*)["']''')
            .firstMatch(html)
            ?.group(1) ??
        '/mooc-ans';
    final String origin = Uri.tryParse(entryUrl)?.origin ?? '';
    if (origin.isEmpty) return null;
    return '$origin$cp$rel';
  }

  static final RegExp _kHeader =
      RegExp('<h2[^>]*class="titType"[^>]*>([\\s\\S]*?)</h2>', caseSensitive: false);
  static final RegExp _kStem =
      RegExp('<div[^>]*class="ans-cc[^"]*"[^>]*>', caseSensitive: false);
  static final RegExp _kDiv = RegExp('<(/?)div\\b', caseSensitive: false);
  static final RegExp _kIframe =
      RegExp('<iframe[^>]*class="attach-iframe[^"]*"[^>]*>', caseSensitive: false);

  /// 抽不出题就返回 null（界面转真实网页兜底），**不返回一个空壳**：
  /// 「本页没有题」和「这一页我们读不懂」在界面上必须是同一句话——都不能假装成功。
  static ChaoxingWorkDetail? parse(String html) {
    final List<Match> stems = _kStem.allMatches(html).toList();
    if (stems.isEmpty) return null;
    final List<String> headers =
        _kHeader.allMatches(html).map((Match m) => htmlText(m.group(1)!)).toList();
    final List<ChaoxingQuestion> out = <ChaoxingQuestion>[];
    for (int i = 0; i < stems.length; i++) {
      final int? end = _divEnd(html, stems[i].end);
      final String inner =
          html.substring(stems[i].end, end ?? html.length);
      final String text = toPlainText(inner);
      final List<String> files = _files(inner);
      if (text.isEmpty && files.isEmpty) continue;
      final (int, String) numbered = _splitHeader(
          i < headers.length ? headers[i] : '', i + 1);
      out.add(ChaoxingQuestion(
        index: numbered.$1,
        type: numbered.$2,
        text: text,
        attachments: files,
        imageCount: '<img'.allMatches(inner).length,
      ));
    }
    return out.isEmpty ? null : ChaoxingWorkDetail(out);
  }

  /// 标题「1. 简答题」拆成 (1, 简答题)。服务端偶尔不带序号（真样本里
  /// `focusSpan` 与 `titType` 内容一致，但少数页面只有题型），所以序号缺失时
  /// 退回按出现顺序编号，不能把「1.」留在正文里显示成「1. 1. 简答题」。
  static (int, String) _splitHeader(String header, int fallbackIndex) {
    final Match? m = RegExp(r'^\s*(\d+)\s*[..、]\s*(.*)$').firstMatch(header);
    if (m == null) {
      return header.isEmpty
          ? (fallbackIndex, '')
          : (fallbackIndex, header.trim());
    }
    return (int.parse(m.group(1)!), m.group(2)!.trim());
  }

  static List<String> _files(String innerHtml) {
    final List<String> out = <String>[];
    for (final Match m in _kIframe.allMatches(innerHtml)) {
      final String name = attrOf(m.group(0)!, 'filename');
      if (name.isNotEmpty && !out.contains(name)) out.add(name);
    }
    return out;
  }

  /// 题干 HTML → 纯文本：段落边界换成换行，其余标签剥掉，实体最后还原
  /// （早一步还原会把 `&lt;p&gt;` 这种正文里的字面标签当成真标签剥掉）。
  static String toPlainText(String html) {
    String s = html.replaceAll(
        RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(
        RegExp(r'</(p|div|li|h\d|tr|blockquote)>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n· ');
    s = s.replaceAll(RegExp(r'</?div[^>]*>', caseSensitive: false), '\n');
    s = unescapeHtml(s.replaceAll(RegExp(r'<[^>]*>'), ' '));
    return s
        .split('\n')
        .map((String l) => l.replaceAll(RegExp(r'[\s\u00A0]+'), ' ').trim())
        .where((String l) => l.isNotEmpty)
        .join('\n');
  }

  /// 从 `<div …>` 之后开始做 div 配平，返回闭合 `</div>` 的起始下标。
  ///
  /// 判闭合只能比 `group(1) == '/'`，不能写 `!= null`：`<(/?)div` 那个可选组
  /// **永远参与匹配**（开标签上它是空串而不是 null），写成判 null 会把开标签
  /// 也当成闭合——第一层嵌套就提前收口，附件 iframe 正好在下一层里。
  static int? _divEnd(String html, int contentStart) {
    int depth = 1;
    for (final Match m in _kDiv.allMatches(html, contentStart)) {
      depth += m.group(1) == '/' ? -1 : 1;
      if (depth == 0) return m.start;
    }
    return null;
  }
}
