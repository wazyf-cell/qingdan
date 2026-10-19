/// 学习通取数客户端：带 cookie 头直连它的 JSON / HTML 页（无官方 API）。
///
/// 接口清单与响应结构来源见 `chaoxing_models.dart`（课程 / 活动）、
/// `chaoxing_homework.dart`（作业页）与 `chaoxing_exam.dart`（考试两页）各自
/// 的文件头声明。会话靠 cookie，**没有 token 刷新**：过期后接口会 302 到登录页
/// 并返回 HTML，这里把它当成「未登录」抛出去，由界面提示重新登录。
library;

import 'dart:convert';
import 'dart:io';

import 'chaoxing_exam.dart';
import 'chaoxing_homework.dart';
import 'chaoxing_models.dart';

/// 会话失效（cookie 缺失/过期）——界面据此显示「重新登录」而不是空列表。
class ChaoxingAuthException implements Exception {
  @override
  String toString() => '学习通会话已失效，需要重新登录';
}

class ChaoxingClient {
  ChaoxingClient({required this.cookie});

  /// 并发上限照抄脚本 :741 的 `batchSize = 5`：账号下有 50+ 门课时全量并发
  /// 容易撞上超星的风控（脚本在课程进度那条链上还额外加了 500ms 间隔，
  /// 注释写明「避免触发验证码」:2811）。
  static const int kBatch = 5;

  /// 形如 `a=1; b=2` 的 Cookie 头值（由登录流程从 WebView 的 cookie jar 导出）。
  final String cookie;

  /// 作业页（脚本 :757-791 那一形态的来源）。
  static const String kUrlHomework =
      'https://mooc1-api.chaoxing.com/work/stu-work';

  /// 考试的卡片形态页。脚本 :463 的常量 `URL_EXAM` 末尾带 `#chaoxing-assignment`
  /// ——那是页面内锚点，HTTP 请求从不发送它，脚本自己抓的时候也没带
  /// （:1434 / :3405 / :3467 三处全是无片段地址），这里同形。
  static const String kUrlExamCards =
      'https://mooc1-api.chaoxing.com/exam-ans/exam/phone/examcode';

  /// 考试的表格形态页：`API_EXAM_LIST` :911 的**原值**，含末尾那个空的 `fid=`。
  /// 不补 fid：脚本 :1455 / :3420 就是照这个常量原样 fetch 的，超星接受空值。
  static const String kUrlExamTable =
      'https://mooc1.chaoxing.com/exam-ans/exam/test/examcode/examlist'
      '?edition=1&nohead=0&fid=';

  final HttpClient _http = HttpClient();

