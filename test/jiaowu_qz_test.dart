import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/import/jiaowu/jiaowu_qz.dart';

/// 夹具形状取自真机抓取的一页强智课表（简表 div + 悬停详情 div 并存、同格两节课
/// 用 `------` 分隔、中文节次标签含「第十一、十二节」这种带顿号的形式、末尾还有
/// 「备注」图例行）；**课名、教师、教学楼/教室、通知单编号、班级段全部换成合成值**
/// （仓库是 public，那一页属于个人数据）。钉的是 DOM 的**位置与格式**——解析器按
/// `title=` 认字段、按行首中文节次定节数，所以这些位置一位都没动。
const String kSample = '''
<table border="1" id="timetable">
 <tbody><tr>
  <th width="70" height="28" align="center">&nbsp;</th>
  <th width="123" height="28" align="center">星期一</th>
  <th width="123" height="28" align="center">星期二</th>
 </tr>
 <tr>
  <th width="70" height="28" align="center">第一二节&nbsp;</th>
  <td width="123" height="28" align="center" valign="top">
   <div id="91D9-1-1" style="display: none" class="kbcontent1"><div class="item-box"><img src="/jsxsd/jsxx/ewmck?id=1"></div><font onmouseover="kbtc(this)" onmouseout="kbot(this)">课程甲</font><br><font title="周次(节次)">1-6,8-11(周)</font><br><font title="教室">A101</font><br><font name="wkxx" style="display:none;"><br></font><br>----------------------<br><font>课程乙</font><br><font title="周次(节次)">1-8(周)</font><br><font title="教室">A202</font><br><font name="wkxx"></font><br></div>
   <div id="91D9-1-1-tip" class="kbcontent2"><font>课程甲</font><br><font title="教师">张老师</font><br><font title="周次(节次)">1-6,8-11(周)[01-02节]</font><br><font title="教学楼" name="jxlmc">【测试楼A栋】</font><br><font title="教室">A101</font><br><font title="通知单编号" name="tzdbh">通知单编号：1234567</font><br><font name="wkxx"></font><br><font title="班级" name="ktmcstr">班级：[000001-000003]班</font><br></div>
  </td>
  <td width="123" height="28" align="center" valign="top">
   <font>课程丙(重)</font><br><font title="周次(节次)">4-16(周)</font><br><font title="教室">B303</font><br><font title="教师">李老师</font><br>
  </td>
 </tr>
 <tr>
  <th width="70" height="28" align="center">第三四节&nbsp;</th>
  <td width="123">&nbsp;</td>
  <td width="123"><font>课程丙(重)</font><br><font title="周次(节次)">4-16(周)</font><br><font title="教室">B303</font><br><font title="教师">李老师</font><br></td>
 </tr>
 <tr>
  <th width="70" height="28" align="center">第十一、十二节&nbsp;</th>
  <td width="123"><font>讲座</font><br><font title="周次(节次)">3(周)</font><br><font title="教室">报告厅</font><br></td>
  <td width="123">&nbsp;</td>
 </tr>
 <tr>
  <th width="70" height="28" align="center">备注:</th>
  <td width="123">无课表课程 有课表课程</td>
  <td width="123"></td>
 </tr>
</tbody></table>
''';

List<String> rowOf(List<List<String>> rows, String name, String day) => rows
    .firstWhere((List<String> r) => r[0] == name && r[1] == day)
    .toList();

void main() {
  group('强智课表页解析', () {
    final List<List<String>> rows = parseQzTimetable(kSample).rows;

    test('表头是列猜测器认得的那七个名字，用户零重映射', () {
      expect(rows.first,
          <String>['课程名称', '星期', '开始节数', '结束节数', '老师', '地点', '周数']);
    });

    test('中文节次标签 → 起止节数（含「第十一、十二节」带顿号的形式）', () {
      expect(rowOf(rows, '课程甲', '1')[2], '1');
      expect(rowOf(rows, '课程甲', '1')[3], '2');
      expect(rowOf(rows, '讲座', '1')[2], '11');
      expect(rowOf(rows, '讲座', '1')[3], '12');
    });

    test('列序 → 星期', () {
      expect(rowOf(rows, '课程丙(重)', '2')[1], '2');
    });

    test('同格多节课都收进来', () {
      expect(rowOf(rows, '课程乙', '1')[4], isEmpty); // 详情里没有它 → 老师留空
      expect(rowOf(rows, '课程乙', '1')[5], 'A202');
    });

    test('悬停详情补老师，并剥掉周次里的 [01-02节] 后缀', () {
      final List<String> r = rowOf(rows, '课程甲', '1');
      expect(r[4], '张老师');
      expect(r[6], '1-6,8-11(周)');
      expect(r[6], isNot(contains('[')));
    });

    test('教学楼/通知单编号/班级这类没有对应字段的条目不产生垃圾行', () {
      expect(rows.length, 5); // 表头 + 4 节课
      expect(rows.any((List<String> r) => r[0].contains('通知单编号')), isFalse);
      expect(rows.any((List<String> r) => r[0].contains('班级')), isFalse);
    });

    test('「备注」图例行不产出条目', () {
      expect(rows.any((List<String> r) => r[0].contains('课表课程')), isFalse);
    });

    test('同一节课出现在相邻节次行 → 并成一条（真机把跨节课散成多行的 bug）', () {
      final List<String> merged = rowOf(rows, '课程丙(重)', '2');
      expect(merged[2], '1');
      expect(merged[3], '4');
      expect(
          rows.where((List<String> r) => r[0] == '课程丙(重)').length, 1);
    });
  });

  group('找不到课表表时', () {
    test('返回空表（界面据此提示「请先导航到课表页」）', () {
      expect(parseQzTimetable('<html><body><p>登录页</p></body></html>').isEmpty,
          isTrue);
    });

    test('「第九十节」解析成 9-10 节', () {
      final List<List<String>> rows = parseQzTimetable('''
<table id="timetable"><tr><th>&nbsp;</th><th>星期一</th></tr>
<tr><th>第九十节</th><td><font>体育</font><br><font title="周次(节次)">1-8(周)</font><br><font title="教室">操场</font><br></td></tr>
</table>''').rows;
      expect(rows.last[2], '9');
      expect(rows.last[3], '10');
    });
  });
}
