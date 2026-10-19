/// 详情页的默认形态 = 本应用自己的原生一屏（2026-10-19 用户裁决）。
///
/// 钉四件事：① 有入口地址时先抽正文，抽到就**不碰网页**；② 附件只是一个不可点
/// 的名字标签（用户原话：「不要显示，最好也不能点击，放一个和文字不同颜色的文档
/// 名字放在这里就行」）；③ 抽不到 / 会话失效 / 没有入口地址 → 退回真实网页，
/// 并且说清为什么退；④ 手动「在网页中作答」能把这一屏换成网页。
///
/// 两端各 pump 一遍（学习通手机与桌面都发，见 `AGENTS.md` M4a S4b 那条教训）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:qingdan/features/chaoxing/chaoxing_detail_page.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_work_detail.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'chaoxing_harness.dart';

const String _entry =
    'https://mooc1-api.chaoxing.com/mooc-ans/android/mtaskmsgspecial'
    '?taskrefId=1&courseId=2&clazzId=3&type=work&enc_task=deadbeef';

ChaoxingWorkDetail _detail() => const ChaoxingWorkDetail(<ChaoxingQuestion>[
      ChaoxingQuestion(
        index: 1,
        type: '简答题',
        text: '请完成附件里的习题，解答拍照放进 word 文档上传。\n命名：学号-姓名-作业.docx',
        attachments: <String>['第三章习题.docx'],
      ),
    ]);

void main() {
  Future<ChaoxingHarness> open(WidgetTester tester, ChaoxingTask task,
      {double width = 411,
      ChaoxingWorkDetail? detail,
      bool failWorkAuth = false}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start();
    // 必须在 pumpWidget **之前**摆好：详情页第一帧就去取正文，晚一步取到的是 null。
    h.client
      ..workDetail = detail
      ..failWorkAuth = failWorkAuth;
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ChaoxingModel>.value(value: h.model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ChaoxingDetailPage(
          task: task,
          webView: (BuildContext _, String _, ValueChanged<Uri?> _) =>
              const SizedBox.expand(key: ValueKey<String>('fake-web')),
        ),
      ),
    ));
    // 抽取是两次 await（读凭据库 + 取页面），转场动画期间再 pump 一次。
    await tester.pump();
    await tester.pump();
    return h;
  }

  Finder key(String k) => find.byKey(ValueKey<String>(k));
  String textAt(WidgetTester tester, String k) =>
      tester.widget<Text>(key(k)).data ?? '';

  /// 题干是 `SelectableText`（长按可选可抄），不是 `Text`。
  SelectableText bodyAt(WidgetTester tester, String k) =>
      tester.widget<SelectableText>(key(k));

  for (final (String label, double width) in
      <(String, double)>[('手机 411dp', 411), ('宽屏 1280dp', 1280)]) {
    testWidgets('$label：抽到正文就渲染原生一屏，不碰 WebView',
        (WidgetTester tester) async {
      final ChaoxingHarness h = await open(tester,
          cxHomework('h1',
              entryUrl: _entry, dueAt: kCxNow.add(const Duration(days: 1))),
          width: width,
          detail: _detail());
      expect(key('detail-native'), findsOneWidget);
      expect(textAt(tester, 'detail-q1-head'), '1. 简答题');
      expect(bodyAt(tester, 'detail-q1-body').data, contains('请完成附件里的习题'));
      expect(textAt(tester, 'detail-meta'), contains('未提交'));
      expect(key('fake-web'), findsNothing, reason: '抽到了就不该再加载网页');
      expect(h.client.workFetches, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label：附件只是不可点的名字标签，没有点击区', (WidgetTester tester) async {
      await open(tester, cxHomework('h1', entryUrl: _entry),
          width: width, detail: _detail());
      final Finder label = key('detail-attach-第三章习题.docx');
      expect(label, findsOneWidget);
      // 键在**容器**上（标签是一整块，不是光一根文字），所以取文字要往下找一层。
      final Finder labelText =
          find.descendant(of: label, matching: find.byType(Text));
      expect(tester.widget<Text>(labelText).data, '第三章习题.docx');
      expect(find.ancestor(of: label, matching: find.byType(InkWell)), findsNothing);
      expect(
          find.ancestor(of: label, matching: find.byType(GestureDetector)),
          findsNothing,
          reason: '用户明确要求：附件不许点开');
      // 颜色与正文不同：标签用强调色，题干用正文色。
      final Color tag = tester.widget<Text>(labelText).style!.color!;
      final Color body = bodyAt(tester, 'detail-q1-body').style!.color!;
      expect(tag, isNot(body));
    });

    testWidgets('$label：抽不出题（已提交 / 已过时效）→ 退回网页并说明理由',
        (WidgetTester tester) async {
      await open(tester, cxHomework('h1', entryUrl: _entry),
          width: width, detail: null);
      expect(key('fake-web'), findsOneWidget);
      expect(key('detail-native'), findsNothing);
      expect(textAt(tester, 'detail-web-note'), contains('没抽出题目'));
      expect(textAt(tester, 'detail-web-note'), contains('已转真实页面'));
    });

    testWidgets('$label：会话失效 → 顶部提示条 + 网页兜底', (WidgetTester tester) async {
      await open(tester, cxHomework('h1', entryUrl: _entry),
          width: width, failWorkAuth: true);
      expect(key('fake-web'), findsOneWidget);
      expect(find.text('登录态可能已失效'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
    });

    testWidgets('$label：没有入口地址的条目不去抽取，直接进网页',
        (WidgetTester tester) async {
      final ChaoxingHarness h =
          await open(tester, cxHomework('h1', entryUrl: null), width: width);
      expect(h.client.workFetches, 0, reason: '没入口就没得抽，不该白跑一趟凭据库');
      expect(key('fake-web'), findsOneWidget);
    });

    testWidgets('$label：有入口地址但网页地址拼不出来时，抽取照试、失败后说两处都不行',
        (WidgetTester tester) async {
      await open(tester,
          cxHomework('h1', clazzId: null, entryUrl: _entry),
          width: width,
          detail: null);
      expect(find.text('这条作业打不开'), findsNothing,
          reason: '入口地址在手，不该直接判它「打不开」');
      expect(textAt(tester, 'detail-web-note'), contains('没带班级 id'));
      expect(textAt(tester, 'detail-web-note'), contains('没抽出题目'));
    });

    testWidgets('$label：「在网页中作答」把原生一屏换成网页', (WidgetTester tester) async {
      final ChaoxingHarness h = await open(tester,
          cxHomework('h1', entryUrl: _entry),
          width: width,
          detail: _detail());
      expect(key('detail-native'), findsOneWidget);
      await tester.tap(key('detail-open-web'));
      await tester.pump();
      expect(key('detail-native'), findsNothing);
      expect(key('fake-web'), findsOneWidget);
      expect(h.client.workFetches, 1, reason: '切网页不该再抽一遍');
    });
  }
}