  Future<List<ChaoxingCourse>> fetchCourses() async {
    final Map<String, Object?> json = await _getJson(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&mcode=');
    return ChaoxingCourse.parseCourseList(json);
  }

  /// 拉到过多少门课（面板用它区分「会话没通」与「都已完成」）。
  int courseCount = 0;

  /// 分批逐课程拉活动并合并，按 (courseId, activeId) 去重。
  /// 顺序照脚本 :1509 的 `[...pendingTasks, ...pendingExams, ...activities]`：
  /// 作业页排最前（那才是「我现在要做什么」的真源），考试两页次之（脚本
  /// :1433-1473 在待办区把它们接在作业后面），`activelist` 只有课堂活动
  /// （签到/讨论/问卷），既没有带截止时间的作业也没有考试的状态与分数列。
  Future<List<ChaoxingTask>> fetchAllTasks() async {
    final List<ChaoxingCourse> courses = await fetchCourses();
    courseCount = courses.length;
    final Map<String, String> names = <String, String>{
      for (final ChaoxingCourse c in courses) c.courseId: c.name,
    };
    final List<ChaoxingTask> out = <ChaoxingTask>[
      ...await fetchHomework(names),
      ...await fetchExams(names),
    ];
    int okCourses = 0;
    for (int i = 0; i < courses.length; i += kBatch) {
      final List<List<ChaoxingTask>> batch =
          await Future.wait(courses.skip(i).take(kBatch).map((ChaoxingCourse c) async {
        try {
          final Map<String, Object?> json = await _activelist(c);
          okCourses++;
          return ChaoxingTask.parseActivities(json,
              courseId: c.courseId,
              courseName: c.name,
              // 活动 JSON 本身不给 classId，用请求它时用的那个班级（M6B §B3）。
              clazzId: c.clazzId);
        } catch (e) {
          // 单门课失败不该让整次刷新空手而归；但一门都没成功时说明是会话问题，
          // 必须照抛，否则「未登录」会被伪装成「没有待办」。
          if (okCourses == 0) rethrow;
          return const <ChaoxingTask>[];
        }
      }));
      out.addAll(batch.expand((List<ChaoxingTask> l) => l));
    }
    return ChaoxingTask.mergeRepublished(ChaoxingTask.dedupe(out));
  }

  /// 账号级一页抓完全部作业（1 个请求，比 54 个 activelist 便宜得多）。
  /// 课程列表能通就说明会话没死，所以这一页单独失败只当「没作业」，不炸整次刷新。
  Future<List<ChaoxingTask>> fetchHomework(
      Map<String, String> courseNames) async {
    try {
      return ChaoxingHomework.parsePage(await _getHtml(kUrlHomework),
          courseNames: courseNames, now: DateTime.now());
    } on ChaoxingAuthException {
      rethrow;
    } catch (_) {
      return const <ChaoxingTask>[];
    }
  }

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile';
  static const Duration _timeout = Duration(seconds: 20);

  /// 取一页 HTML；会话失效时超星返回的不是这个形状（或整页请求失败），
  /// 与 [_getJson] 同一判据：不像 HTML 就当未登录。
  Future<String> _getHtml(String url) async {
    final HttpClientRequest req =
        await _http.getUrl(Uri.parse(url)).timeout(_timeout);
    req.headers.set(HttpHeaders.cookieHeader, cookie);
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final HttpClientResponse res = await req.close().timeout(_timeout);
    final String body =
        await res.transform(utf8.decoder).join().timeout(_timeout);
    if (!body.trimLeft().startsWith('<')) throw ChaoxingAuthException();
    return body;
  }

  /// 考试两页各抓一次（脚本 :1433-1473 / :3405-3432 也是两个都抓、按
  /// `examId || title` 合并；两页是不同形态，少一页就少一批考试）。
  ///
  /// 与 [fetchHomework] 同一容错：单页失败只当「这一页没考试」，会话死了照抛，
  /// 否则「未登录」会被伪装成「没有考试」。同一场考试两页都列出来时 `key` 相同
  /// （都是 `courseId|examId`），由 [ChaoxingTask.dedupe] 吃掉。
  Future<List<ChaoxingTask>> fetchExams(
      Map<String, String> courseNames) async {
    final DateTime now = DateTime.now();
    final List<ChaoxingTask> out = <ChaoxingTask>[];
    try {
      out.addAll(ChaoxingExam.parseCards(await _getHtml(kUrlExamCards),
          courseNames: courseNames, now: now));
    } on ChaoxingAuthException {
      rethrow;
    } catch (_) {/* 这一页没抓到 ≠ 没有考试，下一页照抓 */}
    try {
      out.addAll(ChaoxingExam.parseTable(await _getHtml(kUrlExamTable),
          courseNames: courseNames, now: now));
    } on ChaoxingAuthException {
      rethrow;
    } catch (_) {/* 同上 */}
    return ChaoxingTask.dedupe(out);
  }

  Future<Map<String, Object?>> _activelist(ChaoxingCourse c) => _getJson(
      'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist'
      '?fid=0&courseId=${c.courseId}&classId=${c.clazzId}'
      '&showNotStartedActive=0&_=${DateTime.now().millisecondsSinceEpoch}');

  Future<Map<String, Object?>> _getJson(String url) async {
    final HttpClientRequest req = await _http.getUrl(Uri.parse(url)).timeout(_timeout);
    req.headers.set(HttpHeaders.cookieHeader, cookie);
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final HttpClientResponse res = await req.close().timeout(_timeout);
    final String body =
        await res.transform(utf8.decoder).join().timeout(_timeout);
    // 会话失效时超星返回 HTML 登录页而非 JSON；这里不猜，直接判未登录。
    final Object? decoded = body.trimLeft().startsWith('{')
        ? jsonDecode(body)
        : null;
    if (decoded is! Map) throw ChaoxingAuthException();
    return (decoded as Map<Object?, Object?>).cast<String, Object?>();
  }

  void close() => _http.close(force: true);
}
