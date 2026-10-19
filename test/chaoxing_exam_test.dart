// 学习通「考试」两条解析路径的字段对账（2026-10-19 接上考试数据源）。
// 夹具与「现在是几点」在 `chaoxing_exam_fixtures.dart`；提醒链路在
// chaoxing_exam_notify_test.dart，界面在 chaoxing_exam_tab_test.dart。
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/chaoxing/chaoxing_exam.dart';
import 'package:qingdan/import/chaoxing/chaoxing_links.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_exam_fixtures.dart';

void main() {
  group('卡片形态 ul.ks_list（脚本 extractExams :793-832）', () {
    test('四条都解析到，标题/类型/来源/状态/课程名各归其位', () {
      final List<ChaoxingTask> l = examCards();
      expect(l.length, 4);
      final ChaoxingTask a = examById(l, '88001');
      expect(a.title, '第一次阶段测验');
      expect(a.kind, '考试');
      expect(a.source, ChaoxingSource.exam);
      expect(a.examId, '88001');
      expect(a.courseId, '240000001');
      expect(a.clazzId, '160000002', reason: ':825 读的就是 classId');
      expect(a.serverStatus, '未提交');
      expect(a.serverDone, isFalse);
      expect(a.ongoing, isTrue);
      expect(a.stateAt(kExamNow, done: false), ChaoxingTaskState.todo);
      expect(a.key, '240000001|88001');
      // 这一页没有课程名列：回查课程表补全，不吃页面。
      expect(a.courseName, '课程丁');
    });

    test('dd 的相对时间 = 抓取时刻 + 剩余，推成绝对 dueAt；没有开始时间', () {
      final ChaoxingTask a = examById(examCards(), '88001');
      expect(a.dueAt, kExamNow.add(const Duration(hours: 23, minutes: 35)));
      expect(a.startAt, isNull);
    });

    test('data 是 /开头的相对地址也认（脚本 :819 补 origin，我们只要 query）', () {
      final ChaoxingTask b = examById(examCards(), '88002');
      expect(b.courseId, '240000002');
      expect(b.clazzId, '160000003');
    });

    test('img src 含 ks_02 → 判过期（这一行的文字还写着「剩余3小时」）', () {
      final ChaoxingTask b = examById(examCards(), '88002');
      expect(b.ongoing, isFalse,
          reason: '判过期的唯一依据是 ks_02 那张已截止图（:813），改坏了这条要红');
      expect(b.dueAt, kExamNow.add(const Duration(hours: 3)),
          reason: '页面给的剩余照抄，但条目已经关掉');
      expect(b.serverStatus, '待批阅');
      expect(b.serverDone, isTrue, reason: '扩展把待批阅也当已完成（:828 / :5674）');
      expect(b.stateAt(kExamNow, done: false), ChaoxingTaskState.done);
    });

    test('ks_01 图但 dd 写「已结束」→ 也判过期，且推不出截止时刻', () {
      final ChaoxingTask e = examById(examCards(), '88004');
      expect(e.ongoing, isFalse, reason: '文字形态的过期（脚本 :3272 / :885 同义）');
      expect(e.dueAt, isNull, reason: '「已结束」里没有数字，不编一个截止时刻');
      expect(e.serverStatus, '未提交');
      expect(e.serverDone, isFalse);
      expect(e.stateAt(kExamNow, done: false), ChaoxingTaskState.ended);
    });

    test('没有 ks_state → serverStatus 为 null；缺 taskrefId → id 用标题兜', () {
      final ChaoxingTask c = examById(examCards(), '缺 taskrefId 的测验');
      expect(c.serverStatus, isNull);
      expect(c.id, '缺 taskrefId 的测验');
      expect(c.examId, isNull, reason: 'id 里的标题兜底不能当 examId 用（:1440）');
      // 「剩余2天0小时」= 2 天整，分钟位是 0 也照样认。
      expect(c.dueAt, kExamNow.add(const Duration(days: 2)));
      expect(detailUrlOf(c), isNull, reason: '没有 examId 就不拼地址');
    });

    test('回查不到课程名时用脚本自己的占位「考试课程」', () {
      expect(
          ChaoxingExam.parseCards(kExamCards,
                  courseNames: const <String, String>{}, now: kExamNow)
              .first
              .courseName,
          ChaoxingExam.kUnknownCourse);
    });

    test('没有外层 #chaoxing-assignment-wrapper 时也解析（:795 的退路）', () {
      final List<ChaoxingTask> l = ChaoxingExam.parseCards(kExamCardsNoWrapper,
          courseNames: const <String, String>{}, now: kExamNow);
      expect(l.single.title, '退路形态测验');
      expect(l.single.dueAt, kExamNow.add(const Duration(hours: 5)));
    });

    test('ks_list 之外没有考试行时返回空，不抛', () {
      expect(
          ChaoxingExam.parseCards('<ul class="nav"><li><p>作业</p></li></ul>',
              courseNames: const <String, String>{}, now: kExamNow),
          isEmpty);
    });
  });

  group('表格形态 table.dataTable tr.dataTr（脚本 :832-908）', () {
    test('列逐格对号：标题/开始/结束/时长/状态/形式/分数', () {
      final ChaoxingTask a = examById(examTable(), '991');
      expect(a.title, '第一次单元测验');
      expect(a.startAt, DateTime(2026, 10, 11, 8, 0));
      expect(a.dueAt, DateTime(2026, 10, 11, 22, 0));
      expect(a.durationMinutes, 120);
      expect(a.examForm, '自主考试');
      expect(a.examScore, '85.5');
      expect(a.serverStatus, '已完成', reason: ':884 作答状态优先于考试状态');
      expect(a.serverDone, isTrue);
      expect(a.ongoing, isFalse);
    });

    test('三个 id 从 go() 的 refer 里解出，拼出 examnotes 详情地址', () {
      final ChaoxingTask a = examById(examTable(), '991');
      expect(a.courseId, '240000001');
      expect(a.clazzId, '160000002');
      expect(a.examId, '991');
      final String? url = detailUrlOf(a);
      expect(url, isNotNull);
      expect(
          url,
          contains(
              'mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examnotes'));
      expect(url, contains('courseId=240000001'));
      expect(url, contains('classId=160000002'));
      expect(url, contains('examId=991'));
    });

    test('refer 解不动时退回 moocId / clazzid / examId 直正则（:873-878）', () {
      final ChaoxingTask c = examById(examTable(), '993');
      expect(c.courseId, '240000003');
      expect(c.clazzId, '160000004');
      expect(c.examId, '993');
      expect(c.courseName, '考试课程', reason: '回查不到就占位，不编课程名');
    });

    test('refer 与外层 moocId 同时存在时取 refer（:869-870 的优先序）', () {
      final ChaoxingTask b = examById(examTable(), '992');
      expect(b.courseId, '240000002', reason: '外层那个 moocId=777777 是退路，不是首选');
      expect(b.clazzId, '160000003');
      expect(b.examId, '992');
    });

    test('未到开始的考试 = 未开始，且有绝对截止（提醒排得上）', () {
      final ChaoxingTask b = examById(examTable(), '992');
      expect(b.startAt, DateTime(2026, 10, 25, 14, 0));
      expect(b.dueAt, DateTime(2026, 10, 25, 16, 0));
      expect(b.durationMinutes, 90);
      expect(b.ongoing, isTrue);
      expect(b.stateAt(kExamNow, done: false), ChaoxingTaskState.notStarted);
      expect(b.examScore, '---', reason: '分数列为空时用脚本 :848 的缺省串');
    });

    test('状态列写「进行中」但结束时刻已过 → 仍判已过期', () {
      final ChaoxingTask c = examById(examTable(), '993');
      expect(c.serverStatus, '未提交', reason: ':884 作答状态优先，所以这里不是「进行中」');
      expect(c.ongoing, isFalse, reason: '10-18 22:00 已过，不能再当还开着');
      expect(c.stateAt(kExamNow, done: false), ChaoxingTaskState.ended);
    });

    test('不足 9 列的行整行丢掉（:840）', () {
      expect(examTable().length, 4);
      expect(examTable().map((ChaoxingTask t) => t.title),
          isNot(contains('列数不足的行')));
    });

    test('操作列没有 go() 也没有可解析 href → examId 缺省、详情如实不可用', () {
      final ChaoxingTask d = examTable().last;
      expect(d.id, '没有可解析链接的测验');
      expect(d.examId, isNull);
      expect(detailUrlOf(d), isNull);
      expect(d.serverStatus, '待批阅');
      expect(d.serverDone, isTrue);
      // 时间列只有一个时刻：分不清那是开始还是结束，两个都不填（不猜截止）。
      expect(d.startAt, isNull);
      expect(d.dueAt, isNull);
    });

    test('没有 tr.dataTr 的页面返回空，不抛', () {
      expect(
          ChaoxingExam.parseTable(
              '<table class="dataTable"><tr><td>1</td></tr></table>',
              courseNames: const <String, String>{},
              now: kExamNow),
          isEmpty);
    });
  });

  group('两条路径互不污染', () {
    test('key 都是 courseId|examId（隐藏项存的键，形状不能改）', () {
      expect(examById(examCards(), '88001').key, '240000001|88001');
      expect(examById(examTable(), '991').key, '240000001|991');
    });

    test('同一场考试两页都列出时按 key 去掉一份', () {
      final List<ChaoxingTask> both = <ChaoxingTask>[
        ...ChaoxingExam.parseCards(
            '<ul class="ks_list"><li data="https://x?taskrefId=992&amp;'
            'courseId=240000002&amp;classId=160000003"><div class="ks_pic">'
            '<img src="ks_01.png"></div><dl><dt>数据结构</dt><dd>剩余6天</dd></dl>'
            '<span class="ks_state">未提交</span></li></ul>',
            courseNames: const <String, String>{},
            now: kExamNow),
        examById(examTable(), '992'),
      ];
      expect(both.map((ChaoxingTask t) => t.key).toSet(), <String>{'240000002|992'});
      expect(ChaoxingTask.dedupe(both).length, 1);
    });
  });
}
