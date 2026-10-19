/// 作业题目页解析（`chaoxing_work_detail.dart`）。
///
/// 夹具是 2026-10-19 用真实会话从超星抓下来的题目页**形状**，课程名、题号、
/// 附件名、objectid 全部换成假值——钉的是 DOM 结构，不是任何人的真实作业。
///
/// 为什么值得单独一份测试：这条链路没有任何官方文档，参考的油猴脚本也完全
/// 没有它（脚本只 `window.open` 那个课程中间页）。形状一改（超星一年改几轮）
/// 界面就会静默退回网页兜底——测试至少能在形状变化时先红一次，而不是让用户
/// 某天发现「详情又变成网页了」。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/chaoxing/chaoxing_work_detail.dart';

/// 真样本骨架：标题在 `h2.titType`，题干在 `div.ans-cc…`，附件是题干里的一个
/// `iframe.attach-iframe[filename]`，题干 div 之后紧跟 `div#redioContent`。
String _oneQuestion(String header) => '''
<div class="pad30">
  <div><span class="focusSpan" aria-label="$header"></span>
       <h2 class="titType" aria-hidden="true">
         $header
       </h2></div>
  <div class="ans-cc timuStyle fontLabel workWrap"><span aria-label="题干"></span>
    <p style="text-align:center">第一行题干</p>
    <p>第二行：把 &lt;p&gt; 当字面写在这里，还有 A&amp;B 这样的与号。</p>
    <div class="editor-iframe"><iframe frameborder="0" scrolling="no"
      src="/ananas/common-modules/attachment/insertCloud.html"
      class="attach-iframe" module="insertAttach" objectid="deadbeef"
      filename="第三章习题.docx" filetype="docx" name="x"></iframe></div>
  </div><div id="redioContent">这段不属于题干</div>
</div>
<div class="Briefanswer"><div id="ananas-editor-answer">答题区</div></div>''';

String workPage(List<String> headers) =>
    '<html><head><title>第三次作业</title></head><body>'
    '${headers.map(_oneQuestion).join('\n')}'
    '</body></html>';

void main() {
  test('单题：序号、题型、正文、附件名各归各位', () {
    final ChaoxingWorkDetail? d = ChaoxingWorkPage.parse(workPage(<String>['1. 简答题']));
    expect(d, isNotNull);
    expect(d!.questions.length, 1);
    final ChaoxingQuestion q = d.questions.single;
    expect(q.index, 1);
    expect(q.type, '简答题');
    expect(q.text, contains('第一行题干'));
    expect(q.text, contains('第二行'));
    expect(q.attachments, <String>['第三章习题.docx']);
    expect(q.imageCount, 0);
  });

  test('正文是纯文本：实体还原、字面 &lt;p&gt; 不被当成标签吃掉', () {
    final ChaoxingQuestion q =
        ChaoxingWorkPage.parse(workPage(<String>['1. 简答题']))!.questions.single;
    // 还原放在剥标签之后，所以题干里写着的字面 `&lt;p&gt;` 会以 `<p>` 这几个
    // **字符**留下；要是先还原再剥，它就被当成真标签删掉了（题干少一截没人发现）。
    expect(q.text, contains('<p>'), reason: '字面 <p> 要原样显示');
    expect(q.text, contains('A&B'), reason: '&amp; 要还原成 &');
    expect(q.text.split('\n').length, greaterThan(1), reason: '两个 <p> 要是两行');
  });

  test('题干 div 里的嵌套结构不会把后面的区块一起吞进来', () {
    final ChaoxingQuestion q =
        ChaoxingWorkPage.parse(workPage(<String>['1. 简答题']))!.questions.single;
    expect(q.text, isNot(contains('这段不属于题干')),
        reason: 'ans-cc 里嵌了 editor-iframe，配平写错就会多吞一个兄弟块');
    expect(q.text, isNot(contains('答题区')));
  });

  test('多题：按出现顺序编号，题型分别取', () {
    final ChaoxingWorkDetail d = ChaoxingWorkPage
        .parse(workPage(<String>['1. 单选题', '2. 简答题']))!;
    expect(d.questions.map((ChaoxingQuestion q) => q.index), <int>[1, 2]);
    expect(d.questions.map((ChaoxingQuestion q) => q.type), <String>['单选题', '简答题']);
  });

  test('标题没带序号时按出现顺序补号，不把「1.」重复显示', () {
    final ChaoxingWorkDetail d = ChaoxingWorkPage.parse(
        workPage(<String>['简答题']).replaceAll('1. 简答题', '简答题'))!;
    expect(d.questions.single.index, 1);
    expect(d.questions.single.type, '简答题');
  });

  test('「已过时效」那种信息提示页：抽不出题就返回 null，不给空壳', () {
    expect(
        ChaoxingWorkPage.parse(
            '<html><head><title> 信息提示</title></head><body><p>已过时效，不能操作!</p></body></html>'),
        isNull);
  });

  test('题目页地址：相对形态按确认页自己的 origin 与 _CP_ 拼', () {
    const String confirm = '''
<script>_HOST_ = "//mooc1-api.chaoxing.com"; _CP_ = "/mooc-ans";</script>
<script>function jump(){ var url = location.origin + _CP_ +
 '/work/phone/doHomeWork?courseId=1&amp;workId=2&amp;enc=abc' + '&' + x; }</script>''';
    expect(
        ChaoxingWorkPage.parseWorkUrl(confirm,
            entryUrl: 'https://mooc1-api.chaoxing.com/mooc-ans/android/mtaskmsgspecial?a=1'),
        'https://mooc1-api.chaoxing.com/mooc-ans'
        '/work/phone/doHomeWork?courseId=1&workId=2&enc=abc');
  });

  test('题目页地址：绝对形态原样用；确认页里没有就返回 null', () {
    expect(
        ChaoxingWorkPage.parseWorkUrl(
            '''var u = "https://mooc1.chaoxing.com/work/phone/doHomeWork?enc=9";''',
            entryUrl: 'https://mooc1-api.chaoxing.com/x?a=1'),
        'https://mooc1.chaoxing.com/work/phone/doHomeWork?enc=9');
    expect(
        ChaoxingWorkPage.parseWorkUrl('<html>没有链接</html>',
            entryUrl: 'https://mooc1-api.chaoxing.com/x'),
        isNull);
  });
}
