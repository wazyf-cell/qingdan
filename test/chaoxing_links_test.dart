import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/chaoxing/chaoxing_links.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

/// 形状取自真机抓回的 `work/stu-work` 条目（与 `chaoxing_homework_test.dart`
/// 同源），**但三个 id 与开课班名全部换成合成值**（仓库是 public，
/// 真实的 courseId / clazzId / taskrefId 属于个人数据）。
/// 钉的是「URL 拼了哪些参数、缺参数时给不给」，与具体 id 无关。
ChaoxingTask homework(
        {String courseId = '240000001', String? clazzId = '160000001'}) =>
    ChaoxingTask(
        id: '88000001',
        courseId: courseId,
        courseName: '课程甲2026-2027',
        title: '作业1-4',
        kind: '作业',
        ongoing: true,
        serverStatus: '未提交',
        clazzId: clazzId);

ChaoxingTask activity({String? clazzId = '160000001'}) => ChaoxingTask(
    id: 'a1',
    courseId: '240000001',
    courseName: '课程甲2026-2027',
    title: '签到',
    kind: '签到',
    ongoing: true,
    clazzId: clazzId);

void main() {
  group('详情 URL（照抄脚本 getHomeworkLink :3527-3534）', () {
    test('作业项拼出含 courseid / clazzid / pageHeader=8 的 stucoursemiddle', () {
      final String? url = detailUrlOf(homework());
      expect(url, isNotNull);
      expect(url, contains('mooc1.chaoxing.com/visit/stucoursemiddle'));
      expect(url, contains('courseid=240000001'));
      expect(url, contains('clazzid=160000001'));
      expect(url, contains('pageHeader=8'));
    });

    test('缺 clazzId → null（宁可不给，也不拼一条打不开的地址）', () {
      expect(detailUrlOf(homework(clazzId: null)), isNull);
      expect(detailUrlOf(homework(clazzId: '')), isNull);
    });

    test('缺 courseId → null', () {
      expect(detailUrlOf(homework(courseId: '')), isNull);
    });

    test('课堂活动 → null（上游没有单条活动详情页）', () {
      expect(detailUrlOf(activity()), isNull);
    });
  });

  group('clazzId 进模型但不能动 key', () {
    test('key 仍是 courseId|id（已存隐藏项才不会集体失效）', () {
      expect(homework().key, '240000001|88000001');
    });

    test('activelist 解析把请求用的班级 id 带上（活动 JSON 自己不给）', () {
      final List<ChaoxingTask> tasks = ChaoxingTask.parseActivities(
        <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 1, 'name': '签到', 'status': 1, 'activeType': 2}
          ]
        },
        courseId: 'c9',
        courseName: '课程乙',
        clazzId: 'z9',
      );
      expect(tasks.single.clazzId, 'z9');
      expect(tasks.single.key, 'c9|1');
    });
  });
}
