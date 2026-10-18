/// 外键落库顺序回归测试（2026-10-09 S6 真机 bug 的证伪测试）。
///
/// 为什么必须有这条测试：`kEntityTypes` 曾把 `task` 排在 `list` 之前，而
/// `tasks.list_id → lists(id)` 是外键。设备 B 全新库首同步时任务先落库、
/// 清单还没落库 → `SqliteException(787): FOREIGN KEY constraint failed`。
/// 既有 194 个测试全绿也抓不到，因为 `sync_two_device_test.dart` 的夹具里
/// 任务 `list_id` 恒为 null（**外键值为 NULL 时 SQLite 不校验**）。
///
/// 为什么不写进 sync_two_device_test.dart：那个文件（212 行）测的是「两端
/// 已有基线」的合并 / LWW 语义，加进来会顶到 300 行红线；而本文件测的是
/// 「设备 B 全新库首同步」的**落库顺序与外键**，失败原因与修复面完全不同。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/tag.dart';
import 'package:qingdan/domain/time_table.dart';
// Subtask 与 Task 同在 domain/task.dart（没有独立的 subtask.dart），
// 这里必须从 task.dart 导入，否则会误以为存在 domain/subtask.dart。
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/sync/sync_report.dart';
import 'package:qingdan/sync/sync_serializer.dart';

import 'sync_test_fixture.dart';

