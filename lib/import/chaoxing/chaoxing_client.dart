/// 学习通取数客户端：带 cookie 头直连它的 JSON / HTML 页（无官方 API）。
///
/// 接口清单与响应结构来源见 `chaoxing_models.dart`（课程 / 活动）、
/// `chaoxing_homework.dart`（作业页）与 `chaoxing_exam.dart`（考试两页）各自
/// 的文件头声明。会话靠 cookie，**没有 token 刷新**：过期后接口会 302 到登录页
/// 并返回 HTML，这里把它当成「未登录」抛出去，由界面提示重新登录。
///
/// 2026-10-23 提速（真账号 54 门班级 / 84 条作业实测 5.4s）：
/// ① 课程列表与作业页**互不依赖**，改成并发；考试两页也并发（合并顺序仍固定
///    「表格页在前」，那是 dedupe 留第一条的依据，与完成先后无关）。
/// ② 课堂活动从「刷新时必抓」改成**按需**（切到该页签才拉），它原本占 3 秒。
/// ③ HttpClient 带 `connectionTimeout`，且由调用方跨刷新复用——以前每次刷新
///    新建再 `close(force:true)`，三个主机每次都要重做 TCP+TLS。
library;

import 'dart:convert';
import 'dart:io';

import 'chaoxing_exam.dart';
import 'chaoxing_homework.dart';
import 'chaoxing_models.dart';
import 'chaoxing_work_detail.dart';

/// 会话失效（cookie 缺失/过期）——界面据此显示「重新登录」而不是空列表。
class ChaoxingAuthException implements Exception {
  @override
  String toString() => '学习通会话已失效，需要重新登录';
}

/// 一次「必刷」的产物。课程表一并带出：课堂活动按需加载时还要拿它去发请求。
class ChaoxingEager {
  const ChaoxingEager({
    required this.courses,
    required this.homework,
    required this.exams,
  });

  final List<ChaoxingCourse> courses;
  final List<ChaoxingTask> homework;
  final List<ChaoxingTask> exams;
}

class ChaoxingClient {
  ChaoxingClient({required this.cookie});

  /// 活动请求的并发上限，照抄脚本 :741 的 `batchSize = 5`：账号下 50+ 门课时
  /// 全量并发容易撞上超星的风控（脚本 :2811 还额外加了 500ms 间隔）。
  static const int kBatch = 5;

  /// 形如 `a=1; b=2` 的 Cookie 头值（由登录流程从 WebView 的 cookie jar 导出）。
  final String cookie;

  /// 作业页（脚本 :757-791 那一形态的来源）。
  static const String kUrlHomework =
      'https://mooc1-api.chaoxing.com/work/stu-work';

  /// 考试卡片页。脚本 :463 的常量末尾带 `#chaoxing-assignment`——页面内锚点，
  /// HTTP 请求从不发送它，脚本自己抓的时候也没带（:1434 / :3405 / :3467 三处
  /// 全是无片段地址），这里同形。
  static const String kUrlExamCards =
      'https://mooc1-api.chaoxing.com/exam-ans/exam/phone/examcode';

  /// 考试表格页：`API_EXAM_LIST` :911 的**原值**，含末尾那个空的 `fid=`。
  /// 不补 fid：脚本 :1455 / :3420 就是照这个常量原样 fetch 的，超星接受空值。
  static const String kUrlExamTable =
      'https://mooc1.chaoxing.com/exam-ans/exam/test/examcode/examlist'
      '?edition=1&nohead=0&fid=';

  /// 连接阶段单独限时：不复用连接时每次刷新都要重做三次 TCP+TLS，
  /// 一个 DNS/握手卡死能白等到整页超时（实测最坏一个请求吃掉 60 秒）。
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  /// 拉到过多少门课（面板用它区分「会话没通」与「都已完成」）。
  int courseCount = 0;

