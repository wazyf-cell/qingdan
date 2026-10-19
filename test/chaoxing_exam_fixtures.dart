// 考试两页的 HTML 夹具（**构造**的，不是真实登录态抓的：本机的学习通会话已失效，
// 只有真机才能验证真实页面确实长这样）。
//
// 形状逐条照油猴脚本 `扩展/作业列表.js` 的选择器搭：卡片形态 `extractExams`
// :793-832、表格形态 `extractExamsFromTable` :832-908；字段值照用户 2026-10-19
// 贴的那条真实考试通知填：
//   课程名称：建模课 / 考试名称：第一次单元测验
//   开始时间：2026-10-11 08:00 / 结束时间：2026-10-11 22:00 / 考试形式：自主考试
// 「现在」固定在 kExamNow = 2026-10-19 12:00——那场测验那时**已经考完 8 天**，
// 判过期 / 不进待办列表 / 不进提醒快照都是正确行为（见两个 _test 文件）。
//
// 两个测试文件共用（解析器对账 + 提醒链路），所以按项目惯例单独成文，不是 `_test`
// 结尾，`flutter test` 不会直接执行它。
import 'package:qingdan/import/chaoxing/chaoxing_exam.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

final DateTime kExamNow = DateTime(2026, 10, 19, 12);

const Map<String, String> kExamCourses = <String, String>{
  '240000001': '课程丁',
  '240000002': '建模课',
};

/// 卡片形态四条：① 未交、还剩 23 小时 35 分 ② ks_02 图判过期（文字还写着
/// 「剩余3小时」，判过期的依据只能是那张图）③ ks_01 图但文字「已结束」
/// ④ 没有 ks_state，且 `data` 里没带 taskrefId。
const String kExamCards = '''
<div id="chaoxing-assignment-wrapper">
<ul class="ks_list">
  <li data="https://mooc1.chaoxing.com/exam-ans/exam/test/examcode/examnotes?taskrefId=88001&amp;courseId=240000001&amp;classId=160000002">
    <div class="ks_pic"><img src="https://x/ks_01.png"></div>
    <dl><dt>第一次阶段测验</dt><dd>剩余23小时35分</dd></dl>
    <span class="ks_state">未提交</span>
  </li>
  <li data="/exam-ans/exam/test/examcode/examnotes?taskrefId=88002&amp;courseId=240000002&amp;classId=160000003">
    <div class="ks_pic"><img src="https://x/ks_02.png"></div>
    <dl><dt>期末考查</dt><dd>剩余3小时</dd></dl>
    <span class="ks_state">待批阅</span>
  </li>
  <li data="https://mooc1.chaoxing.com/exam-ans/exam/test/examcode/examnotes?taskrefId=88004&amp;courseId=240000002&amp;classId=160000003">
    <div class="ks_pic"><img src="https://x/ks_01.png"></div>
    <dl><dt>文字写着已结束的开卷测验</dt><dd>已结束</dd></dl>
    <span class="ks_state">未提交</span>
  </li>
  <li data="https://mooc1.chaoxing.com/exam-ans/exam/test/examcode/examnotes?courseId=240000001&amp;classId=160000009">
    <div class="ks_pic"><img src="https://x/ks_01.png"></div>
    <dl><dt>缺 taskrefId 的测验</dt><dd>剩余2天0小时</dd></dl>
  </li>
</ul>
</div>
''';

/// 只有 `ul.ks_list`、没有外层 id 的形态（脚本 :794-795 的退路分支）。
const String kExamCardsNoWrapper = '''
<ul class="ks_list">
  <li data="https://x/y?taskrefId=88009&amp;courseId=240000001&amp;classId=160000002">
    <div class="ks_pic"><img src="https://x/ks_01.png"></div>
    <dl><dt>退路形态测验</dt><dd>剩余5小时</dd></dl>
    <span class="ks_state">未提交</span>
  </li>
</ul>
''';

/// 表格形态（`examcode/examlist` 页）：列序照脚本 :842-849。
/// ① 用户贴的那场（状态列已写「已结束」）② 还没开始的未来测验
/// ③ **状态列还写着「进行中」但结束时刻已过** ④ 只有 6 列 ⑤ 操作列没有 go()。
const String kExamTable = '''
<table class="dataTable"><tbody>
<tr class="dataTr">
  <td>1</td><td>第一次单元测验</td>
  <td>2026-10-11 08:00<br>2026-10-11 22:00</td>
  <td>120分钟</td><td>已结束</td><td>已完成</td><td>85.5</td><td>自主考试</td>
  <td><a href="#" onclick="go('https://mooc1.chaoxing.com/exam-ans/exam/test/examcode/examnotes?moocId=240000001&amp;clazzid=160000002&amp;examId=991&amp;refer=http%3A%2F%2Fmooc1.chaoxing.com%2Fexam-ans%2Fexam%2Ftest%2Fexamcode%2Fexamnotes%3FcourseId%3D240000001%26classId%3D160000002%26examId%3D991');return false;">查看</a></td>
</tr>
<tr class="dataTr">
  <td>2</td><td>数据结构</td>
  <td>2026-10-25 14:00 ~ 2026-10-25 16:00</td>
  <td>90分钟</td><td>未开始</td><td>未提交</td><td></td><td>自主考试</td>
  <td><a href="#" onclick="go('/exam-ans/exam/test/examcode/examnotes?moocId=777777&amp;clazzid=666666&amp;refer=http%3A%2F%2Fx%3FcourseId%3D240000002%26classId%3D160000003%26examId%3D992');return false;">前往考试</a></td>
</tr>
<tr class="dataTr">
  <td>3</td><td>状态没刷新的软工概论测验</td>
  <td>2026-10-18 08:00 至 2026-10-18 22:00</td>
  <td>60分钟</td><td>进行中</td><td>未提交</td><td>---分</td><td>自主考试</td>
  <td><a href="#" onclick="go('https://x/y?examId=993&amp;clazzid=160000004&amp;moocId=240000003');return false;">查看</a></td>
</tr>
<tr class="dataTr">
  <td>4</td><td>列数不足的行</td><td>2026-10-20 08:00</td><td>60分钟</td>
  <td>进行中</td><td>未提交</td>
</tr>
<tr class="dataTr">
  <td>5</td><td>没有可解析链接的测验</td><td>2026-10-30 10:00</td><td>45分钟</td>
  <td>进行中</td><td>待批阅</td><td>---</td><td>闭卷</td>
  <td><a href="#">详情</a></td>
</tr>
</tbody></table>
''';

List<ChaoxingTask> examCards([Map<String, String> names = kExamCourses]) =>
    ChaoxingExam.parseCards(kExamCards, courseNames: names, now: kExamNow);

List<ChaoxingTask> examTable() =>
    ChaoxingExam.parseTable(kExamTable, courseNames: kExamCourses, now: kExamNow);

ChaoxingTask examById(List<ChaoxingTask> l, String id) =>
    l.singleWhere((ChaoxingTask t) => t.id == id);
