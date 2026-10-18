import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

import 'dao_test_helper.dart';

/// 作息模板库用例（M6-D §6.2）。
///
/// 钉四件事：① 内置模板不可删、不可改名、不可改节次，且**任何写路径都不给
/// 它记意图**（不记 = 不上云，这就是「内置不参与同步」的实现手段）；
/// ② 「使用」= 复制快照，且 `replaceDetails` **按节次复用原 id**——否则同步
/// 侧会把「改了时间」看成「一删一增」；③ 校验不过一行不写；④ 用户模板照常
/// 记意图（两台设备都该看到）。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late SemesterDao dao;
  late TimetableUseCase templates;
  late SemesterUseCase semesters;

  setUp(() async {
    env = await DaoTestDb.open();
    final AppServices services = AppServices(db: env.db);
    dao = services.semesterDao;
    templates = TimetableUseCase(services);
    semesters = SemesterUseCase(services);
  });
  tearDown(() async => env.close());

  Future<List<Map<String, Object?>>> ops(String entityType,
          [String? operation]) =>
      env.db.query('op_log',
          where: operation == null
              ? 'entity_type = ?'
              : 'entity_type = ? AND operation = ?',
          whereArgs: operation == null
              ? <Object?>[entityType]
              : <Object?>[entityType, operation],
          orderBy: 'rowid ASC');

  List<TimeDetail> twoSections(String timetableId, {int shift = 0}) =>
      <TimeDetail>[
        TimeDetail(id: '', timetableId: timetableId, section: 1, startMinutes: 480 + shift, endMinutes: 525 + shift),
        TimeDetail(id: '', timetableId: timetableId, section: 2, startMinutes: 540 + shift, endMinutes: 585 + shift),
      ];

  group('模板库读与守卫', () {
    test('templates() 含内置模板且排最前，两列标记随行带回', () async {
      final List<TimeTable> list = await templates.templates();
      expect(list.first.id, kBuiltInTimetableId);
      expect(list.first.isBuiltin, isTrue);
      expect(list.first.isTemplate, isTrue);
      await templates.createTemplate(name: '自建', generated: twoSections(''));
      final List<TimeTable> after = await templates.templates();
      expect(after, hasLength(2), reason: '用户模板进库，两台设备都该看到');
      expect(after.last.isBuiltin, isFalse);
      // 用户自建模板的落库必须记意图（timetable create）。
      expect(await ops('timetable', 'create'), hasLength(1));
    });

    test('内置模板：拒删 / 拒改名 / 拒改节次，且 op-log 零条 builtin 意图', () async {
      await expectLater(
        templates.deleteTemplate(kBuiltInTimetableId),
        throwsA(isA<StateError>().having(
            (StateError e) => e.message, 'message', '内置模板不可删除')),
      );
      await expectLater(
        templates.renameTemplate(kBuiltInTimetableId, '改个名'),
        throwsA(isA<StateError>().having(
            (StateError e) => e.message, 'message', '内置模板不可改名')),
      );
      await expectLater(
        templates.saveTemplateDetails(kBuiltInTimetableId, twoSections(kBuiltInTimetableId)),
        throwsA(isA<StateError>()),
      );
      final TimeTable? still = await dao.findTimetableById(kBuiltInTimetableId);
      expect(still?.name, kBuiltInTimetableName);
      expect((await templates.templateDetails(kBuiltInTimetableId)).length,
          kBuiltInTimeDetails.length);
      // 核心钉子：op-log 里绝不能出现 builtin-college 或 builtin-college-NN。
      final List<Map<String, Object?>> tainted = await env.db.query('op_log',
          where: "entity_id LIKE 'builtin-college%'");
      expect(tainted, isEmpty,
          reason: '记了意图就会被 push——内置模板「不参与同步」全靠不写 op-log');
    });

    test('学期专属作息不许从模板库入口删改（_requireTemplate 守卫）', () async {
      final Semester s = await semesters.createSemester(
          name: '学期', firstWeekDate: DateTime.utc(2026, 2, 2));
      final TimeTable own = (await dao.findTimetableForSemester(s.id))!;
      await expectLater(templates.deleteTemplate(own.id),
          throwsA(isA<StateError>()));
      await expectLater(templates.renameTemplate(own.id, '劫持'),
          throwsA(isA<StateError>()));
    });

    test('templateDetails 按节次升序返回', () async {
      final List<TimeDetail> d =
          await templates.templateDetails(kBuiltInTimetableId);
      expect(d.map((TimeDetail x) => x.section).toList(),
          List<int>.generate(kBuiltInTimeDetails.length, (int i) => i + 1));
    });
  });

  group('createTemplate 三来源', () {
    test('空白 / generated / copyFrom 复制内置（复制出的是新行，与原模板脱钩）', () async {
      final TimeTable blank = await templates.createTemplate(name: '空白');
      expect(await templates.templateDetails(blank.id), isEmpty);

      final TimeTable gen =
          await templates.createTemplate(name: '两节', generated: twoSections(''));
      expect((await templates.templateDetails(gen.id)).length, 2);

      final TimeTable copied = await templates.createTemplate(
          name: '复制内置', copyFromId: kBuiltInTimetableId);
      final List<TimeDetail> copiedDetails =
          await templates.templateDetails(copied.id);
      expect(copiedDetails.length, kBuiltInTimeDetails.length);
      expect(copiedDetails.map((TimeDetail d) => d.id).toSet(),
          isNot(contains('$kBuiltInTimetableId-01')),
          reason: '新行新 id：改副本不能碰到内置原行');

      // 改副本不影响内置。
      expect(await templates.saveTemplateDetails(copied.id, <TimeDetail>[
        TimeDetail(id: '', timetableId: copied.id, section: 1, startMinutes: 600, endMinutes: 645),
      ]), isNull);
      expect((await templates.templateDetails(kBuiltInTimetableId)).first.startMinutes, 480);
      // copyFrom 路径同样不许给 builtin 记意图。
      final List<Map<String, Object?>> tainted = await env.db.query('op_log',
          where: "entity_id LIKE 'builtin-college%'");
      expect(tainted, isEmpty);
    });

    test('generated 非法直接拒（ArgumentError），库里不留半截模板', () async {
      final List<TimeTable> before = await templates.templates();
      await expectLater(
        templates.createTemplate(name: '坏表', generated: <TimeDetail>[
          TimeDetail(id: '', timetableId: '', section: 1, startMinutes: 600, endMinutes: 500),
        ]),
        throwsA(isA<ArgumentError>()),
      );
      expect((await templates.templates()).length, before.length);
    });
  });

  group('改名 / 删除 / 保存节次', () {
    test('renameTemplate 改名并记一条 timetable update 意图', () async {
      final TimeTable t = await templates.createTemplate(name: '旧名');
      await templates.renameTemplate(t.id, '新名');
      expect((await dao.findTimetableById(t.id))!.name, '新名');
      final List<Map<String, Object?>> updates = await ops('timetable', 'update');
      expect(updates, hasLength(1));
      expect(updates.single['entity_id'], t.id);
    });

    test('deleteTemplate 连带节次删干净，time_detail 与 timetable 各有 delete 意图', () async {
      final TimeTable t =
          await templates.createTemplate(name: '删我', generated: twoSections(''));
      final List<String> detailIds = (await templates.templateDetails(t.id))
          .map((TimeDetail d) => d.id)
          .toList();
      await templates.deleteTemplate(t.id);
      expect(await dao.findTimetableById(t.id), isNull);
      expect(await env.db.query('time_details',
          where: 'timetable_id = ?', whereArgs: <Object?>[t.id]), isEmpty);
      expect((await ops('timetable', 'delete')).map((Map<String, Object?> r) => r['entity_id']),
          contains(t.id));
      expect((await ops('time_detail', 'delete')).map((Map<String, Object?> r) => r['entity_id']),
          containsAll(detailIds));
    });

    test('saveTemplateDetails：校验不过返回错误串且一行不写；通过返回 null', () async {
      final TimeTable t =
          await templates.createTemplate(name: '校验', generated: twoSections(''));
      final List<TimeDetail> untouchedBefore =
          await templates.templateDetails(t.id);
      final String? err = await templates.saveTemplateDetails(t.id, <TimeDetail>[
        TimeDetail(id: '', timetableId: t.id, section: 1, startMinutes: 480, endMinutes: 525),
        TimeDetail(id: '', timetableId: t.id, section: 2, startMinutes: 500, endMinutes: 600),
      ]);
      expect(err, contains('重叠'));
      final List<TimeDetail> afterFail = await templates.templateDetails(t.id);
      expect(afterFail.map((TimeDetail d) => d.startMinutes),
          untouchedBefore.map((TimeDetail d) => d.startMinutes));

      expect(await templates.saveTemplateDetails(t.id, twoSections('', shift: 30)), isNull);
      expect((await templates.templateDetails(t.id)).first.startMinutes, 510);
    });
  });

  group('applyTemplateToSemester（「使用」= 复制快照）', () {
    test('改时间后 apply：节次 id 被复用（不是删+增），学期与模板脱钩', () async {
      final TimeTable tpl = await templates.createTemplate(
          name: '源模板', generated: twoSections('', shift: 15));
      final Semester s = await semesters.createSemester(
          name: '上课的学期', firstWeekDate: DateTime.utc(2026, 2, 2));
      final TimeTable own = (await dao.findTimetableForSemester(s.id))!;
      // 学期建自内置模板（12 节）；换成两节的源模板：2 节复用 id、其余删掉记 delete。
      final Map<int, String> idsBefore = {
        for (final TimeDetail d in await dao.findDetails(own.id)) d.section: d.id,
      };
      final int opsBefore = (await env.db.query('op_log')).length;

      await templates.applyTemplateToSemester(
          semesterId: s.id, templateId: tpl.id);

      final List<TimeDetail> after = await dao.findDetails(own.id);
      expect(after.length, 2);
      expect(after[0].id, idsBefore[1], reason: '同节次必须复用原 id：同步侧才是 update 而不是删+增');
      expect(after[1].id, idsBefore[2]);
      expect(after[0].startMinutes, 495);
      final List<Map<String, Object?>> newOps =
          (await env.db.query('op_log', orderBy: 'rowid ASC'))
              .skip(opsBefore)
              .toList();
      expect(newOps.where((Map<String, Object?> r) => r['entity_type'] == 'time_detail' && r['operation'] == 'create'),
          isEmpty, reason: 'apply 不该新增节次行');
      expect(newOps.where((Map<String, Object?> r) => r['operation'] == 'update')
          .map((Map<String, Object?> r) => r['entity_id']), containsAll(<String>[idsBefore[1]!, idsBefore[2]!]),
          reason: '前 2 节走 update 通道');
      expect(newOps.where((Map<String, Object?> r) => r['operation'] == 'delete'), hasLength(10),
          reason: '内置 12 节里没被模板覆盖到的 10 节逐条记 delete');
      // 模板本体没被动过。
      expect((await templates.templateDetails(tpl.id)).length, 2);

      // 脱钩：再改模板，学期不变。
      await templates.saveTemplateDetails(tpl.id, twoSections(tpl.id, shift: 60));
      expect((await dao.findDetails(own.id))[0].startMinutes, 495);
    });

    test('apply 内置模板不产生任何 builtin 意图（复制出来的全是新 id）', () async {
      final Semester s = await semesters.createSemester(
          name: '空学期占位', firstWeekDate: DateTime.utc(2026, 2, 2),
          templateId: kBuiltInTimetableId);
      final TimeTable own = (await dao.findTimetableForSemester(s.id))!;
      final int opsBefore = (await env.db.query('op_log')).length;
      await templates.applyTemplateToSemester(
          semesterId: s.id, templateId: kBuiltInTimetableId);
      final List<Map<String, Object?>> added =
          (await env.db.query('op_log', orderBy: 'rowid ASC'))
              .skip(opsBefore)
              .toList();
      expect(added, isEmpty, reason: '同内容 apply：replaceDetails 判无变化，一条都不写');
      expect(
          await env.db.query('op_log', where: "entity_id LIKE 'builtin-college%'"),
          isEmpty);
      expect((await dao.findDetails(own.id)).length, kBuiltInTimeDetails.length);
    });

    test('老学期没有专属作息行时 apply 顺手补建「<学期名> 作息」', () async {
      // 用 DAO.insert 造「v6 之前的老学期」形状：只有 semesters 行、没有作息行。
      final Semester legacy =
          await dao.insert(name: '老学期', firstWeekMonday: DateTime.utc(2025, 9, 1));
      expect(await dao.findTimetableForSemester(legacy.id), isNull);
      await templates.applyTemplateToSemester(
          semesterId: legacy.id, templateId: kBuiltInTimetableId);
      final TimeTable? table = await dao.findTimetableForSemester(legacy.id);
      expect(table, isNotNull);
      expect(table!.name, '老学期 作息');
      expect((await dao.findDetails(table.id)).length, kBuiltInTimeDetails.length);
    });

    test('模板不存在 / 学期不存在都拒，不留孤儿', () async {
      await expectLater(
          templates.applyTemplateToSemester(
              semesterId: 'nope', templateId: 'nope-template'),
          throwsA(isA<StateError>()));
      final Semester s = await semesters.createSemester(
          name: '在的', firstWeekDate: DateTime.utc(2026, 2, 2));
      await expectLater(
          templates.applyTemplateToSemester(semesterId: s.id, templateId: 'ghost'),
          throwsA(isA<StateError>()),
      );
      expect((await dao.findTimetableForSemester(s.id)) != null, isTrue);
    });
  });
}
