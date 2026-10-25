import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/semester_detail_page.dart';
import 'package:qingdan/features/course/timetable_editor_page.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// 学期与作息整页（v1.0.10）：字段、作息只读表、改作息页、模板生成与返回拦截。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb db;
  late SemesterUseCase semesters;
  late TimetableUseCase templates;
  late CoursePaneModel model;

  setUp(() async {
    db = await DaoTestDb.open();
    final AppServices services = AppServices(db: db.db);
    semesters = SemesterUseCase(services);
    templates = TimetableUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters,
        courseUseCase: CourseUseCase(services));
    await semesters.createSemester(
        name: '2026-2027-1', firstWeekDate: DateTime.utc(2026, 8, 31));
    await model.load();
    final Semester active = (await semesters.activeSemester())!;
    final String? err = await semesters.saveDetailsForSemester(active.id, <TimeDetail>[
      TimeDetail(
          id: '', timetableId: '', section: 1, startMinutes: 480, endMinutes: 525),
      TimeDetail(
          id: '', timetableId: '', section: 2, startMinutes: 535, endMinutes: 580),
    ]);
    expect(err, isNull);
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await io(tester, () async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (int i = 0; i < 8; i++) {
        await semesters.allSemesters();
      }
    });
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapIo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    });
    await settle(tester);
  }

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<TimetableUseCase>.value(value: templates),
        Provider<CourseUseCase>.value(value: CourseUseCase(AppServices(db: db.db))),
        ChangeNotifierProvider<CoursePaneModel>.value(value: model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => TextButton(
              key: const ValueKey<String>('open-detail'),
              onPressed: () async {
                final Semester s = (await semesters.activeSemester())!;
                await openSemesterDetailPage(ctx, semester: s);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('open-detail')));
    await settle(tester);
    expect(find.byType(SemesterDetailPage), findsOneWidget);
  }

  testWidgets('渲染学期字段、作息只读表与两个出口', (tester) async {
    await openPage(tester);
    expect(find.byKey(const ValueKey<String>('semester-save')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('semester-edit-timetable')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('semester-apply-template')),
        findsOneWidget);
  });

  testWidgets('改字段点保存：三个字段一次写进库', (tester) async {
    await openPage(tester);
    await tester.enterText(
        find.byKey(const ValueKey<String>('semester-name')), '改过的学期');
    await tester.pump();
    await tapIo(tester,
        find.byKey(const ValueKey<String>('semester-save')));
    final Semester? saved = await io(tester, () => semesters.activeSemester());
    expect(saved?.name, '改过的学期');
    expect(find.byKey(const ValueKey<String>('semester-detail-said')),
        findsOneWidget);
  });

  testWidgets('编辑作息：进整页，保存后回到详情', (tester) async {
    await openPage(tester);
    await tapIo(tester,
        find.byKey(const ValueKey<String>('semester-edit-timetable')));
    expect(find.byType(TimetableEditorPage), findsOneWidget);
    await tapIo(tester, find.byKey(const ValueKey<String>('tt-page-save')));
    await settle(tester);
    expect(find.byType(TimetableEditorPage), findsNothing);
    expect(find.byType(SemesterDetailPage), findsOneWidget);
  });

  testWidgets('从模板生成：选内置模板后节次变成模板的 12 节', (tester) async {
    await openPage(tester);
    final List<TimeTable> all = (await io(tester, templates.templates))!;
    final TimeTable builtin = all.firstWhere((TimeTable t) => t.isBuiltin);
    await tapIo(tester,
        find.byKey(const ValueKey<String>('semester-apply-template')));
    await tapIo(tester,
        find.byKey(ValueKey<String>('semester-template-${builtin.id}')));
    final List<TimeDetail> details = (await io(tester, () async {
      final Semester s = (await semesters.activeSemester())!;
      return semesters.loadDetailsForSemester(s.id);
    }))!;
    expect(details, hasLength(12));
  });

  testWidgets('改过字段返回要确认；取消留在页面，确认才退出', (tester) async {
    await openPage(tester);
    await tester.enterText(
        find.byKey(const ValueKey<String>('semester-name')), '未保存');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey<String>('semester-discard-confirm')),
        findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey<String>('semester-discard-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(SemesterDetailPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey<String>('semester-discard-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(SemesterDetailPage), findsNothing);
  });
}
