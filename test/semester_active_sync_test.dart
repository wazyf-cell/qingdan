import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/sync/sync_state_writer.dart' show rowToSyncJson;

import 'sync_test_fixture.dart';

/// `is_active` 剔除出同步（M6-D §四，本批最容易出事的一步）。
///
/// 危害形状不是「数据不一致」，是**两台设备互抢当前学期**：手机上翻一眼上学期，
/// Windows 同步之后也跟着变，回来打开应用看见的是上学期的课表。修法是把
/// 「哪个学期是当前」定性成设备本地视图（与 `task_tags` 同一待遇，2026-10-10 先例）。
///
/// 三条实现手段各自都要钉住：① 上云剔除；② 拉下来插入时一律 0（DDL 默认是 1，
/// `INSERT OR REPLACE` 不给值就会打回 1）；③ 本地 UPDATE 永不写这列（调用方拿的
/// 是加载时的旧快照，写回去会把用户刚选的当前学期悄悄改回来）。
void main() {
  late SyncTestFixture fx;

  setUp(() async {
    fx = await SyncTestFixture.create();
  });

  tearDown(() async => fx.dispose());

  SemesterUseCase useCase(int device) => SemesterUseCase(
      device == 1 ? fx.device1.services : fx.device2.services);

  Future<List<String>> activeIds(int device) async {
    final List<Map<String, Object?>> rows = await (device == 1
            ? fx.device1.db
            : fx.device2.db)
        .query('semesters', where: 'is_active = 1');
    return <String>[for (final Map<String, Object?> r in rows) r['id']! as String]
      ..sort();
  }

  Future<int?> isActive(int device, String id) async {
    final Map<String, Object?>? row = await (device == 1
            ? fx.device1.db
            : fx.device2.db)
        .query('semesters', where: 'id = ?', whereArgs: <Object?>[id], limit: 1)
        .then((List<Map<String, Object?>> r) => r.isEmpty ? null : r.first);
    return row?['is_active'] as int?;
  }

  test('序列化：semester 的云端 JSON 里没有 is_active / isActive 键', () {
    final Map<String, Object?> json = rowToSyncJson(<String, Object?>{
      'id': 's1',
      'name': '2026-2027-1',
      'first_week_monday': 1,
      'total_weeks': 20,
      'is_active': 1,
      'created_time': 1,
      'modified_time': 2,
    });
    expect(json.containsKey('isActive'), isFalse);
    expect(json.containsKey('is_active'), isFalse);
    expect(json['name'], '2026-2027-1', reason: '只剔本地列，别的列照常走');
  });

  test('双端：A 切当前学期不会改掉 B 的当前学期', () async {
    final Semester a1 = await useCase(1).createSemester(
        name: 'A-大一上', firstWeekDate: DateTime.utc(2025, 9, 1));
    final Semester a2 = await useCase(1).createSemester(
        name: 'A-大一下',
        firstWeekDate: DateTime.utc(2026, 2, 2),
        setActive: false); // M6-D §6.1：默认 setActive=true 会抢当前，这里要验的是不抢
    expect(await activeIds(1), <String>[a1.id],
        reason: '第二个学期建出来不该抢 active（DDL 默认 1 的陷阱）');
    await useCase(1).activeSemester(); // 读一次，确认自愈没改变结论
    expect(await isActive(1, a2.id), 0);

    expect((await fx.syncDevice(1)).errors, isEmpty);

    // B 设备自己先建一个学期：它的「当前」是它自己的事。
    final Semester b1 = await useCase(2).createSemester(
        name: 'B-我的学期', firstWeekDate: DateTime.utc(2026, 3, 2));
    final r2 = await fx.syncDevice(2);
    expect(r2.errors, isEmpty);

    expect(await isActive(2, a1.id), 0,
        reason: '远端来的学期一律非当前（插入必须显式给 0，否则吃 DEFAULT 1）');
    expect(await isActive(2, a2.id), 0);
    expect(await activeIds(2), <String>[b1.id], reason: 'B 的当前学期不能被抢走');
    expect((await useCase(2).allSemesters()).length, 3,
        reason: '学期本身要照常同步过来，剔的只是 is_active 这一列');

    // A 再切一次当前学期并同步：B 端必须毫无感觉。
    await fx.device1.services.semesterDao.setActiveSemester(a2.id);
    expect(await activeIds(1), <String>[a2.id]);
    await fx.syncDevice(1);
    await fx.syncDevice(2);
    expect(await activeIds(2), <String>[b1.id],
        reason: 'A 的浏览动作传到了 B，就是这次要修的那个形状');
    expect(await isActive(2, a2.id), 0);
  });

  test('B 的学期同步到 A 后，同样不会接管 A 的当前学期', () async {
    final Semester a1 = await useCase(1).createSemester(
        name: 'A-学期', firstWeekDate: DateTime.utc(2025, 9, 1));
    final Semester b1 = await useCase(2).createSemester(
        name: 'B-学期', firstWeekDate: DateTime.utc(2026, 2, 2));
    await fx.syncDevice(1);
    await fx.syncDevice(2);
    await fx.syncDevice(1);

    expect(await isActive(1, b1.id), 0);
    expect(await activeIds(1), <String>[a1.id]);
  });

  test('云端实体 JSON 里查不到 is_active（防只改一侧）', () async {
    final Semester a1 = await useCase(1).createSemester(
        name: 'A-上传检查', firstWeekDate: DateTime.utc(2025, 9, 1));
    await fx.syncDevice(1);

    final File file = File('${fx.cloudDir.path}/entities/semester/${a1.id}.json');
    expect(file.existsSync(), isTrue, reason: '先确认云端真有这个对象');
    final Map<String, Object?> json =
        (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
    expect(json.keys, isNot(contains('is_active')));
    expect(json.keys, isNot(contains('isActive')));
    expect(json['name'], 'A-上传检查');
  });

  test('本地 UPDATE 永不写 is_active：陈旧快照不能把当前学期改回去', () async {
    final SemesterUseCase uc = useCase(1);
    final Semester s1 =
        await uc.createSemester(name: '旧名', firstWeekDate: DateTime.utc(2025, 9, 1));
    final Semester s2 =
        await uc.createSemester(
            name: '第二个',
            firstWeekDate: DateTime.utc(2026, 2, 2),
            setActive: false); // 保持「当前仍是 s1」，旧名快照才有意义
    // 拿着 s1「还是当前学期」时的旧快照，等 s2 被切成当前之后再改 s1 的名字。
    final Semester stale = (await uc.activeSemester())!;
    await fx.device1.services.semesterDao.setActiveSemester(s2.id);

    await fx.device1.services.semesterDao.update(stale.copyWith(name: '改个名'));

    expect(await isActive(1, s1.id), 0,
        reason: 'UPDATE 写回 is_active=1 就会同时出现两个当前学期');
    expect(await activeIds(1), <String>[s2.id]);
    expect((await uc.allSemesters()).firstWhere((Semester s) => s.id == s1.id).name,
        '改个名', reason: '业务列照常写进去，别把剔除做成什么都不写');
  });

  test('findActive 自愈：一个 active 都没有时选最新学期并修好标记', () async {
    await useCase(1)
        .createSemester(name: '早的', firstWeekDate: DateTime.utc(2025, 9, 1));
    final Semester later = await useCase(1)
        .createSemester(name: '晚的', firstWeekDate: DateTime.utc(2026, 2, 2));
    // 手改成「一个都没选中」——同步来的库、迁移边缘形状都会长这样。
    await fx.device1.db
        .rawUpdate('UPDATE semesters SET is_active = 0');
    expect(await activeIds(1), isEmpty);

    final Semester? healed = await useCase(1).activeSemester();

    expect(healed?.name, '晚的', reason: '回退到 created_time 最新的那一个');
    expect(await activeIds(1), <String>[later.id], reason: '顺手把标记修好');
  });
}
