import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';

import 'dao_test_helper.dart';

/// 学期保存的用例层回归测试。
///
/// 缺陷来源（2026-10-18 用户报「右上 ⚙ 里改了周数点保存，像没点到」）：
/// 设置弹层与向导步 3 都写成 `renameSemester` → `setTotalWeeks` → `setFirstWeek`
/// 三次调用，而每个 setter 都拿**同一份旧快照** `copyWith` 后整行写回，
/// 于是后一次把前一次的改动原样盖回去——三个字段里只有最后写的那个生效。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late SemesterUseCase semesters;

  setUp(() async {
    env = await DaoTestDb.open();
    semesters = SemesterUseCase(AppServices(db: env.db));
  });

  tearDown(() => env.close());

  Future<Semester> seed({int totalWeeks = 16}) => semesters.createSemester(
      name: '2025-2026-1',
      firstWeekDate: DateTime.utc(2025, 9, 1),
      totalWeeks: totalWeeks);

  test('saveSemester 一次写完名称、开学周与总周数', () async {
    final Semester s = await seed();
    await semesters.saveSemester(s,
        name: '大三下',
        firstWeekDate: DateTime.utc(2026, 3, 4), // 周三 → 归一化到 2026-03-02
        totalWeeks: 20);

    final Semester? back = await semesters.activeSemester();
    expect(back!.name, '大三下');
    expect(back.totalWeeks, 20);
    expect(back.firstWeekMonday, DateTime.utc(2026, 3, 2),
        reason: '用户选的是那周的任意一天，落库必须是周一');
  });

  test('改总周数不动名称：三个字段各改各的也不会互相盖回', () async {
    final Semester s = await seed();
    await semesters.saveSemester(s,
        name: s.name,
        firstWeekDate: s.firstWeekMonday,
        totalWeeks: 19);
    final Semester? back = await semesters.activeSemester();
    expect(back!.totalWeeks, 19);
    expect(back.name, '2025-2026-1');
    expect(back.firstWeekMonday, DateTime.utc(2025, 9, 1));
  });

  test('空名与越界周数直接拒，不落半套改动', () async {
    final Semester s = await seed();
    expect(
        () => semesters.saveSemester(s,
            name: '  ',
            firstWeekDate: s.firstWeekMonday,
            totalWeeks: 20),
        throwsArgumentError);
    expect(
        () => semesters.saveSemester(s,
            name: '行',
            firstWeekDate: s.firstWeekMonday,
            totalWeeks: Semester.maxTotalWeeks + 1),
        throwsArgumentError);
    final Semester? back = await semesters.activeSemester();
    expect(back!.totalWeeks, 16, reason: '被拒的写不能留下任何一部分');
    expect(back.name, '2025-2026-1');
  });

  test('raiseTotalWeeks 只抬不缩，越上限夹到 30', () async {
    await seed(totalWeeks: 16);
    expect(await semesters.raiseTotalWeeks(10), isNull,
        reason: '缩周数会让已有课程翻不到，不是导入该干的事');
    expect((await semesters.activeSemester())!.totalWeeks, 16);

    final Semester? raised = await semesters.raiseTotalWeeks(19);
    expect(raised!.totalWeeks, 19);
    expect((await semesters.activeSemester())!.totalWeeks, 19);

    final Semester? capped = await semesters.raiseTotalWeeks(40);
    expect(capped!.totalWeeks, Semester.maxTotalWeeks,
        reason: 'DB 有 CHECK(1~30)，不夹取会整条写入炸掉');
  });

  test('还没有学期时抬周数返回 null，不凭空建学期', () async {
    expect(await semesters.activeSemester(), isNull);
    expect(await semesters.raiseTotalWeeks(20), isNull);
  });
}
