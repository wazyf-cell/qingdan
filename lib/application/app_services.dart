import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../data/course_dao.dart';
import '../data/op_log_writer.dart';
import '../data/semester_dao.dart';
import '../data/subtask_dao.dart';
import '../data/sync_state_dao.dart';
import '../data/tag_dao.dart';
import '../data/task_dao.dart';
import '../data/task_list_dao.dart';

/// 数据层依赖容器：main 装配一次，用例层共享同一连接。
///
/// UI 层不得接触本类与任何 DAO（AGENTS.md 铁律），只持有用例层对象。
class AppServices {
  /// [onLocalWrite] 是 M3 同步触发回调：四个 DAO 共用同一个 OpLogWriter，
  /// 保证任何写路径（任务/清单/子任务/标签）都通告同一处（设计稿 §2.1）。
  AppServices({required Database db, void Function()? onLocalWrite})
      : this._(db, OpLogWriter(onLocalWrite: onLocalWrite));

  AppServices._(Database db, OpLogWriter opLog)
      : taskListDao = TaskListDao(db, opLog: opLog),
        taskDao = TaskDao(db, opLog: opLog),
        subtaskDao = SubtaskDao(db, opLog: opLog),
        tagDao = TagDao(db, opLog: opLog),
        // 课表域与任务域共用同一个 opLog（M4a S6）：写库后必须敲 `onLocalWrite`
        // 才会触发同步。S5 之前故意不共享，是因为那时 `kEntityTypes` 里还没有
        // 课表四类，触发一次同步只会空跑并白烧坚果云配额（实测约 300 请求/3.5
        // 分钟即封号）。现在课表已进 `kEntityTypes`，空跑的前提不成立了。
        semesterDao = SemesterDao(db, opLog: opLog),
        courseDao = CourseDao(db, opLog: opLog),
        syncStateDao = SyncStateDao(db);

  final TaskListDao taskListDao;
  final TaskDao taskDao;
  final SubtaskDao subtaskDao;
  final TagDao tagDao;

  /// 课表域（M4a）。
  final SemesterDao semesterDao;
  final CourseDao courseDao;

  /// 同步基线（M2，v3 迁移新增表）。
  final SyncStateDao syncStateDao;
}