  /// 刷新必抓的两波：课程+作业并发，随后两页考试并发。
  ///
  /// [onHomework] 在第一波落地时调一次（此时作业已经能显示），[onDone] 在全部
  /// 结束时再调一次——界面据此做渐进渲染：用户要的是「作业一出来就先看到」。
  Future<ChaoxingEager> fetchEager({
    void Function(ChaoxingEager firstWave)? onHomework,
    void Function(ChaoxingEager all)? onDone,
  }) async {
    final DateTime now = DateTime.now();
    // 第一波：课程列表（JSON）与作业页（HTML）互不依赖。
    final List<Object?> wave1 = await Future.wait<Object?>(<Future<Object?>>[
      fetchCourses(),
      _softHtml(kUrlHomework),
    ]);
    final List<ChaoxingCourse> courses = wave1[0]! as List<ChaoxingCourse>;
    courseCount = courses.length;
    final Map<String, String> names = <String, String>{
      for (final ChaoxingCourse c in courses) c.courseId: c.name,
    };
    final List<ChaoxingTask> homework = _parseSoft(
        () => ChaoxingHomework.parsePage(wave1[1]! as String,
            courseNames: names, now: now));
    onHomework?.call(ChaoxingEager(
        courses: courses, homework: homework, exams: const <ChaoxingTask>[]));

    // 第二波：两页考试互不依赖。合并顺序固定「表格页在前」——[ChaoxingTask.dedupe]
    // 留第一条，而只有表格页给绝对时间区间（详见 [fetchExams] 的说明）。
    final List<Object?> wave2 = await Future.wait<Object?>(<Future<Object?>>[
      _softHtml(kUrlExamTable),
      _softHtml(kUrlExamCards),
    ]);
    final List<ChaoxingTask> exams = <ChaoxingTask>[];
    if (wave2[0] != null) {
      exams.addAll(_parseSoft(() => ChaoxingExam.parseTable(wave2[0]! as String,
          courseNames: names, now: now)));
    }
    if (wave2[1] != null) {
      exams.addAll(_parseSoft(() => ChaoxingExam.parseCards(wave2[1]! as String,
          courseNames: names, now: now)));
    }
    final ChaoxingEager done = ChaoxingEager(
        courses: courses,
        homework: homework,
        exams: ChaoxingTask.dedupe(exams));
    onDone?.call(done);
    return done;
  }

  Future<List<ChaoxingCourse>> fetchCourses() async {
    final Map<String, Object?> json = await _getJson(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&mcode=');
    return ChaoxingCourse.parseCourseList(json);
  }

  /// 按需拉课堂活动（签到/讨论/问卷），按 (courseId, activeId) 去重。
  ///
  /// 它与作业页不同：**一个班一个请求**（实测 54 个班 = 11 批），且没有带截止
  /// 时间的作业、没有考试状态，所以从刷新里挪出来，切到「课堂活动」页签才拉。
  /// 用常驻工作池而不是「每 5 个一批等齐再下一批」：后者前面一批里只要有一个
  /// 慢，后面 4 个空位就干等着。
  Future<List<ChaoxingTask>> fetchActivities(List<ChaoxingCourse> courses) async {
    final List<ChaoxingCourse> queue = List<ChaoxingCourse>.of(courses);
    final List<ChaoxingTask> out = <ChaoxingTask>[];
    final List<Object> errors = <Object>[];
    int ok = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final ChaoxingCourse c = queue.removeAt(0);
        try {
          final Map<String, Object?> json = await _activelist(c);
          ok++;
          out.addAll(ChaoxingTask.parseActivities(json,
              courseId: c.courseId,
              courseName: c.name,
              // 活动 JSON 本身不给 classId，用请求它时用的那个班级（M6B §B3）。
              clazzId: c.clazzId));
        } on ChaoxingAuthException {
          rethrow;
        } catch (e) {
          errors.add(e);
        }
      }
    }

