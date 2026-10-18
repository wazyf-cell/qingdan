import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/first_run_guide.dart';
import 'package:qingdan/features/settings/help_section.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 首启引导框（M6-C6 + 用户裁决 Q26）。
///
/// 三件必须成立的事：① `ui.guideSeen == false` 才弹；② **两个按钮都写 true**
/// （「以后再说」也不再弹，靠 prefs 而不是内存标记）；③「去看使用说明」真能进
/// `help-page`。另外遮罩点不掉——否则会有第三条路径既不弹也不记，下次又弹。
void main() {
  late SharedPreferences prefs;
  late SettingsModel settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    settings = SettingsModel(prefs: prefs);
    await settings.load();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: SizedBox.expand()),
    ));
    await tester.pumpAndSettle();
  }

  /// 模拟 main.dart 首帧后的调用：不等它返回（返回时机由按钮决定）。
  Future<void> showGuide(WidgetTester tester) async {
    maybeShowFirstRunGuide(tester.element(find.byType(Scaffold)), settings);
    await tester.pumpAndSettle();
  }

  testWidgets('guideSeen 为 false → 弹欢迎框，两个按钮都在',
      (WidgetTester tester) async {
    expect(settings.guideSeen, isFalse);
    await pumpHome(tester);
    await showGuide(tester);

    expect(find.byKey(const ValueKey<String>('first-run-guide')), findsOneWidget);
    expect(find.text('欢迎使用清单'), findsOneWidget);
    expect(find.text('以后再说'), findsOneWidget);
    expect(find.text('去看使用说明'), findsOneWidget);
    // 一次只说一件事：引导框里不许掺同步/权限类告警。
    expect(find.textContaining('同步未配置'), findsNothing);
  });

  testWidgets('点「以后再说」→ prefs 变 true，重开不再弹',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await showGuide(tester);

    await tester.tap(find.byKey(const ValueKey<String>('guide-later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('first-run-guide')), findsNothing);
    expect(settings.guideSeen, isTrue);
    expect(prefs.getBool(SettingsModel.kGuideSeenKey), isTrue,
        reason: '只改内存不落盘，下次启动还会弹');

    // 「重开应用」= 新建模型再 load()，读到的必须是 true。
    // 这里刻意不 await 那次调用：实现如果无视 guideSeen，await 会永远挂着
    // （反证 B1a 就是这么卡住的），改成发射后 pump 一下再断言。
    final SettingsModel reopened = SettingsModel(prefs: prefs);
    await reopened.load();
    expect(reopened.guideSeen, isTrue);
    maybeShowFirstRunGuide(tester.element(find.byType(Scaffold)), reopened);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('first-run-guide')), findsNothing);
  });

  testWidgets('点「去看使用说明」→ 进 help-page，同样算看过',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await showGuide(tester);

    await tester.tap(find.byKey(const ValueKey<String>('guide-open-help')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('first-run-guide')), findsNothing);
    expect(find.byType(HelpPage), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('help-page')), findsOneWidget);
    expect(find.text('四个页签'), findsOneWidget);
    expect(prefs.getBool(SettingsModel.kGuideSeenKey), isTrue);
  });

  testWidgets('已经看过（prefs 里 true）→ 根本不弹',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{SettingsModel.kGuideSeenKey: true});
    final SharedPreferences seeded = await SharedPreferences.getInstance();
    final SettingsModel returning = SettingsModel(prefs: seeded);
    await returning.load();

    await pumpHome(tester);
    maybeShowFirstRunGuide(tester.element(find.byType(Scaffold)), returning);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('first-run-guide')), findsNothing);
  });

  testWidgets('遮罩点不掉：不存在「既不弹也不记」的第三条路径',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await showGuide(tester);

    await tester.tapAt(const Offset(6, 6)); // 对话框外的遮罩
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('first-run-guide')), findsOneWidget);
    expect(settings.guideSeen, isFalse);
  });

  test('guideSeen 落盘往返：写 true 后新模型 load 读到 true', () async {
    await settings.setGuideSeen(true);
    expect(prefs.getBool(SettingsModel.kGuideSeenKey), isTrue);
    final SettingsModel reloaded = SettingsModel(prefs: prefs);
    await reloaded.load();
    expect(reloaded.guideSeen, isTrue);
  });
}
