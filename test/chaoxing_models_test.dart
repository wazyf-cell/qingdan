import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

/// 固定的「当前时间」，让状态机与分桶的期望值可以写死。
final DateTime kNow = DateTime(2026, 10, 17, 12);

/// 真机抓到的 activelist 条目形状（字段名与顺序照 logcat 实录）。
Map<String, Object?> _item({
  Object id = 12345,
  String name = '第一章签到',
  Object? type = 2,
  Object? activeType,
  Object? status = 1,
  Object? startTime,
  Object? endTime,
}) =>
    <String, Object?>{
      'userStatus': 1,
      'nameTwo': '',
      'otherId': '2',
      'groupId': 2,
      'source': 15,
      'isLook': 1,
      'type': type,
      'releaseNum': 0,
      'attendNum': 2,
      'activeType': activeType ?? type,
      'logo': 'https://x/active_type_2_gray.png',
      'nameOne': name,
      'id': id,
      'status': status,
      'startTime': ?startTime,
      'endTime': ?endTime,
    };

Map<String, Object?> _payload(List<Map<String, Object?>> items) =>
    <String, Object?>{
      'result': 1,
      'msg': null,
      'data': <String, Object?>{
        'ext': <String, Object?>{'_from_': 'x'},
        'readingDuration': 1,
        'activeList': items,
      },
    };

List<ChaoxingTask> _parse(List<Map<String, Object?>> items,
        {String courseId = 'c1'}) =>
    ChaoxingTask.parseActivities(_payload(items),
        courseId: courseId, courseName: '高等数学');

ChaoxingTask _t(
        {bool ongoing = true, DateTime? startAt, DateTime? dueAt, String id = '1'}) =>
    ChaoxingTask(
        id: id,
        courseId: 'c1',
        courseName: '高等数学',
        title: 'T$id',
        kind: '作业',
        ongoing: ongoing,
        startAt: startAt,
        dueAt: dueAt);

/// 同课同标题同类型的两条记录，用来模拟服务端重发。
ChaoxingTask _same(String id, DateTime? startAt, {bool ongoing = true}) =>
    ChaoxingTask(
        id: id,
        courseId: 'c1',
        courseName: '高等数学',
        title: '同一条',
        kind: '其他任务',
        ongoing: ongoing,
        startAt: startAt);

