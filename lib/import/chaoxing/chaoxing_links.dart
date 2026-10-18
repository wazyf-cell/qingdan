/// 学习通条目的「详情」URL 拼接（纯函数，无 IO，可单测）。
///
/// **来源声明**（AGENTS.md 移植必须声明来源）：URL 与查询参数逐字照抄用户目录
/// 里的油猴脚本 `扩展/作业列表.js`（上游 https://github.com/Cooanyh/chaoxing-list，
/// AGPL-3.0-or-later，作者 lcandy2 / Coren）——基址 `API_VISIT_COURSE` :910，
/// 拼法 `getHomeworkLink` :3527-3534（`courseid` / `clazzid` / `pageHeader=8`），
/// 考试拼法 `getExamLink` :3536-3542（本批未接，见下）。
/// 只重写「读哪些字段 / 拼哪个 URL」这层，未拷贝其 UI 与遥测代码。
library;

import 'chaoxing_models.dart';

/// 课程中间页（作业、任务都在这个页里）。脚本 :910 的常量原值带 `?ismooc2=1`，
/// 这里用 [Uri.replace] 追加参数，产出与脚本 `url.href` 同形的串。
const String _kVisitCourse =
    'https://mooc1.chaoxing.com/visit/stucoursemiddle?ismooc2=1';

/// 详情地址；**返回 null 表示本应用打不开真实题目页**，界面要如实降级。
///
/// 只有「作业」页条目能拼：`stu-work` 的 `li[data]` 里同时带 `courseId` 与
/// `clazzId`（`chaoxing_homework.dart` 已把后者读出来）。判别沿用页签的那条
/// 分界——`serverStatus != null` 才是作业页来的条目（见 `chaoxing_grouping.dart`
/// 的 `tasksOfTab`），`activelist` 的课堂活动上游没有对应的单条详情页，
/// 脚本自己也只把它当「进课程」（`getActivityLink` :3544-3549），所以这里返回
/// null 而不是拼一个会 404 的 URL。
///
/// 考试（`kind == '考试'`）**不拼** `getExamLink`：那条链需要 `examId`，
/// 而我们的考试条目是从 `activelist` 的标题关键词认出来的，手里只有活动 id、
/// 没有 examId（脚本走的是 `examcode/examlist` 另一条接口，本批未接）。
/// 宁可不给，也不拼一条打不开的地址。
String? detailUrlOf(ChaoxingTask t) {
  final String? clazzId = t.clazzId;
  if (t.serverStatus == null) return null;
  if (t.courseId.isEmpty || clazzId == null || clazzId.isEmpty) return null;
  return Uri.parse(_kVisitCourse)
      .replace(queryParameters: <String, String>{
        'ismooc2': '1',
        'courseid': t.courseId,
        'clazzid': clazzId,
        'pageHeader': '8',
      })
      .toString();
}
