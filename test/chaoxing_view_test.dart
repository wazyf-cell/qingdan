import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/features/chaoxing/chaoxing_grouping.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_time.dart';

final DateTime kNow = DateTime(2026, 10, 17, 12);

ChaoxingTask _h(String id, String course, String title,
        {String? status = '未提交',
        bool serverDone = false,
        bool ongoing = true,
        DateTime? dueAt}) =>
    ChaoxingTask(
        id: id,
        courseId: id,
        courseName: course,
        title: title,
        kind: '作业',
        ongoing: ongoing,
        dueAt: dueAt,
        serverStatus: status,
        serverDone: serverDone);

ChaoxingTask _a(String id, String course, String kind,
        {bool ongoing = true, DateTime? dueAt}) =>
    ChaoxingTask(
        id: id,
        courseId: id,
        courseName: course,
        title: 'T$id',
        kind: kind,
        ongoing: ongoing,
        dueAt: dueAt);

/// 作业页三条：待提交（3 小时后截止）、已完成、已过期未提交。
List<ChaoxingTask> homework() => <ChaoxingTask>[
      _h('h1', '课程甲', '第四次作业',
          dueAt: kNow.add(const Duration(hours: 3))),
      _h('h2', '课程丙', '实验3 项目成本估算+AI',
          status: '已完成',
          serverDone: true,
          dueAt: kNow.subtract(const Duration(hours: 1))),
      _h('h3', '课程乙', '第一次作业',
          ongoing: false, dueAt: kNow.subtract(const Duration(hours: 2))),
    ];

/// 课堂活动两条：进行中签到、已结束讨论。
List<ChaoxingTask> activities() => <ChaoxingTask>[
      _a('a1', '课程甲', '签到', dueAt: kNow.add(const Duration(hours: 30))),
      _a('a2', '课程甲', '分组讨论', ongoing: false),
    ];

List<String> _ids(List<ChaoxingRow> rows) =>
    rows.map((ChaoxingRow r) => r.task.id).toList();

void main() {
  group('剩余时长与截止行（与扩展成品逐字一致）', () {
    test('≥1 天省略分钟，不足 1 天带分钟', () {
      expect(formatRemaining(const Duration(days: 1, hours: 3, minutes: 34)),
          '1天3小时');
      expect(formatRemaining(const Duration(hours: 23, minutes: 49)),
          '23小时49分');
      expect(formatRemaining(const Duration(minutes: 34)), '34分');
      expect(formatRemaining(const Duration(seconds: 30)), '不足1分');
      expect(formatRemaining(const Duration(hours: 25)), '1天1小时');
      expect(formatRemaining(const Duration(days: 2)), '2天0小时');
      expect(formatRemaining(const Duration(minutes: -90)), '1小时30分');
    });

    test('截止行 = 「MM-DD HH:mm 截止（剩…）」，月日补零', () {
      expect(formatDeadlineLine(DateTime(2026, 10, 18, 22, 59), kNow),
          '10-18 22:59 截止（剩1天10小时）');
      expect(formatDeadlineLine(DateTime(2026, 11, 8, 9, 5), kNow),
          '11-08 09:05 截止（剩21天21小时）');
    });

    test('已过截止的活条目显示「已逾期」前缀', () {
      expect(formatDeadlineLine(DateTime(2026, 10, 17, 9, 55), kNow),
          '10-17 09:55 截止（已逾期 2小时5分）');
    });

    test('紧急度分档：24 小时内急、72 小时内近', () {
      expect(urgencyOf(null, kNow), ChaoxingUrgency.none);
      expect(urgencyOf(kNow.add(const Duration(hours: 3)), kNow),
          ChaoxingUrgency.urgent);
      expect(urgencyOf(kNow.add(const Duration(hours: 48)), kNow),
          ChaoxingUrgency.soon);
      expect(urgencyOf(kNow.add(const Duration(hours: 100)), kNow),
          ChaoxingUrgency.calm);
    });
  });

  group('页签分界', () {
    test('带服务端状态原文的进「全部作业」，其余进「课堂活动」', () {
      final List<ChaoxingTask> all = <ChaoxingTask>[...homework(), ...activities()];
      expect(tasksOfTab(all, ChaoxingTab.homework).length, 3);
      expect(tasksOfTab(all, ChaoxingTab.activities).length, 2);
    });
  });

  group('工具栏开关（语义对齐扩展）', () {
    test('默认全显示，截止最早优先', () {
      expect(_ids(buildRows(homework(), const ChaoxingViewSettings(), kNow)),
          <String>['h3', 'h2', 'h1']);
    });

    test('仅看未完成：藏掉已完成与已结束', () {
      expect(
          _ids(buildRows(homework(),
              const ChaoxingViewSettings(onlyUnfinished: true), kNow)),
          <String>['h1']);
    });

    test('仅看可提交：只留没过期且没交的', () {
      expect(
          _ids(buildRows(homework(),
              const ChaoxingViewSettings(onlySubmittable: true), kNow)),
          <String>['h1']);
    });

    test('隐藏标记优先于一切开关', () {
      expect(
          _ids(buildRows(
              homework(),
              const ChaoxingViewSettings(hidden: <String>{'h1|h1'}),
              kNow)),
          <String>['h3', 'h2']);
    });

    test('搜索命中标题或课程，不分大小写', () {
      const ChaoxingViewSettings s = ChaoxingViewSettings();
      expect(_ids(buildRows(homework(), s, kNow, query: '白盒')), isEmpty);
      expect(_ids(buildRows(homework(), s, kNow, query: '成本')), <String>['h2']);
      expect(_ids(buildRows(homework(), s, kNow, query: '运筹')), <String>['h1']);
    });

    test('课程筛选只留该课程', () {
      expect(
          _ids(buildRows(homework(), const ChaoxingViewSettings(), kNow,
              course: '课程甲')),
          <String>['h1']);
      expect(
          courseOptions(homework()),
          <String>['课程乙', '课程丙', '课程甲']);
    });
  });

  group('排序五档', () {
    List<ChaoxingRow> sorted(ChaoxingSortBy by) => buildRows(
        homework(), ChaoxingViewSettings(sortBy: by), kNow);

    test('截止最晚优先：无截止仍排最后', () {
      expect(_ids(sorted(ChaoxingSortBy.timeDesc)), <String>['h1', 'h2', 'h3']);
    });

    test('按课程：课程名升序，组内截止升序', () {
      expect(_ids(sorted(ChaoxingSortBy.course)), <String>['h3', 'h2', 'h1']);
    });

    test('按状态：待办 → 已完成 → 已结束', () {
      expect(_ids(sorted(ChaoxingSortBy.status)), <String>['h1', 'h2', 'h3']);
    });

    test('按名称：标题字典序', () {
      expect(_ids(sorted(ChaoxingSortBy.name)), <String>['h2', 'h3', 'h1']);
    });
  });

  group('活动页签沿用同一套开关', () {
    test('仅看未完成藏掉已结束的活动', () {
      expect(
          _ids(buildRows(activities(),
              const ChaoxingViewSettings(onlyUnfinished: true), kNow)),
          <String>['a1']);
    });

    test('活动没有服务端状态，标签退回本地状态机', () {
      final ChaoxingRow row =
          buildRows(activities(), const ChaoxingViewSettings(), kNow).first;
      expect(row.task.serverStatus, isNull);
      expect(row.state, ChaoxingTaskState.todo);
    });
  });
}
