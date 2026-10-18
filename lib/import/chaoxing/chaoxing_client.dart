/// 学习通取数客户端：带 cookie 头直连它的 JSON 接口（无官方 API）。
///
/// 接口清单与响应结构来源见 `chaoxing_models.dart` 文件头声明。会话靠
/// cookie，**没有 token 刷新**：过期后接口会 302 到登录页并返回 HTML，
/// 这里把它当成「未登录」抛出去，由界面提示重新登录。
library;

import 'dart:convert';
import 'dart:io';

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

  final HttpClient _http = HttpClient();

  Future<List<ChaoxingCourse>> fetchCourses() async {
    final Map<String, Object?> json = await _getJson(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&mcode=');
    return ChaoxingCourse.parseCourseList(json);
  }

  /// 拉到过多少门课（面板用它区分「会话没通」与「都已完成」）。
  int courseCount = 0;

  /// 分批逐课程拉活动并合并，按 (courseId, activeId) 去重。
  /// 作业页（stu-work）排在最前：那才是「我现在要做什么」的真源，
  /// activelist 只有课堂活动（签到/讨论/问卷），没有带截止时间的作业。
  Future<List<ChaoxingTask>> fetchAllTasks() async {
    final List<ChaoxingCourse> courses = await fetchCourses();
    courseCount = courses.length;
    final Map<String, String> names = <String, String>{
      for (final ChaoxingCourse c in courses) c.courseId: c.name,
    };
    final List<ChaoxingTask> out = <ChaoxingTask>[...await fetchHomework(names)];
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
      final HttpClientRequest req = await _http
          .getUrl(Uri.parse('https://mooc1-api.chaoxing.com/work/stu-work'))
          .timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.cookieHeader, cookie);
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile');
      final HttpClientResponse res =
          await req.close().timeout(const Duration(seconds: 20));
      final String body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      if (!body.trimLeft().startsWith('<')) throw ChaoxingAuthException();
      return ChaoxingHomework.parsePage(body,
          courseNames: courseNames, now: DateTime.now());
    } on ChaoxingAuthException {
      rethrow;
    } catch (_) {
      return const <ChaoxingTask>[];
    }
  }

  Future<Map<String, Object?>> _activelist(ChaoxingCourse c) => _getJson(
      'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist'
      '?fid=0&courseId=${c.courseId}&classId=${c.clazzId}'
      '&showNotStartedActive=0&_=${DateTime.now().millisecondsSinceEpoch}');

  Future<Map<String, Object?>> _getJson(String url) async {
    final HttpClientRequest req =
        await _http.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 20));
    req.headers.set(HttpHeaders.cookieHeader, cookie);
    req.headers.set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile');
    final HttpClientResponse res =
        await req.close().timeout(const Duration(seconds: 20));
    final String body =
        await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    // 会话失效时超星返回 HTML 登录页而非 JSON；这里不猜，直接判未登录。
    final Object? decoded = body.trimLeft().startsWith('{')
        ? jsonDecode(body)
        : null;
    if (decoded is! Map) throw ChaoxingAuthException();
    return (decoded as Map<Object?, Object?>).cast<String, Object?>();
  }

  void close() => _http.close(force: true);
}
