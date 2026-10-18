/// 学习通课程（= 一个班级）实体与 `backclazzdata` 解析。
///
/// 从 `chaoxing_models.dart` 拆出（M6B §B3：加 `clazzId` 后单文件撞 300 行红线）。
///
/// **来源声明**（AGENTS.md 禁止事项要求逐个文件标注）：接口地址与响应层级取自
/// 用户的油猴脚本 `扩展/作业列表.js`（上游 https://github.com/Cooanyh/chaoxing-list，
/// AGPL-3.0-or-later，作者 lcandy2 / Coren）——课程接口 :467、课程解析 :2264。
/// 只重写「读哪些字段」这层契约，未拷贝其 Vue UI 与遥测代码。
library;

/// 一门课（= 一个班级）。学习通的作业/考试都挂在 (courseId, clazzId) 上。
class ChaoxingCourse {
  const ChaoxingCourse({
    required this.courseId,
    required this.clazzId,
    required this.name,
  });

  final String courseId;
  final String clazzId;
  final String name;

  String get key => '$courseId|$clazzId';

  /// `backclazzdata?view=json` → `channelList[]`：只取 `cataid == 100000002`
  /// 的条目，课程在 `content.course.data[]`，班级 id 在外层 `key`。
  static List<ChaoxingCourse> parseCourseList(Map<String, Object?> json) {
    final List<ChaoxingCourse> out = <ChaoxingCourse>[];
    for (final Object? raw in
        (json['channelList'] as List<Object?>? ?? const [])) {
      final Map<String, Object?> channel = (raw! as Map<Object?, Object?>).cast();
      if (channel['cataid'].toString() != '100000002') continue;
      final Map<String, Object?> content =
          ((channel['content'] as Map<Object?, Object?>?) ?? const {}).cast();
      final Map<String, Object?> courseWrap =
          ((content['course'] as Map<Object?, Object?>?) ?? const {}).cast();
      for (final Object? c
          in (courseWrap['data'] as List<Object?>? ?? const [])) {
        final Map<String, Object?> course = (c! as Map<Object?, Object?>).cast();
        out.add(ChaoxingCourse(
          courseId: course['id'].toString(),
          clazzId: channel['key'].toString(),
          name: (course['name'] ?? '') as String,
        ));
      }
    }
    return dedupe(out);
  }

  /// 同一 (courseId, clazzId) 在 `channelList` 里会出现多次，不去重就会
  /// 对同一门课发重复请求，并把同一条活动收两遍（真机第一版就撞到了）。
  static List<ChaoxingCourse> dedupe(List<ChaoxingCourse> courses) {
    final Set<String> seen = <String>{};
    return courses.where((ChaoxingCourse c) => seen.add(c.key)).toList();
  }
}
