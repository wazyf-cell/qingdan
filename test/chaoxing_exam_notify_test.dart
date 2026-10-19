// 考试接进「提醒快照 / 状态机 / 页签 / 筛选」这四条链路（2026-10-19）。
//
// 判据用那场已结束的考试：`第一次单元测验`（**考试名取自真实通知的形状，
// 但去掉年级与专业；仓库是 public，开课班名属于个人数据**），
// 开始 2026-10-11 08:00、结束 **2026-10-11 22:00**，而「现在」固定在
// kExamNow = 2026-10-19 12:00——**它那时已经考完 8 天了**。正确行为是：状态=已结束、
// 不进提醒快照、不计入角标、开「仅看未完成」后从列表消失。这几条就是
// 「结束时间已过 → 不进列表」的可执行版本（界面上还剩哪一格见
// chaoxing_exam_tab_test.dart；解析字段见 chaoxing_exam_test.dart）。
//
// 一半用例直接吃 `chaoxing_exam_fixtures.dart` 的**解析结果**（端到端），
// 一半用 harness 的 cxExam 单独搭某一种排除条件。
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_grouping.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';
import 'package:qingdan/notify/reminder_plan.dart';

import 'chaoxing_exam_fixtures.dart';
import 'chaoxing_harness.dart';

final DateTime kNow = kExamNow;

/// 已结束的那场：结束时刻已过 8 天。
ChaoxingTask ended() => cxExam('991',
    courseId: '240000001',
    examId: '991',
    title: '第一次单元测验',
    startAt: DateTime(2026, 10, 11, 8, 0),
    dueAt: DateTime(2026, 10, 11, 22, 0),
    ongoing: false,
    status: '已完成');

/// 还没开始的下一场。
ChaoxingTask upcoming() => cxExam('992',
    courseId: '240000002',
    clazzId: '160000003',
    examId: '992',
    title: '期中测验',
    startAt: DateTime(2026, 10, 25, 14, 0),
    dueAt: DateTime(2026, 10, 25, 16, 0),
    status: '未提交');

/// 今天 20:00 截止、已经在可交窗口内的那场。
ChaoxingTask open() => cxExam('993',
    courseId: '240000003',
    clazzId: '160000004',
    examId: '993',
    title: '第二次单元测验',
    startAt: kNow.subtract(const Duration(hours: 2)),
    dueAt: kNow.add(const Duration(hours: 8)),
    status: '未提交');

List<ChaoxingSnapshotItem> snap(List<ChaoxingTask> l,
        {Set<String> hidden = const <String>{}}) =>
    chaoxingSnapshotOf(l, hidden, kNow);

ChaoxingTask hw2() => cxHomework('1', title: '第四次作业', dueAt: kNow);

