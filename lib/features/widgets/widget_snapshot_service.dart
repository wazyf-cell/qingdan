// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/widgets/widget_snapshot.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/platform/widget_bridge.dart';

/// 三份快照的 SharedPreferences 键。
///
/// 原生侧读的是同一个文件（`FlutterSharedPreferences.xml`，键带 `flutter.` 前缀），
/// 改这里的常量必须同步改 `WidgetSnapshot.kt` 的三个常量。
const String kWidgetTodayKey = 'widget.today';
const String kWidgetCourseKey = 'widget.course';
const String kWidgetChaoxingKey = 'widget.chaoxing';

/// 把当前数据写成小组件快照，并通知桌面重画。
///
/// 为什么由应用来写、而不是让原生读 SQLite：数据库有迁移与同步两套语义，
/// 让 Kotlin 直接开库等于把 schema 变成对外契约；快照只有「这屏要显示的字段」，
/// 改起来不影响库。
///
/// 刷新时机：任务/课程/学习通任一模型发通知（600ms 防抖）+ 回到前台 + 启动一次。
class WidgetSnapshotService {
  WidgetSnapshotService({
    required TaskUseCase taskUseCase,
    required SemesterUseCase semesterUseCase,
    required CourseUseCase courseUseCase,
    ChaoxingModel? chaoxing,
    DateTime Function()? clock,
  })  : _tasks = taskUseCase,
        _semesters = semesterUseCase,
        _courses = courseUseCase,
        _chaoxing = chaoxing,
        _clock = clock ?? DateTime.now;

  final TaskUseCase _tasks;
  final SemesterUseCase _semesters;
  final CourseUseCase _courses;
  final ChaoxingModel? _chaoxing;
  final DateTime Function() _clock;

  final List<Listenable> _sources = <Listenable>[];
  Timer? _timer;
  bool _writing = false;
  bool _again = false;

  void attach(Iterable<Listenable> sources) {
    for (final Listenable s in sources) {
      if (_sources.contains(s)) continue;
      _sources.add(s);
      s.addListener(_onChanged);
    }
  }

  void dispose() {
    for (final Listenable s in _sources) {
      s.removeListener(_onChanged);
    }
    _sources.clear();
    _timer?.cancel();
  }

  void _onChanged() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), () {
      unawaited(refresh());
    });
  }

  /// 立即重建三份快照。写失败只打日志：小组件是附加功能，不能影响应用内操作。
  Future<void> refresh() async {
    if (_writing) {
      _again = true;
      return;
    }
    _writing = true;
    try {
      final DateTime now = _clock();
      final List<Task> active = await _tasks.findAllActive();
      final Map<String, Object?> today =
          buildTodaySnapshot(allActive: active, now: now);

      Semester? semester;
      List<Course> onDay = const <Course>[];
      List<TimeDetail> details = const <TimeDetail>[];
      try {
        semester = await _semesters.activeSemester();
        if (semester != null) {
          onDay = await _courses.coursesOn(now);
          details = await _semesters.loadDetailsForSemester(semester.id);
        }
      } catch (e) {
        debugPrint('小组件：读课表失败，按「没有学期」渲染：$e');
      }

      final ChaoxingModel? cx = _chaoxing;
      final Map<String, Object?> course = buildCourseSnapshot(
        semester: semester,
        courses: onDay,
        details: details,
        now: now,
      );
      final Map<String, Object?> chaoxing = buildChaoxingSnapshot(
        tasks: cx?.tasks ?? const <ChaoxingTask>[],
        hidden: cx?.settings.hidden ?? const <String>{},
        now: now,
        fetchedAt: cx?.fetchedAt,
      );

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(kWidgetTodayKey, jsonEncode(today));
      await prefs.setString(kWidgetCourseKey, jsonEncode(course));
      await prefs.setString(kWidgetChaoxingKey, jsonEncode(chaoxing));
      await WidgetBridge.refresh();
    } catch (e) {
      debugPrint('小组件快照写入失败（不影响应用内功能）：$e');
    } finally {
      _writing = false;
      if (_again) {
        _again = false;
        unawaited(refresh());
      }
    }
  }
}
