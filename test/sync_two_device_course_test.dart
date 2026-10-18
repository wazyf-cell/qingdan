/// 课表域的双端离线分叉验收（M4a S6 的核心验收项）。
///
/// 覆盖三条：① 两端各改同一门课的**不同字段**必须都保住（字段级 LWW 的卖点）；
/// ② 两端改同一节作息的**同一字段**必须收敛到时间新的那份——这条就是
/// `time_details` 需要 v5 时间戳列的原因，缺列时两端各留各的、永不收敛；
/// ③ UID 必须由两台设备各自算出同一个值（跨设备去重与同步的共同前提）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/sync/sync_report.dart';

import 'sync_test_fixture.dart';

void main() {
  late SyncTestFixture fx;

  setUp(() async {
    fx = await SyncTestFixture.create();
    // 设备1 建好学期 + 4 节作息 + 一门课，两端先建立基线。
    final Semester s = await fx.device1.services.semesterDao.insert(
        name: '2025-2026-1', firstWeekMonday: DateTime.utc(2025, 9, 1));
    final TimeTable t = await fx.device1.services.semesterDao
        .createTimetable(name: '默认作息', semesterId: s.id);
    await fx.device1.services.semesterDao.replaceDetails(
        t.id,
        generateTimeDetails(
            timetableId: t.id,
            firstStartMinutes: 480,
            lessonMinutes: 45,
            breakMinutes: 10,
            sectionCount: 4));
    await fx.device1.services.courseDao.insert(Course(
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
          semesterId: s.id,
          teacher: '小明',
          location: '逸夫楼201',
        ));
    expect((await fx.syncDevice(1)).errors, isEmpty);
    expect((await fx.syncDevice(2)).errors, isEmpty);
  });

  tearDown(() async => fx.dispose());

  Future<Course> courseOn(DeviceHarness d) async {
    final List<Course> rows = await d.services.courseDao.findActive();
    expect(rows, hasLength(1), reason: '两端都应当只有那一门同步来的课');
    return rows.single;
  }

  Future<TimeDetail> sectionOne(DeviceHarness d) async {
    final List<Map<String, Object?>> rows = await d.db
        .query('time_details', where: 'section = ?', whereArgs: <Object?>[1]);
    return TimeDetail.fromMap(rows.single);
  }

  test('两端各改不同字段：地点与老师都保住，不互相覆盖', () async {
    final Course mine = await courseOn(fx.device1);
    final Course theirs = await courseOn(fx.device2);

    // 设备1 只改地点；设备2 离线状态下只改老师。
    await fx.device1.services.courseDao
        .update(mine.copyWith(location: '逸夫楼302'));
    await fx.device2.services.courseDao
        .update(theirs.copyWith(teacher: '小红'));

    expect((await fx.syncDevice(1)).errors, isEmpty);
    expect((await fx.syncDevice(2)).errors, isEmpty);
    // 第三轮才收敛：设备1 的第二轮同步只能拉到设备2 已上传的东西，而设备2 是
    // 在它之后才推的（ eventual consistency，M3 的验收同样是 sync1/2/1）。
    expect((await fx.syncDevice(1)).errors, isEmpty);

    for (final DeviceHarness d in <DeviceHarness>[fx.device1, fx.device2]) {
      final Course c = await courseOn(d);
      expect(c.location, '逸夫楼302', reason: '设备1 的地点改动必须保住');
      expect(c.teacher, '小红', reason: '设备2 的老师改动必须保住');
    }
  });

  test('同一节同一字段：编辑时间新的那份赢，与谁后推送无关（v5 时间戳的意义）',
      () async {
    // 形状刻意选成「后推送的那份其实是更早的编辑」：
    //  · 有列级时间戳 → 合并按 modifiedTime 判，设备1 的新值赢；
    //  · 没有（v5 之前）→ `_remoteNewer` 恒 false → 恒判本地胜 → 设备2 那条
    //    更早的编辑反而把新值覆盖掉，且两端照样「收敛」，收敛到错的那份。
    // 所以断言的不是「两端一致」，而是「一致地等于新值」。
    final TimeDetail base = await sectionOne(fx.device1);

    final List<TimeDetail> d1Details =
        await fx.device1.services.semesterDao.findDetails(base.timetableId);
    await fx.device1.services.semesterDao.replaceDetails(
        base.timetableId,
        <TimeDetail>[
          for (final TimeDetail d in d1Details)
            if (d.section == 1)
              d.copyWith(startMinutes: 500, endMinutes: 545)
            else
              d,
        ]);
    expect((await fx.syncDevice(1)).errors, isEmpty); // 设备1 的新值先上云

    // 设备2 离线期间做的是一条**更早**的编辑（这里刻意把时间戳拨回一分钟前）。
    final List<TimeDetail> d2Details =
        await fx.device2.services.semesterDao.findDetails(base.timetableId);
    await fx.device2.services.semesterDao.replaceDetails(
        base.timetableId,
        <TimeDetail>[
          for (final TimeDetail d in d2Details)
            if (d.section == 1)
              d.copyWith(startMinutes: 460, endMinutes: 505)
            else
              d,
        ]);
    final TimeDetail d2Changed = await sectionOne(fx.device2);
    await fx.forceRowModifiedTime(
        fx.device2,
        'time_details',
        d2Changed.id,
        DateTime.now().toUtc().millisecondsSinceEpoch - 60000);

    expect((await fx.syncDevice(2)).errors, isEmpty);
    expect((await sectionOne(fx.device2)).startMinutes, 500,
        reason: '设备2 后推送，但它的编辑更早，必须让位给设备1 的新值');
    expect((await fx.syncDevice(1)).errors, isEmpty);
    expect((await sectionOne(fx.device1)).startMinutes, 500);
  });

  test('老行形状（时间戳为 NULL）推得出去、落得下、之后还改得动 —— 真机 Android 库升 v5 后首轮的彩排', () async {
    // 真机那台设备上 12 节作息是 v4 时代建的：内容与 op-log 都在，但 v5 之前
    // 没有时间戳列，升级后两列全 NULL。上传载荷按**同步时刻的当前行**现读
    // （intent_resolver.dart:119、sync_push.dart:107），所以把时间戳抹回 NULL
    // 就复现了那份 `modifiedTime: null` 的 JSON —— 这是 S6-4 要面对的真实数据。
    final TimeTable legacy = await fx.device2.services.semesterDao
        .createTimetable(name: '老作息');
    await fx.device2.services.semesterDao.replaceDetails(
        legacy.id,
        generateTimeDetails(
            timetableId: legacy.id,
            firstStartMinutes: 480,
            lessonMinutes: 45,
            breakMinutes: 10,
            sectionCount: 12));
    await fx.device2.db.execute(
      'UPDATE time_details SET created_time = NULL, modified_time = NULL '
      'WHERE timetable_id = ?',
      <Object?>[legacy.id],
    );

    expect((await fx.syncDevice(2)).errors, isEmpty,
        reason: '老行上传不得因为时间戳缺失而报错');
    expect((await fx.syncDevice(1)).errors, isEmpty);

    final List<Map<String, Object?>> landed = await fx.device1.db.query(
      'time_details',
      where: 'timetable_id = ?',
      whereArgs: <Object?>[legacy.id],
      orderBy: 'section ASC',
    );
    expect(landed, hasLength(12),
        reason: '12 节老行必须整体到达对端（父 timetable 先落库才有这些行）');
    expect(
      landed.where((Map<String, Object?> r) => r['modified_time'] == null).length,
      12,
      reason: 'NULL 到对端仍是 NULL；实现若"顺手补 0"，这节会恒被判为 1970 年的最旧编辑',
    );

    // 老行不是死数据：对端编辑它、推回来，本机必须收（base 的时间戳是 null，
    // 「本地未改 → 取远端」这条分支要先于 LWW 生效）。
    // 必须走 DAO 而不是裸 update：同步意图来自 op-log，绕过用例层的写入
    // 不会产生意图，测试就会红在「自己没记日志」而不是被测行为上。
    final String legacySectionId = landed.first['id']! as String;
    final List<TimeDetail> d1Details =
        await fx.device1.services.semesterDao.findDetails(legacy.id);
    await fx.device1.services.semesterDao.replaceDetails(
        legacy.id,
        <TimeDetail>[
          for (final TimeDetail d in d1Details)
            if (d.id == legacySectionId)
              d.copyWith(startMinutes: 500, endMinutes: 545)
            else
              d,
        ]);
    expect((await fx.syncDevice(1)).errors, isEmpty);
    expect((await fx.syncDevice(2)).errors, isEmpty);
    final Map<String, Object?> afterPull = (await fx.device2.db.query(
      'time_details',
      where: 'id = ?',
      whereArgs: <Object?>[legacySectionId],
      limit: 1,
    ))
        .single;
    expect(afterPull['start_minutes'], 500,
        reason: '老行被对端编辑后必须能刷回来');
  });

  test('UID 由两台设备各自算出同一个值', () async {
    final Course c = await courseOn(fx.device2);
    expect(
      c.uid,
      courseUidOf(
          name: c.name,
          weekday: c.weekday,
          startSection: c.startSection,
          endSection: c.endSection,
          weeks: c.weeks),
      reason: '设备2 本地重算的 UID 必须等于设备1 传来的（否则同步后课会重复）',
    );
    final SyncReport r = await fx.syncDevice(2);
    expect(r.uploaded, 0, reason: '内容没变就不该重传');
  });
}
