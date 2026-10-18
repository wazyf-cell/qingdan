import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// 「未排时间」与空作息的界面契约（2026-10-18 模拟器实测缺陷）。
///
/// 现场：教务抓取导入 30 门课，但 `time_details` 一节都没有 → 网格全空、
/// 12 门课全进「未排时间」，用户读成「课表被改坏了」。两处要钉住：
/// 1. 作息空表时**不再给一张空网格**，改成把因果说清楚 + 一个「去填作息」出口；
/// 2. 收纳区展开后限高滚动——它是 Column 里的非弹性子节点，拿的是无上限高度
///    约束，12 条 ListTile 直接撑爆整列（实测 BOTTOM OVERFLOWED BY 256 PIXELS）。
///
/// ★ 碰数据库的动作一律包 `tester.runAsync`；面板首帧后自己 `load()`，
/// 所以这里**不预调 load**，按真机顺序 pump（`course_week_navigation_test.dart`
/// 同一套陷阱说明）。411dp 与 1280dp 各 pump 一次（总纲铁律 8）。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

  // 设备现场同款：开学第一周周一 2026-08-31、共 20 周、今天 2026-10-18（周日）
  // → 今天是第 7 周。
  final DateTime today = DateTime(2026, 10, 18, 9, 50);
  final DateTime firstMonday = DateTime.utc(2026, 8, 31);
  const List<int> allWeeks = <int>[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
  ];

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kLatestSchemaVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await runMigrations(db, fromVersion: 0, toVersion: version);
        },
      ),
    );
    services = AppServices(db: db);
    semesters = SemesterUseCase(services);
    courses = CourseUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters, courseUseCase: courses, clock: () => today);
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 建学期 + [scheduled] 门「作息里有节次」的课 + [unscheduled] 门「节次超出
  /// 作息」的课。作息写几节由 [sections] 决定，0 = 把该学期那张作息表整表清空。
  Future<void> seed(WidgetTester tester,
      {required int sections,
      int scheduled = 0,
      int unscheduled = 0}) {
    return io(tester, () async {
      final String semesterId = (await semesters.createSemester(
              name: '2026-2027-1',
              firstWeekDate: firstMonday,
              totalWeeks: 20))
          .id;
      // 节次写进**这个学期自己的**作息表（读路径 2026-10-19 起按学期）。
      // [sections] = 0 时整表替换成空表：建学期时它先拿着模板的 12 节，
      // 不写这一趟就清不掉，「作息空表」那个形态永远测不到。
      final String? error = await semesters
          .saveDetailsForSemester(semesterId, <TimeDetail>[
        for (int s = 1; s <= sections; s++)
          TimeDetail(
              id: '',
              timetableId: '',
              section: s,
              startMinutes: 480 + (s - 1) * 55,
              endMinutes: 480 + (s - 1) * 55 + 45),
      ]);
      expect(error, isNull);
      for (int i = 0; i < scheduled; i++) {
        await courses.create(
            name: '已排课$i',
            weekday: i % 5 + 1,
            startSection: 1,
            endSection: sections < 2 ? 1 : 2,
            weeks: allWeeks,
            location: 'A${100 + i}',
            semesterId: semesterId);
      }
      for (int i = 0; i < unscheduled; i++) {
        await courses.create(
            name: '未排课$i',
            weekday: i % 5 + 1,
            startSection: sections + 1,
            endSection: sections + 2,
            weeks: allWeeks,
            location: 'B${200 + i}',
            semesterId: semesterId);
      }
    });
  }

  Future<void> pumpPane(WidgetTester tester,
      {required double width, required double height}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<CourseUseCase>.value(value: courses),
        ChangeNotifierProvider<CoursePaneModel>.value(value: model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CoursePane()),
      ),
    ));
    await tester.pump();
    // 面板首帧后的 load() 要真延时才跑得完（runAsync 里冻结的是假时钟）。
    await io(tester,
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
  }

  String weekLabel(WidgetTester tester) => tester
          .widget<Text>(find.byKey(const ValueKey<String>('week-label')))
          .data ??
      '';

  testWidgets('411dp：作息空表 → 说清因果 + 给出口，不给空网格', (tester) async {
    await seed(tester, sections: 0, unscheduled: 12);
    await pumpPane(tester, width: 411, height: 860);

    // 周次仍按学期算对（第 7 周），空的是网格不是学期。
    expect(weekLabel(tester), '第 7 周 / 共 20 周');
    expect(model.details, isEmpty);
    expect(find.byKey(const ValueKey<String>('no-timetable-title')),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('no-timetable-hint')))
            .data,
        contains('12 门课'),
        reason: '必须告诉用户课没丢，否则读起来像数据被删了');
    expect(find.byKey(const ValueKey<String>('week-pager')), findsNothing,
        reason: '作息空表时不再画一张什么都看不出来的空网格');

    await tester.tap(find.byKey(const ValueKey<String>('no-timetable-fill')));
    await tester.pumpAndSettle();
    expect(find.text('学期与作息'), findsOneWidget,
        reason: '出口要真的能进到填作息那张卡');
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280dp：作息空表同样给出口（桌面走对话框形态）', (tester) async {
    await seed(tester, sections: 0, unscheduled: 12);
    await pumpPane(tester, width: 1280, height: 860);

    expect(find.byKey(const ValueKey<String>('no-timetable-title')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('no-timetable-fill')));
    await tester.pumpAndSettle();
    expect(find.text('学期与作息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('411×640：12 条未排课展开后限高滚动，不撑爆整列', (tester) async {
    // 作息只有 1-2 节，另排 12 门 3-4 节的课 → 收纳区 12 条，正是真机那一张。
    await seed(tester, sections: 2, scheduled: 2, unscheduled: 12);
    await pumpPane(tester, width: 411, height: 640);

    expect(find.byKey(const ValueKey<String>('week-pager')), findsOneWidget,
        reason: '有作息就要正常画网格');
    expect(find.text('已排课0'), findsOneWidget);

    final Finder title = find.byKey(const ValueKey<String>('unscheduled-title'));
    expect(tester.widget<Text>(title).data, '未排时间（12）');
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '溢出会被框架记成异常');

    final Size list = tester.getSize(find
        .byKey(const ValueKey<String>('unscheduled-list'))
        .last);
    expect(list.height, lessThanOrEqualTo(640 * 0.35 + 0.5),
        reason: '展开内容必须限高，否则非弹性子节点把整列撑爆');
    expect(find.text('周一 · 第 3-4 节 · B200'), findsWidgets,
        reason: '一屏十几条时必须带星期，否则同名课分不清');
  });
}
