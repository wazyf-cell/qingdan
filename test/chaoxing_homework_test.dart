import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/import/chaoxing/chaoxing_homework.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

/// 夹具形状取自 2026-10-17 真机探针抓回的 `work/stu-work` 页面片段，
/// **但作业名、三个 id、activeId 全部换成合成值**（仓库是 public，
/// 真实待办清单属于个人数据）。三种形态：带 courseId 的未提交、无红点的未提交、
/// 无 courseId 且无剩余时间的；另补已完成与已过期两条对照。
const String kPage = '''
<ul class="nav">
<li onclick="goTask(this);" data="https://mooc1-api.chaoxing.com/mooc-ans/android/mtaskmsgspecial?taskrefId=88000001&amp;msgId=0&amp;courseId=240000001&amp;userId=1&amp;clazzId=160000001&amp;type=work&amp;enc_task=f72">
  <span class="spanImg"><img src=x><i class="redPoint"></i></span>
  <div role="option">
    <p aria-hidden="true">第一章作业：项目计划书</p>
    <span  class="status"  aria-hidden="true">未提交</span>
    <span aria-hidden="true">《课程甲...》</span>
    <span class="fr" aria-hidden="true">剩余241小时</span>
    <span aria-label="作业名称第一章作业"></span>
  </div>
</li>
<li onclick="goTask(this);" data="https://mooc1-api.chaoxing.com/mooc-ans/android/mtaskmsgspecial?taskrefId=88000002&amp;courseId=240000002&amp;clazzId=160000002&amp;type=work">
  <span class="spanImg"><img src=x></span>
  <div role="option">
    <p aria-hidden="true">第二章作业：测试应用</p>
    <span  class="status"  aria-hidden="true">未提交</span>
    <span aria-hidden="true">《课程乙...》</span>
    <span class="fr" aria-hidden="true">剩余120小时55分钟</span>
  </div>
</li>
<li onclick="goTask(this);" data="https://mobilelearn.chaoxing.com/widget/renwu/proxyRenwuAttendUrl?activeId=2000000000001&amp;returnType=10">
  <span class="spanImg"><img src=x><i class="redPoint"></i></span>
  <div role="option">
    <p aria-hidden="true">课程大作业</p>
    <span  class="status"  aria-hidden="true">未提交</span>
    <span aria-hidden="true">《课程乙...》</span>
  </div>
</li>
<li onclick="goTask(this);" data="https://mooc1-api.chaoxing.com/mooc-ans/android/mtaskmsgspecial?taskrefId=9&amp;courseId=240000001&amp;type=work">
  <div role="option">
    <p>第三章实验</p>
    <span class="">已完成</span>
    <span>《课程甲...》</span>
    <span class="fr">剩余97小时</span>
  </div>
</li>
<li onclick="goTask(this);" data="https://mooc1-api.chaoxing.com/mooc-ans/android/mtaskmsgspecial?taskrefId=10&amp;courseId=240000001&amp;type=work">
  <div role="option">
    <p>过期作业</p>
    <span class="status">未提交</span>
    <span>《课程甲...》</span>
    <span class="fr">已过期</span>
  </div>
</li>
</ul>
''';

final DateTime kNow = DateTime(2026, 10, 17, 21, 59);

List<ChaoxingTask> parse() => ChaoxingHomework.parsePage(kPage,
    courseNames: const <String, String>{'240000001': '课程甲2026-2027'},
    now: kNow);

void main() {
  group('作业页解析（对照扩展成品界面）', () {
    test('五条 li 全解析到，字段各归其位', () {
      final List<ChaoxingTask> tasks = parse();
      expect(tasks.length, 5);
      final ChaoxingTask first = tasks.first;
      expect(first.id, '88000001');
      expect(first.title, '第一章作业：项目计划书');
      expect(first.kind, '作业');
      expect(first.serverStatus, '未提交');
      expect(first.serverDone, isFalse);
      expect(first.unread, isTrue);
      // 课程名用 courseId 回查课程表补全，不吃页面上被截断的《课程甲...》。
      expect(first.courseName, '课程甲2026-2027');
    });

    test('截止时间 = 抓取时刻 + 「剩余X小时Y分钟」', () {
      final List<ChaoxingTask> tasks = parse();
      expect(tasks[0].dueAt, kNow.add(const Duration(hours: 241)));
      expect(tasks[1].dueAt,
          kNow.add(const Duration(hours: 120, minutes: 55)));
    });

    test('没有红点 = 已打开过；没有 .fr = 无截止时间', () {
      final List<ChaoxingTask> tasks = parse();
      expect(tasks[1].unread, isFalse);
      expect(tasks[2].dueAt, isNull);
      // 无 courseId 的条目退回页面上的截断课程名。
      expect(tasks[2].courseName, '课程乙...');
      expect(tasks[2].id, '2000000000001');
    });

    test('状态 span 不带 status 类 = 已提交（脚本 :773 的同一条规则）', () {
      final ChaoxingTask done = parse()[3];
      expect(done.serverStatus, '已完成');
      expect(done.serverDone, isTrue);
      expect(done.stateAt(kNow, done: false), ChaoxingTaskState.done);
    });

    test('「已过期」判为已结束且不给截止时间', () {
      final ChaoxingTask expired = parse()[4];
      expect(expired.ongoing, isFalse);
      expect(expired.dueAt, isNull);
      expect(expired.stateAt(kNow, done: false), ChaoxingTaskState.ended);
    });

    test('未提交且未过期 = 待办', () {
      expect(parse()[0].stateAt(kNow, done: false), ChaoxingTaskState.todo);
    });

    // M6B §B3：`li[data]` 里就带 clazzId，早先没读出来 → 详情 URL 拼不出来。
    // 这条断言在未改解析器时必须红（旧代码解析完 clazzId 恒为 null）。
    test('clazzId 从同一串 data 里读出来（拼详情 URL 用）', () {
      final List<ChaoxingTask> tasks = parse();
      expect(tasks[0].clazzId, '160000001');
      expect(tasks[1].clazzId, '160000002');
      // 第三条是 proxyRenwuAttendUrl，data 里没有 clazzId → 缺省而不是猜。
      expect(tasks[2].clazzId, isNull);
      // 读它不能改 key 的形状：隐藏项 prefs 里存的就是这个键。
      expect(tasks[0].key, '240000001|88000001');
    });
  });
}
