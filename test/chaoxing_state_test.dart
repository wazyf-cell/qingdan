import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

/// 固定的「当前时间」，让状态机与分桶的期望值可以写死。
final DateTime kNow = DateTime(2026, 10, 17, 12);

ChaoxingTask _t({bool ongoing = true, DateTime? startAt, DateTime? dueAt}) =>
    ChaoxingTask(
        id: '1',
        courseId: 'c1',
        courseName: '高等数学',
        title: 'T',
        kind: '作业',
        ongoing: ongoing,
        startAt: startAt,
        dueAt: dueAt);

void main() {
  group('状态机（已完成是本地标记，已结束是服务端/时间真值）', () {
    test('开着且没有起止时间 → 待办', () {
      expect(_t().stateAt(kNow, done: false), ChaoxingTaskState.todo);
    });

    test('发布时间在未来 → 未开始', () {
      expect(
          _t(startAt: kNow.add(const Duration(hours: 1)))
              .stateAt(kNow, done: false),
          ChaoxingTaskState.notStarted);
    });

    test('截止时间已过 → 已结束', () {
      expect(
          _t(dueAt: kNow.subtract(const Duration(hours: 1)))
              .stateAt(kNow, done: false),
          ChaoxingTaskState.ended);
    });

    test('服务端已关闭（status!=1）即使截止时间在未来也算已结束', () {
      expect(
          _t(ongoing: false, dueAt: kNow.add(const Duration(hours: 1)))
              .stateAt(kNow, done: false),
          ChaoxingTaskState.ended);
    });

    test('本地完成标记压过其它状态', () {
      expect(_t(ongoing: false).stateAt(kNow, done: true),
          ChaoxingTaskState.done);
      expect(
          _t(startAt: kNow.add(const Duration(hours: 1)))
              .stateAt(kNow, done: true),
          ChaoxingTaskState.done);
    });

    test('有效性窗口：缺失端点视为不设限', () {
      expect(
          _t(startAt: kNow.subtract(const Duration(hours: 1)),
                  dueAt: kNow.add(const Duration(hours: 1)))
              .isValidAt(kNow),
          isTrue);
      expect(_t(dueAt: kNow.add(const Duration(hours: 1))).isValidAt(kNow),
          isTrue);
      expect(_t().isValidAt(kNow), isTrue);
      expect(_t(startAt: kNow.add(const Duration(hours: 1))).isValidAt(kNow),
          isFalse);
      expect(
          _t(dueAt: kNow.subtract(const Duration(hours: 1))).isValidAt(kNow),
          isFalse);
      expect(_t(ongoing: false).isValidAt(kNow), isFalse);
    });
  });

  group('截止分桶', () {
    ChaoxingDueBucket b(DateTime? due) => ChaoxingDueBucket.of(due, kNow);

    test('无截止 → none', () => expect(b(null), ChaoxingDueBucket.none));
    test('已过 → overdue',
        () => expect(b(kNow.subtract(const Duration(minutes: 1))),
            ChaoxingDueBucket.overdue));
    test('当天晚些 → today',
        () => expect(b(DateTime(2026, 10, 17, 15)), ChaoxingDueBucket.today));
    test('明天 → tomorrow',
        () => expect(b(DateTime(2026, 10, 18, 12)),
            ChaoxingDueBucket.tomorrow));
    test('5 天后 → week',
        () => expect(b(kNow.add(const Duration(days: 5))),
            ChaoxingDueBucket.week));
    test('10 天后 → later',
        () => expect(b(kNow.add(const Duration(days: 10))),
            ChaoxingDueBucket.later));
    test('恰好 7 天不算 week',
        () => expect(b(kNow.add(const Duration(days: 7))),
            ChaoxingDueBucket.later));
  });
}