void main() {
  group('考试进提醒快照（chaoxingSnapshotOf）', () {
    test('dueAt = 结束时间：没考完的考试正常进快照', () {
      final List<ChaoxingSnapshotItem> kept = snap(<ChaoxingTask>[open()]);
      expect(kept.single.key, '240000003|993');
      expect(kept.single.title, '第二次单元测验');
      expect(kept.single.dueAt, kNow.add(const Duration(hours: 8)),
          reason: '提醒必须按结束时刻排：那时还没交就再也交不了了');
    });

    test('结束时间已过的考试不进快照——这是正确行为，不是没生效', () {
      expect(snap(<ChaoxingTask>[ended()]), isEmpty);
      expect(ended().stateAt(kNow, done: false), ChaoxingTaskState.ended);
    });

    test('还没开始的考试也进快照（提前量排不排由规划器判）', () {
      expect(snap(<ChaoxingTask>[upcoming()]).single.key, '240000002|992');
    });

    test('已交 / 待批阅 / 无截止 / 已隐藏的考试都不进快照', () {
      final DateTime future = kNow.add(const Duration(hours: 3));
      expect(
          snap(<ChaoxingTask>[
            cxExam('d',
                examId: 'd', dueAt: future, status: '已完成', serverDone: true),
            cxExam('p',
                examId: 'p', dueAt: future, status: '待批阅', serverDone: true),
            cxExam('n', examId: 'n', status: '未提交'), // 没有截止时刻
          ]),
          isEmpty,
          reason: '前两条按 :828 已算交过，最后一条排不出时间');
      expect(
          snap(<ChaoxingTask>[open(), upcoming()],
                  hidden: <String>{'240000003|993'})
              .map((ChaoxingSnapshotItem i) => i.key),
          <String>['240000002|992'],
          reason: '隐藏是设备本地便签，只挡这一台设备的提醒');
    });

    test('端到端：整张表格页解析出来只有下一场进快照', () {
      expect(snap(examTable()).map((ChaoxingSnapshotItem i) => i.key),
          <String>['240000002|992'],
          reason: '991 已考完、993 状态没刷新但已过点、最后一条没有截止');
    });

    test('端到端：整张卡片页只有还没到期的两条进快照', () {
      expect(
          snap(examCards()).map((ChaoxingSnapshotItem i) => i.key),
          <String>['240000001|88001', '240000001|缺 taskrefId 的测验'],
          reason: '88002 是 ks_02、88004 文字「已结束」（推不出截止），都进不来');
    });
  });

  test('结束时刻已过的考试不算待办，也不在有效窗口内', () {
    expect(
        <ChaoxingTask>[ended(), open(), upcoming()]
            .where((ChaoxingTask t) =>
                t.stateAt(kNow, done: false) == ChaoxingTaskState.todo)
            .map((ChaoxingTask t) => t.id),
        <String>['993']);
    expect(ended().inWindow(kNow), isFalse);
    expect(ended().isValidAt(kNow), isFalse);
  });

  group('考试不污染别的页签与合并', () {
    test('两个考试页给出的同名考试不会被 mergeRepublished 相消', () {
      final ChaoxingTask a = cxExam('991',
          courseId: '240000002', examId: '991', title: '期中测验');
      final ChaoxingTask b = cxExam('992',
          courseId: '240000002', examId: '992', title: '期中测验');
      expect(ChaoxingTask.mergeRepublished(<ChaoxingTask>[a, b]).length, 2,
          reason: '同课同名的两场都是真考试（重发相消只管课堂活动）');
      expect(
          ChaoxingTask.dedupe(<ChaoxingTask>[
            a,
            cxExam('991',
                courseId: '240000002', examId: '991', title: '期中测验')
          ]).length,
          1,
          reason: '只有 key 完全相同（同一场的两份副本）才去掉');
    });

    test('同名同 id 的作业与考试也各留一条', () {
      expect(ChaoxingTask.mergeRepublished(<ChaoxingTask>[
        cxHomework('992', courseId: '240000002', title: '期中测验'),
        upcoming(),
      ]).length, 2);
    });

    test('标题含「考试」的课堂活动仍归「课堂活动」页签，不算考试', () {
      expect(tabOf(cxActivity('a9', kind: '考试', clazzId: 'z9', dueAt: kNow)),
          ChaoxingTab.activities);
      expect(tabOf(upcoming()), ChaoxingTab.exam);
      expect(tabOf(hw2()), ChaoxingTab.homework);
    });

    test('tasksOfTab 把考试只给「全部考试」，不落进「全部作业」', () {
      final List<ChaoxingTask> all = <ChaoxingTask>[
        hw2(),
        upcoming(),
        ended(),
        cxActivity('a1'),
      ];
      expect(tasksOfTab(all, ChaoxingTab.homework).map((ChaoxingTask t) => t.id),
          <String>['1']);
      expect(tasksOfTab(all, ChaoxingTab.exam).map((ChaoxingTask t) => t.id),
          <String>['992', '991']);
      expect(tasksOfTab(all, ChaoxingTab.activities).single.id, 'a1');
    });

    test('「仅看未完成」把考完的筛掉，没考完的留着', () {
      final List<ChaoxingTask> l = <ChaoxingTask>[ended(), open()];
      expect(
          buildRows(l, const ChaoxingViewSettings(onlyUnfinished: true), kNow)
              .map((ChaoxingRow r) => r.task.id),
          <String>['993']);
      expect(
          buildRows(l, const ChaoxingViewSettings(onlySubmittable: true), kNow)
              .single
              .task
              .id,
          '993');
    });
  });
}