    final int lanes = courses.length < kBatch ? courses.length : kBatch;
    await Future.wait(List<Future<void>>.generate(lanes, (_) => worker()));
    // 一个都没成功 = 会话/网络问题，必须照抛：否则「未登录」会被伪装成「没有活动」。
    if (ok == 0 && errors.isNotEmpty) throw errors.first;
    return ChaoxingTask.mergeRepublished(ChaoxingTask.dedupe(out));
  }

  /// 取一页 HTML；失败返回 null（= 这一页没有，不影响其它页），会话失效照抛。
  Future<String?> _softHtml(String url) async {
    try {
      return await _getHtml(url);
    } on ChaoxingAuthException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// 解析失败一律当「这一页是空的」：页面改版会让正则抽不到东西，那不该炸掉
  /// 整次刷新，也不该被显示成「未登录」。
  List<ChaoxingTask> _parseSoft(List<ChaoxingTask> Function() body) {
    try {
      return body();
    } catch (_) {
      return const <ChaoxingTask>[];
    }
  }

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile';
  static const Duration _timeout = Duration(seconds: 20);

  /// 取一页 HTML；会话失效时超星返回的不是这个形状，与 [_getJson] 同一思路判
  /// 未登录。但**光看首字符不够**：cookie 过期后这一串请求会被 302 到
  /// `passport2.chaoxing.com` 的登录页，而登录页本身就是合法 HTML（以 `<` 开头），
  /// 于是「未登录」被读成「这一页没有作业/考试」——列表静默变空，界面还一片祥和。
  /// 所以先认重定向落点（[bouncedToLogin]，与详情页 WebView 那条判据同源），
  /// 再看首字符兜住「没跳转但回来的不是页面」那种形态。
  Future<String> _getHtml(String url) async {
    final HttpClientRequest req =
        await _http.getUrl(Uri.parse(url)).timeout(_timeout);
    req.headers.set(HttpHeaders.cookieHeader, cookie);
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final HttpClientResponse res = await req.close().timeout(_timeout);
    final String body =
        await res.transform(utf8.decoder).join().timeout(_timeout);
    if (bouncedToLogin(res.redirects.map((RedirectInfo r) => r.location)) ||
        !body.trimLeft().startsWith('<')) {
      throw ChaoxingAuthException();
    }
    return body;
  }

  /// 这一串重定向落点里有没有「登录页」。判据与 `chaoxing_detail_page.dart` 的
  /// `_onLoadStop` 一致（认 `passport` / `login`），两处必须同一套，否则 WebView
  /// 那条路说「登录态失效」而 HTTP 这条路说「没有待办」。
  static bool bouncedToLogin(Iterable<Uri> locations) => locations.any((Uri u) {
        final String s = '${u.host}${u.path}'.toLowerCase();
        return s.contains('passport') || s.contains('/login');
      });

  /// 考试两页合并（脚本 :1433-1473 / :3405-3432 也是两个都抓、按
  /// `examId || title` 合并）。保留此方法供「只想拿考试」的调用方使用；
  /// [fetchEager] 里两页是并发的，这里的串行版本只在单测与诊断里用。
  ///
  /// **表格页排在卡片页前面**：同一场考试两页都列出来时 [ChaoxingTask.dedupe]
  /// 留第一条，而只有表格页给绝对时间区间（真账号实测：卡片页 40 条里
  /// 「剩余」「截止」「已结束」一个字都没有，时间列全空）。反过来放就会把
  /// 带时间的那条丢掉、留下没时间的——2026-10-19 实测被这样吃掉两场考试。
  Future<List<ChaoxingTask>> fetchExams(Map<String, String> courseNames) async {
    final DateTime now = DateTime.now();
    final List<ChaoxingTask> out = <ChaoxingTask>[];
    final String? table = await _softHtml(kUrlExamTable);
    if (table != null) {
      out.addAll(_parseSoft(
          () => ChaoxingExam.parseTable(table, courseNames: courseNames, now: now)));
    }
    final String? cards = await _softHtml(kUrlExamCards);
    if (cards != null) {
      out.addAll(_parseSoft(
          () => ChaoxingExam.parseCards(cards, courseNames: courseNames, now: now)));
    }
    return ChaoxingTask.dedupe(out);
  }

  /// 取一条作业的正文：确认页 → 题目页两跳。
  ///
  /// 返回 null 表示**这一条抽不出正文**（已提交 / 已过时效 / 页面不是题目页），
  /// 界面要退回真实网页；会话失效照抛 [ChaoxingAuthException]，不能把「没登录」
  /// 说成「这道题是空的」。
  Future<ChaoxingWorkDetail?> fetchWorkDetail(String entryUrl) async {
    final String confirm = await _getHtml(entryUrl);
    final String? workUrl =
        ChaoxingWorkPage.parseWorkUrl(confirm, entryUrl: entryUrl);
    if (workUrl == null) return null;
    return ChaoxingWorkPage.parse(await _getHtml(workUrl));
  }

  Future<Map<String, Object?>> _activelist(ChaoxingCourse c) => _getJson(
      'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist'
      '?fid=0&courseId=${c.courseId}&classId=${c.clazzId}'
      '&showNotStartedActive=0&_=${DateTime.now().millisecondsSinceEpoch}');

  Future<Map<String, Object?>> _getJson(String url) async {
    final HttpClientRequest req =
        await _http.getUrl(Uri.parse(url)).timeout(_timeout);
    req.headers.set(HttpHeaders.cookieHeader, cookie);
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final HttpClientResponse res = await req.close().timeout(_timeout);
    final String body =
        await res.transform(utf8.decoder).join().timeout(_timeout);
    // 会话失效时超星返回 HTML 登录页而非 JSON；这里不猜，直接判未登录。
    final Object? decoded =
        body.trimLeft().startsWith('{') ? jsonDecode(body) : null;
    if (decoded is! Map) throw ChaoxingAuthException();
    return (decoded as Map<Object?, Object?>).cast<String, Object?>();
  }

  void close() => _http.close(force: true);
}
