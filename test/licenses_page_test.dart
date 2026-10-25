import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/licenses_page.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 开源许可自定义页：双端不溢出，本应用/上游/完整依赖入口都在。
void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const LicensesPage(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '${width}dp 渲染异常');
  }

  for (final double width in <double>[411, 1280]) {
    testWidgets('${width.toInt()}dp：许可页分区、声明与入口齐全',
        (WidgetTester tester) async {
      await pump(tester, width);
      expect(find.byKey(const ValueKey<String>('licenses-page')),
          findsOneWidget);
      expect(find.text('GNU AGPL-3.0-or-later'), findsOneWidget);
      expect(find.text('上游与移植'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('licenses-full')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('licenses-open-repo')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('licenses-open-issues')),
          findsOneWidget);
      expect(find.textContaining('蓝航APP'), findsWidgets);
      expect(find.textContaining('只适配南昌航空大学强智'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
