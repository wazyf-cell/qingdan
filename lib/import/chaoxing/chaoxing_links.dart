/// 学习通条目的「详情」URL 拼接（纯函数，无 IO，可单测）。
///
/// **来源声明**（AGENTS.md 移植必须声明来源）：URL 与查询参数逐字照抄用户目录
/// 里的油猴脚本 `扩展/作业列表.js`（上游 https://github.com/Cooanyh/chaoxing-list，
/// AGPL-3.0-or-later，作者 lcandy2 / Coren）——基址 `API_VISIT_COURSE` :910，
/// 拼法 `getHomeworkLink` :3527-3534（`courseid` / `clazzid` / `pageHeader=8`），
/// 考试基址 `API_OPEN_EXAM` :912，拼法 `getExamLink` :3536-3542
/// （`courseId` / `classId` / `examId`，参数名大小写与脚本逐字一致）。
/// 只重写「读哪些字段 / 拼哪个 URL」这层，未拷贝其 UI 与遥测代码。
library;

import 'chaoxing_models.dart';

/// 课程中间页（作业、任务都在这个页里）。脚本 :910 的常量原值带 `?ismooc2=1`，
/// 这里用 [Uri.replace] 追加参数，产出与脚本 `url.href` 同形的串。
const String _kVisitCourse =
    'https://mooc1.chaoxing.com/visit/stucoursemiddle?ismooc2=1';

/// 考试入口页 = 脚本 :912 的 `API_OPEN_EXAM` 原值，一字未改。
const String _kOpenExam =
    'https://mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examnotes';

/// 详情地址；**返回 null 表示本应用打不开真实题目页**，界面要如实降级。
///
/// 三个来源页各有各的判据，共同的底线是**缺参数就不拼**（宁可不给，也不给一条
/// 会 404 / 会跳错误页的地址）：
///  - **考试**：见 [_examUrl]（脚本 `getExamLink` :3536-3542）。
///  - **作业页**条目：`stu-work` 的 `li[data]` 里同时带 `courseId` 与 `clazzId`
///    （`chaoxing_homework.dart` 已把后者读出来），拼课程中间页的作业栏。
///    判别沿用页签那条分界——`serverStatus != null` 才是作业页来的条目
///    （见 `chaoxing_grouping.dart` 的 [tabOf]）。
///  - **课堂活动**：返回 null。`activelist` 的条目上游没有对应的单条详情页，
///    脚本自己也只把它当「进课程」（`getActivityLink` :3544-3549）。
String? detailUrlOf(ChaoxingTask t) {
  final String? clazzId = t.clazzId;
  if (t.courseId.isEmpty || clazzId == null || clazzId.isEmpty) return null;
  if (t.source == ChaoxingSource.exam) return _examUrl(t, clazzId);
  if (t.serverStatus == null) return null;
  return Uri.parse(_kVisitCourse)
      .replace(queryParameters: <String, String>{
        'ismooc2': '1',
        'courseid': t.courseId,
        'clazzid': clazzId,
        'pageHeader': '8',
      })
      .toString();
}

/// 考试那条 `examnotes`：`courseId` / `classId` / `examId` **缺一个都不拼**。
///
/// 早先这里写过一条「考试不拼 `getExamLink`，因为手里只有活动 id、没有 examId
/// （脚本走的是 examcode/examlist 另一条接口，本批未接）」——那句话在当时是真的，
/// 现在考试两页都接上了，两个来源都能给出 examId：
///  - 表格形态：从操作列 `onclick="go('…')"` 里那串地址的 `refer` 参数解出
///    （脚本 :861-871，退路 :873-878）；
///  - 卡片形态：`li[data]` 的 `taskrefId`——脚本 :823 就是把它当 `examId` 存的
///    （:3471 的 `examItems` 全部来自这一形态，:3536 的 `getExamLink` 照用不误）。
///
/// 仍然返回 null 的两种**真缺**：① 那一行的操作列既没有 `go('…')` 也没有可解析
/// 的 href（三个 id 全空）；② 卡片形态的 `data` 里没带 `taskrefId`。
/// **刻意不用 [ChaoxingTask.id] 顶替**：缺 examId 时那条 id 是标题兜底出来的
/// （脚本 :1440 的判重键就是 `examId || title`），拿它当 examId 拼出来的地址
/// 必然打不开，那正是「为了看起来能用而拼个假链接」。
String? _examUrl(ChaoxingTask t, String classId) {
  final String? examId = t.examId;
  if (examId == null || examId.isEmpty) return null;
  return Uri.parse(_kOpenExam)
      .replace(queryParameters: <String, String>{
        'courseId': t.courseId,
        'classId': classId,
        'examId': examId,
      })
      .toString();
}