void main() {
  late SyncTestFixture fx;

  setUp(() async {
    fx = await SyncTestFixture.create();
  });

  tearDown(() async {
    await fx.dispose();
  });

  test('不变量：kEntityTypes 顺序必须满足外键依赖（清单先于任务、任务先于子任务）', () {
    // 直接锁常量：顺序一旦被改回 ['task', 'list', ...]，这条在最前面就红，
    // 且报错文案直接点名原因，不必等端到端跑完才定位。
    expect(
      kEntityTypes.indexOf('list'),
      lessThan(kEntityTypes.indexOf('task')),
      reason: 'tasks.list_id → lists(id)：清单必须先于任务落库；实际顺序 $kEntityTypes',
    );
    expect(
      kEntityTypes.indexOf('task'),
      lessThan(kEntityTypes.indexOf('subtask')),
      reason: 'subtasks.task_id → tasks(id)：任务必须先于子任务落库；实际顺序 $kEntityTypes',
    );
    // M4a S6 课表链：timetables.semester_id 与 courses.semester_id → semesters，
    // time_details.timetable_id → timetables。四类整体排在 list 之前。
    expect(
      kEntityTypes.indexOf('semester'),
      lessThan(kEntityTypes.indexOf('timetable')),
      reason: 'timetables.semester_id → semesters(id)；实际顺序 $kEntityTypes',
    );
    expect(
      kEntityTypes.indexOf('timetable'),
      lessThan(kEntityTypes.indexOf('time_detail')),
      reason: 'time_details.timetable_id → timetables(id)；实际顺序 $kEntityTypes',
    );
    expect(
      kEntityTypes.indexOf('semester'),
      lessThan(kEntityTypes.indexOf('course')),
      reason: 'courses.semester_id → semesters(id)；实际顺序 $kEntityTypes',
    );
    expect(
      kEntityTypes.indexOf('course'),
      lessThan(kEntityTypes.indexOf('list')),
      reason: '课表四类整体排在任务域之前；实际顺序 $kEntityTypes',
    );
    // 每个同步类型都必须能映射到表，且不重不漏：顺序常量漏掉一个类型会
    // 静默丢失该类型的双向同步（两端永不收敛，且不报任何错）。
    expect(kEntityTypes.toSet(), kEntityTable.keys.toSet());
    expect(kEntityTypes.length, kEntityTypes.toSet().length, reason: '类型不得重复');
  });

  test('前置守卫：夹具的磁盘库 PRAGMA foreign_keys 确实为 ON（否则下面那条会假绿）', () async {
    for (final DeviceHarness device in <DeviceHarness>[fx.device1, fx.device2]) {
      final List<Map<String, Object?>> rows =
          await device.db.rawQuery('PRAGMA foreign_keys');
      expect(rows.first.values.first, 1,
          reason: '【${device.dbPath}】外键必须开启；关着的话外键测试永远绿');
    }
  });

  test('★核心：设备1 建清单+归属该清单的任务+子任务，全新设备2 首同步必须零错误', () async {
    // 1. 设备1 按「清单 → 任务 → 子任务」建数据：这是产生外键引用的唯一方式，
    //    也正因如此，只要任务带 list_id，设备2 就必然踩到落库顺序。
    final TaskList list =
        await fx.device1.services.taskListDao.insert(name: '工作');
    final Task task = await fx.device1.services.taskDao.insert(
      title: '归属清单的任务',
      listId: list.id,
    );
    final Subtask sub = await fx.device1.services.subtaskDao.insert(
      taskId: task.id,
      title: '子步骤',
    );
    final Tag tag = await fx.device1.services.tagDao.insert(name: '重要');

    // 2. 设备1 上传。
    final SyncReport r1 = await fx.syncDevice(1);
    expect(r1.errors, isEmpty, reason: '设备1 上传不应有错误；实际：${r1.errors}');

    // 3. 设备2 首同步。设备2 是全新库（既无清单也无任务），这正是真机 S6
    //    首次同步的形状——上一次真机 bug 就在这里炸。
    final SyncReport r2 = await fx.syncDevice(2);

    // 4. 先断报告：pull 内部的插入失败被 `catch` 收进 errors 而不上抛，
    //    所以「errors 里有 787」是这条 bug 最直接的证据（异常原文就在串里）。
    expect(r2.errors, isEmpty, reason: '设备2 首同步必须零错误；实际捕获：${r2.errors}');

    // 5. 清单确实先到了。
    expect(await fx.device2.services.taskListDao.findById(list.id), isNotNull,
        reason: '清单必须先于任务落库');

    // 6. 任务到了，且外键值原样保留（不是被外键失败丢掉、也不是被写成 NULL）。
    final Map<String, Object?>? taskRow = await fx.device2.taskRow(task.id);
    expect(taskRow, isNotNull, reason: '设备2 首同步后必须能查到该任务');
    expect(taskRow!['list_id'], list.id,
        reason: 'tasks.list_id 必须指向设备1 的清单 id，不能是 null');

    // 7. 子任务也到了：subtasks.task_id → tasks(id)，任务先落库它才插得进。
    final List<Map<String, Object?>> subs = await fx.device2.db.query(
      'subtasks',
      where: 'task_id = ?',
      whereArgs: <Object?>[task.id],
    );
    expect(subs.length, 1, reason: '子任务必须随父任务同步到全新设备2');
    expect(subs.first['id'], sub.id);

    // 8. 标签同批一起过（tag 无外键，但顺序常量漏掉它会静默不同步）。
    expect(await fx.device2.services.tagDao.findById(tag.id), isNotNull);
  });

  test('★核心：设备1 的学期+作息+课（带批次外键）同步到全新设备2，零错误且剔除 import_batch_id',
      () async {
    final Semester semester = await fx.device1.services.semesterDao.insert(
        name: '2025-2026-1', firstWeekMonday: DateTime.utc(2025, 9, 1));
    final TimeTable table = await fx.device1.services.semesterDao
        .createTimetable(name: '默认作息', semesterId: semester.id);
    await fx.device1.services.semesterDao.replaceDetails(
        table.id, generateTimeDetails(
            timetableId: table.id,
            firstStartMinutes: 480,
            lessonMinutes: 45,
            breakMinutes: 10,
            sectionCount: 4));
    // 本地先建一条批次行，让 courses.import_batch_id 是**真外键**（非 NULL 才会被校验）。
    final ImportBatch batch = await fx.device1.services.courseDao
        .insertBatch(ImportBatch(
            id: 'b1', fileName: 'x.csv', importedAt: DateTime.utc(2025, 9, 2)));
    final Course course = await fx.device1.services.courseDao.insert(Course(
          id: '',
          uid: courseUidOf(
              name: '高等数学',
              weekday: 1,
              startSection: 1,
              endSection: 2,
              weeks: <int>[1, 2, 3]),
          name: '高等数学',
          weekday: 1,
          startSection: 1,
          endSection: 2,
          weeks: const <int>[1, 2, 3],
          semesterId: semester.id,
          origin: CourseOrigin.import,
          importBatchId: batch.id,
        ));

    expect((await fx.syncDevice(1)).errors, isEmpty);
    final SyncReport r2 = await fx.syncDevice(2);
    expect(r2.errors, isEmpty,
        reason: '设备2 首同步课表必须零错误（787 就藏在这里）；实际：${r2.errors}');

    final Map<String, Object?>? remote = (await fx.device2.db
            .query('courses', where: 'id = ?', whereArgs: <Object?>[course.id]))
        .cast<Map<String, Object?>>()
        .firstOrNull;
    expect(remote, isNotNull, reason: '课程必须同步到全新设备');
    expect(remote!['semester_id'], semester.id,
        reason: 'courses.semester_id 不能变 NULL（NULL 不校验外键＝假绿）');
    // 批次不同步：接收端这一列必须为空，否则它指向一个对端不存在的行。
    expect(remote['import_batch_id'], isNull,
        reason: 'import_batch_id 必须在序列化两侧剔除');
    expect(remote['uid'], course.uid, reason: 'UID 跨设备必须逐字节一致');

    final List<Map<String, Object?>> details = await fx.device2.db
        .query('time_details', where: 'timetable_id = ?', whereArgs: <Object?>[table.id]);
    expect(details, hasLength(4), reason: '作息四节随表同步（time_detail 排在 timetable 之后）');
    expect(
        details.every((Map<String, Object?> r) => r['modified_time'] != null),
        isTrue,
        reason: 'v5 的时间戳得真的同步过去，否则对端 LWW 恒判本地胜');
  });
}
