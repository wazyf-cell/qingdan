import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_detail_page.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'chaoxing_harness.dart';

/// 详情页降级文案（`chaoxing_detail_page.dart` 的 `_unsupported`）。
///
/// 钉的是「两种 null 不能混成一句话」。`detailUrlOf`（`chaoxing_links.dart`
/// :33-34）在两种情况下都返回 null：① 课堂活动 / 考试这类**上游本来就没有
/// 单条题目页**的条目；② **真作业**（`serverStatus != null`）但抓到的那一行没带
/// `clazzId`——那种条目其实有题目页，只是我们拼不出地址。原先两句并一句，写成
/// 「这类条目在超星里没有单独的题目页」，等于把②也说成①，用户就不会再回超星里
/// 点开这条作业。
///
/// 详情页不按宽度分支（全屏页），但学习通两端都发，故 411 / 1280 各 pump 一遍。
/// 测试环境没有 `flutter_inappwebview` 的平台实现，`webView` 注入点换占位 Widget；
/// 这两条用例走的是 null-URL 分支，压根不会构造 WebView。
void main() {
  Future<void> pumpDetail(WidgetTester tester, ChaoxingTask task,
      {required double width}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ChaoxingDetailPage(
        task: task,
        webView: (BuildContext _, String _, ValueChanged<Uri?> _) =>
            const SizedBox.shrink(),
      ),
    ));
    await tester.pump();
  }

  Finder key(String k) => find.byKey(ValueKey<String>(k));
  String textAt(WidgetTester tester, String k) =>
      tester.widget<Text>(key(k)).data ?? '';

  for (final (String label, double width) in
      <(String, double)>[('手机 411dp', 411), ('桌面 1280dp', 1280)]) {
    testWidgets('$label：真作业缺 clazzId → 说清「它有题目页，是我们参数没抓到」',
        (WidgetTester tester) async {
      await pumpDetail(tester, cxHomework('h9', clazzId: null), width: width);

      expect(key('detail-headline'), findsOneWidget);
      expect(textAt(tester, 'detail-headline'), '这条作业打不开');
      final String said = textAt(tester, 'detail-reason');
      expect(said, contains('clazzId'), reason: '$label：要点名缺的那个参数');
      expect(said, contains('是有题目页的'),
          reason: '$label：真作业有题目页，不能混进「这类活动天生没页」');
      expect(said, isNot(contains('没有单独的题目页')),
          reason: '$label：这句正是审计抓到的那句谎话');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label：课堂活动 → 如实说这类活动上游就没有单条题目页（带类型名）',
        (WidgetTester tester) async {
      await pumpDetail(tester, cxActivity('a9', kind: '签到'), width: width);

      expect(textAt(tester, 'detail-headline'), '该类型暂不支持查看详情');
      final String said = textAt(tester, 'detail-reason');
      expect(said, contains('签到'), reason: '$label：要告诉用户是哪一类看不了');
      expect(said, contains('没有单独的题目页'));
      expect(said, isNot(contains('clazzId')),
          reason: '$label：活动类不该提「参数没抓到」');
      expect(tester.takeException(), isNull);
    });
  }
}
