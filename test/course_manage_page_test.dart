import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/features/course/course_manage_page.dart';
import 'package:qingdan/features/course/import_wizard/import_wizard.dart';
import 'package:qingdan/features/course/semester_sheet.dart';

import 'dao_test_helper.dart';
import 'course_manage_page_harness.dart';

/// 课表管理整页（M6-D §7.4）= 学期面板的整页版本 + 两条导入入口的第二入口。
///
/// 三条入口形态各不相同，要分开钉死：本页永远 push 整页；「导入课表文件」411 push
/// 路由 / 1280 居中 Dialog；「时间表管理」两端都是弹层。碰库动作一律在
/// `tester.runAsync` 里跑完；411 与 1280 各 pump 一遍（总纲铁律 8）。
/// 夹具与点法在 `course_manage_page_harness.dart`。
void main() {
  ensureSqfliteFfi();
  late ManageHarness h;

  setUp(() async => h = await ManageHarness.create());
  tearDown(() async => h.close());

  for (final (String label, double width) in
      <(String, double)>[('移动 411dp', 411), ('桌面 1280dp', 1280)]) {
    group(label, () {
      testWidgets('P1 能进能退：三条入口行 + 两个学期行都在本页，勾只在当前学期',
          (WidgetTester tester) async {
        final double height = h.heightOf(width);
        await h.seed(tester);
        await h.openManage(tester, width);
        await h.tapIo(tester, 'open-shell');

        expect(find.byType(CourseManagePage), findsOneWidget);
        // 量尺寸而不是量原点：进场的页面转场即使 pump 到位也会留下 **亚像素**原点
        // （411dp 实测 left=0.1、1280dp left=0.5）。写 `Rect.fromLTRB(0,0,w,h)`
        // 等于把一个看不见的路由动画余量钉成红线，白天绿、换个断言顺序就红。
        final Rect page = tester.getRect(find.byType(CourseManagePage));
        expect(page.width, closeTo(width, 0.5), reason: '$label：整页宽度没铺满');
        expect(page.height, closeTo(height, 0.5), reason: '$label：整页高度没铺满');
        expect(page.left.abs(), lessThan(1.0),
            reason: '$label：整页必须贴着视口左边，不是浮在中间的一块');

        final String idA = await h.idOf(tester, 'A 学期');
        final String idB = await h.idOf(tester, 'B 学期');
        expect(h.key('semester-row-$idA'), findsOneWidget);
        expect(h.key('semester-row-$idB'), findsOneWidget);
        expect(h.key('semester-check-$idA'), findsOneWidget);
        expect(h.key('semester-check-$idB'), findsNothing,
            reason: '$label：勾只有一个，而且挂在当前学期那行');
        expect(h.key('semester-create'), findsOneWidget);

        final Rect row1 = tester.getRect(h.key('manage-import'));
        final Rect row2 = tester.getRect(h.key('manage-capture'));
        final Rect row3 = tester.getRect(h.key('manage-templates'));
        final Rect sem = tester.getRect(h.key('semester-row-$idA'));
        expect(row1.width, greaterThan(width * 0.8), reason: '$label：入口行没铺满');
        expect(row2.width, closeTo(row1.width, 0.5));
        expect(row2.top, greaterThan(row1.bottom - 1));
        expect(row3.top, greaterThan(row2.bottom - 1));
        expect(sem.top, greaterThan(row3.bottom - 1),
            reason: '$label：学期列表排在三条入口之后（§7.4）');
        expect(row3.right, lessThanOrEqualTo(width));
        expect(tester.widget<ListTile>(h.key('manage-capture')).onTap, isNotNull,
            reason: '$label：教务抓取这条入口不许是死行');
        expect(tester.takeException(), isNull, reason: '$label 出现布局异常');

        await tester.tap(find.byType(BackButton));
        // 退场的路由要**动画走完之后再有一帧**才真的从 Overlay 上摘掉：只
        // `pump()` + 一次 `pump(400ms)` 会停在同一帧里，Page 还挂在树上，看着
        // 像「退不回去」。分多帧推进，别用 pumpAndSettle（本页首帧有读库回调，
        // 它会一直等到超时）。
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(CourseManagePage), findsNothing);
        expect(h.key('open-shell'), findsOneWidget, reason: '$label：退不回去');
      });

      testWidgets('P2 「导入课表文件」= 同一个五步向导开在本页之上（形态按断点分）',
          (WidgetTester tester) async {
        final double height = h.heightOf(width);
        await h.seed(tester);
        await h.openManage(tester, width);
        await h.tapIo(tester, 'open-shell');
        await h.tapIo(tester, 'manage-import');

        expect(find.byType(ImportWizardPage), findsOneWidget);
        expect(h.key('pick-file'), findsOneWidget, reason: '$label：向导步 1 没出现');
        expect(h.key('wizard-next'), findsOneWidget);
        if (width < 720) {
          expect(find.byType(Dialog), findsNothing, reason: '窄屏该 push 路由');
          final Rect w1 = tester.getRect(find.byType(ImportWizardPage));
          expect(w1.width, closeTo(width, 0.5));
          expect(w1.height, closeTo(height, 0.5));
          expect(w1.left.abs(), lessThan(1.0));
          expect(find.text('导入课表'), findsOneWidget);
        } else {
          expect(find.byType(Dialog), findsOneWidget, reason: '宽屏该居中弹窗');
          // `Dialog` 自己的 layout box 就是整屏（它是定位层，卡片是里面的 child），
          // 拿它的宽度当「弹窗宽度」必然得到 1280——量那颗定宽 860 的卡片。
          final Rect card = tester.getRect(find
              .descendant(
                  of: find.byType(ImportWizardPage),
                  matching: find.byType(SizedBox))
              .first);
          expect(card.width, closeTo(860, 1), reason: '$label：向导卡片定宽 860');
          expect(card.height, closeTo(600, 1));
          expect(card.center.dx, closeTo(width / 2, 1));
        }
        expect(tester.takeException(), isNull);

        // 关掉向导要回到本页，而不是把整页一起带走。
        await h.popTop(tester);
        expect(find.byType(ImportWizardPage), findsNothing);
        expect(find.byType(CourseManagePage), findsOneWidget);
        expect(h.key('manage-import'), findsOneWidget);
      });

      testWidgets('P3 「时间表管理」= 打开同一份模板库（两端都是弹层）',
          (WidgetTester tester) async {
        await h.seed(tester);
        await h.openManage(tester, width);
        await h.tapIo(tester, 'open-shell');
        await h.tapIo(tester, 'manage-templates');

        expect(h.key('timetable-library'), findsOneWidget,
            reason: '$label：模板库没开出来');
        expect(find.text('大学默认'), findsOneWidget,
            reason: '$label：内置模板要在列（§7.3）');
        expect(h.key('tpl-create'), findsOneWidget);
        expect(tester.getRect(h.key('timetable-library')).width,
            lessThanOrEqualTo(width));
        if (width < 720) {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
        }
        expect(tester.takeException(), isNull, reason: '$label 出现布局异常');

        await h.popTop(tester);
        expect(h.key('timetable-library'), findsNothing);
        expect(find.byType(CourseManagePage), findsOneWidget,
            reason: '$label：关掉模板库要还在本页');
      });

      testWidgets('P4 整页形态点一行学期：切换成功且回执 semester-said 留在本页',
          (WidgetTester tester) async {
        await h.seed(tester);
        await h.openManage(tester, width);
        await h.tapIo(tester, 'open-shell');
        final String idB = await h.idOf(tester, 'B 学期');
        expect(h.key('semester-said'), findsNothing, reason: '没操作过不该有回执');

        await tester.tap(h.key('semester-row-$idB'));
        await tester.pump();
        await h.settle(tester);
        await tester.pumpAndSettle();

        expect(h.model.semester?.id, idB, reason: '$label：写链没跑完');
        expect(find.byType(CourseManagePage), findsOneWidget,
            reason: '$label：整页不该关，回执要显示在本页');
        expect(h.key('semester-said'), findsOneWidget);
        expect(tester.widget<Text>(h.key('semester-said')).data,
            contains('已切换到「B 学期」'));
        expect(h.key('semester-check-$idB'), findsOneWidget, reason: '勾跟着换过去');
        final List<Map<String, Object?>> actives = (await h.io(tester,
            () => h.env.db.query('semesters', where: 'is_active = 1')))!;
        expect(actives.map((Map<String, Object?> r) => r['id']), <Object?>[idB],
            reason: '库里必须真的换了过去，不是只改了内存对象');
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('导入/create 新学期的 model.load() 一到，管理页列表立刻出现新行（v1.0.8 用户报）',
      (WidgetTester tester) async {
    await h.seed(tester);
    await h.openManage(tester, 411);
    await h.tapIo(tester, 'open-shell');

    final String idA = await h.idOf(tester, 'A 学期');
    expect(h.key('semester-row-$idA'), findsOneWidget);
    expect(find.text('C 学期'), findsNothing);

    // 复现向导步 3 建学期 + 完成时 `pane.load()` 的真实调用顺序：
    // 页面不会重建（State 还在），列表必须自己跟着 model 的通知重读。
    final String idC = (await h.io(tester, () async {
      final Semester created = await h.semesters.createSemester(
          name: 'C 学期',
          firstWeekDate: DateTime.utc(2025, 9, 1),
          setActive: false);
      await h.model.load();
      return created.id;
    }))!;
    await h.settle(tester);
    await tester.pump();

    expect(h.key('semester-row-$idC'), findsOneWidget,
        reason: '新导入的学期不能等重启才出现在「课表管理」里');
    expect(find.text('C 学期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('对照 §7.1：弹层形态把回执交给外层 pop，列表自己不留 semester-said',
      (WidgetTester tester) async {
    String? said;
    await h.seed(tester);
    await h.pumpShell(tester, 1280, open: (BuildContext ctx) async {
      said = await showSemesterSheet(ctx,
          model: h.model,
          semesters: h.semesters,
          templates: h.templates,
          isMobile: false);
    });
    await h.tapIo(tester, 'open-shell');
    final String idB = await h.idOf(tester, 'B 学期');
    expect(h.key('semester-row-$idB'), findsOneWidget);

    await tester.tap(h.key('semester-row-$idB'));
    await tester.pump();
    await h.settle(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SemesterListView), findsNothing, reason: '弹层切完就关');
    expect(h.key('semester-said'), findsNothing, reason: '回执归外层，不留在列表里');
    expect(said, '已切换到「B 学期」',
        reason: '§7.1：面板把这句话作为 pop 值交回调用方（课表页行内回执）');
    expect(tester.takeException(), isNull);
  });
}