void main() {
  group('activelist 解析', () {
    test('startTime / endTime 按毫秒时间戳解析', () {
      final ChaoxingTask t = _parse(<Map<String, Object?>>[
        _item(
          startTime: DateTime(2026, 10, 16, 12).millisecondsSinceEpoch,
          endTime: DateTime(2026, 10, 18, 15, 34).millisecondsSinceEpoch,
        ),
      ]).single;
      expect(t.startAt, DateTime(2026, 10, 16, 12));
      expect(t.dueAt, DateTime(2026, 10, 18, 15, 34));
      expect(t.ongoing, isTrue);
      expect(t.id, '12345');
      expect(t.courseId, 'c1');
      expect(t.courseName, '高等数学');
      expect(t.key, 'c1|12345');
    });

    test('缺时间字段时不编造，两端都为 null', () {
      final ChaoxingTask t = _parse(<Map<String, Object?>>[_item()]).single;
      expect(t.startAt, isNull);
      expect(t.dueAt, isNull);
    });

    test('字符串日期也能解析（超星两种量纲都发过）', () {
      final ChaoxingTask t = _parse(<Map<String, Object?>>[
        _item(startTime: '2026-10-20 23:59:59'),
      ]).single;
      expect(t.startAt, DateTime(2026, 10, 20, 23, 59, 59));
    });

    test('status==2 判为已结束（ongoing=false）', () {
      expect(_parse(<Map<String, Object?>>[_item(status: 2)]).single.ongoing,
          isFalse);
    });

    test('包壳层级退化时仍取得到列表', () {
      final List<ChaoxingTask> direct = ChaoxingTask.parseActivities(
          <String, Object?>{'data': <Object?>[_item()]},
          courseId: 'c9',
          courseName: 'X');
      expect(direct.single.courseId, 'c9');
    });
  });

  group('类型判定（标题规则优先于码表，照脚本 :661-666）', () {
    String kindOf(Map<String, Object?> item) =>
        _parse(<Map<String, Object?>>[item]).single.kind;

    test('真机标题「… AI 情境对话实践」判成 AI实践（脚本的正则会漏）', () {
      expect(
          kindOf(_item(
              name: '校园文化节抽奖活动中的随机事件关系运算 AI 情境对话实践',
              type: 77)),
          'AI实践');
    });

    test('码表命中：type=2 → 签到', () {
      expect(kindOf(_item(name: '第三章第一节', type: 2)), '签到');
    });

    test('activeType 优先于 type：type=2 但 activeType=47 → 作业', () {
      expect(
          kindOf(_item(name: '第二章习题', type: 2, activeType: 47)), '作业');
    });

    test('未知码落「其他任务」，不猜', () {
      expect(kindOf(_item(name: '医疗诊断系统的概率建模', type: 77)), '其他任务');
    });

    test('标题含「考试」时压过码表', () {
      expect(kindOf(_item(name: '期中考试', type: 2)), '考试');
    });

    test('「分组」+「讨论」→ 分组讨论', () {
      expect(kindOf(_item(name: '第四章分组讨论', type: 77)), '分组讨论');
    });

    test('真机探针补的三条码：11 选人 / 46 通知 / 74 位置签到', () {
      expect(kindOf(_item(name: '选人', type: 11)), '选人');
      expect(kindOf(_item(name: '音乐会公告', type: 46)), '通知');
      expect(kindOf(_item(name: '位置签到20251110-签退', type: 74)), '位置签到');
    });
  });

  group('去重', () {
    test('同 (courseId, activeId) 的重复条目只留一条', () {
      final List<ChaoxingTask> out = _parse(<Map<String, Object?>>[
        _item(id: 7),
        _item(id: 7),
        _item(id: 8),
      ]);
      expect(out.length, 2);
      expect(out.map((ChaoxingTask t) => t.id).toList(), <String>['7', '8']);
    });

    test('不同课程的同 id 是两条（键里带 courseId）', () {
      final List<ChaoxingTask> out = ChaoxingTask.dedupe(<ChaoxingTask>[
        _t(id: '1').copyCourse('c1'),
        _t(id: '1').copyCourse('c2'),
      ]);
      expect(out.length, 2);
    });

    test('服务端重发的同标题进行中条目，只留发布最晚的一条', () {
      final List<ChaoxingTask> out = ChaoxingTask.mergeRepublished(
          <ChaoxingTask>[
        _same('old', kNow.subtract(const Duration(hours: 5))),
        _same('new', kNow.subtract(const Duration(hours: 1))),
      ]);
      expect(out.single.id, 'new');
    });

    test('顺序颠倒时同样留下有时间的那条', () {
      final List<ChaoxingTask> out = ChaoxingTask.mergeRepublished(
          <ChaoxingTask>[
        _same('withTime', kNow),
        _same('noTime', null),
      ]);
      expect(out.single.id, 'withTime');
    });

    test('已结束的同标题条目不合并（历史留痕）', () {
      final List<ChaoxingTask> out = ChaoxingTask.mergeRepublished(
          <ChaoxingTask>[
        _same('a', null, ongoing: false),
        _same('b', null, ongoing: false),
      ]);
      expect(out.length, 2);
    });

    test('不同课程的同标题条目不合并', () {
      final List<ChaoxingTask> out = ChaoxingTask.mergeRepublished(
          <ChaoxingTask>[
        _same('a', kNow),
        _same('b', kNow).copyCourse('c2'),
      ]);
      expect(out.length, 2);
    });

    test('课程列表按 (courseId, clazzId) 去重，避免重复发请求', () {
      final List<ChaoxingCourse> courses = ChaoxingCourse.parseCourseList(
          <String, Object?>{
            'channelList': <Object?>[
              <String, Object?>{
                'cataid': 100000002,
                'key': '111',
                'content': <String, Object?>{
                  'course': <String, Object?>{
                    'data': <Object?>[
                      <String, Object?>{'id': 'c1', 'name': '高等数学'},
                    ],
                  },
                },
              },
              <String, Object?>{
                'cataid': '100000002',
                'key': '111',
                'content': <String, Object?>{
                  'course': <String, Object?>{
                    'data': <Object?>[
                      <String, Object?>{'id': 'c1', 'name': '高等数学'},
                    ],
                  },
                },
              },
              <String, Object?>{
                'cataid': '999',
                'key': '222',
                'content': <String, Object?>{
                  'course': <String, Object?>{
                    'data': <Object?>[
                      <String, Object?>{'id': 'c2', 'name': '英语'},
                    ],
                  },
                },
              },
            ],
          });
      expect(courses.length, 1);
      expect(courses.single.key, 'c1|111');
      expect(courses.single.name, '高等数学');
    });
  });
}

extension on ChaoxingTask {
  ChaoxingTask copyCourse(String courseId) => ChaoxingTask(
      id: id,
      courseId: courseId,
      courseName: courseName,
      title: title,
      kind: kind,
      ongoing: ongoing,
      startAt: startAt,
      dueAt: dueAt);
}
