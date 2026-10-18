// 学习通提醒快照单测（M6-C4）。
//
// 快照只落 SharedPreferences，**不进 SQLite、不参与同步**；它是「应用被杀后提醒
// 还要能响」的唯一凭据，所以读回来的容错比写出去更重要：JSON 坏了返回空表而不是抛。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/notify/chaoxing_snapshot.dart';

ChaoxingSnapshotItem _item(String key,
        {DateTime? due,
        bool hidden = false,
        bool serverDone = false,
        bool ongoing = true}) =>
    ChaoxingSnapshotItem(
        key: key,
        courseName: '数据结构',
        title: '作业$key',
        dueAt: due,
        hidden: hidden,
        serverDone: serverDone,
        ongoing: ongoing);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late ChaoxingSnapshotStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    store = ChaoxingSnapshotStore(prefs: prefs);
  });

  test('写入 → 读回一致：字段、三个 flag 与空 dueAt 都不变形', () async {
    final List<ChaoxingSnapshotItem> items = <ChaoxingSnapshotItem>[
      _item('a', due: DateTime(2026, 10, 18, 23, 40)),
      _item('b', due: DateTime(2026, 10, 20, 8, 0), hidden: true),
      _item('d',
          due: DateTime(2026, 10, 21, 8, 0), serverDone: true, ongoing: false),
      _item('c'), // 无截止时间：写进去也该原样读回
    ];
    await store.writeSnapshot(items);
    final List<ChaoxingSnapshotItem> got = await store.readSnapshot();
    expect(got.map((ChaoxingSnapshotItem e) => e.key), ['a', 'b', 'd', 'c'],
        reason: '按 dueAt 升序，无 dueAt 的排最后');
    expect(got[0].courseName, '数据结构');
    expect(got[0].title, '作业a');
    expect(got[1].hidden, isTrue);
    expect(got[0].serverDone, isFalse);
    expect(got[0].ongoing, isTrue);
    expect(got[2].serverDone, isTrue, reason: '快照里已交的作业不能被重新提醒');
    expect(got[2].ongoing, isFalse, reason: '服务端已结束的项同理（丢了它就会被重新排上）');
    expect(got[3].dueAt, isNull);
  });

  test('dueAt 读回来是本地时刻（免打扰顺延看墙上钟点，UTC 会整体偏 8 小时）',
      () async {
    await store.writeSnapshot([_item('a', due: DateTime(2026, 10, 18, 23, 40))]);
    final ChaoxingSnapshotItem got = (await store.readSnapshot()).single;
    expect(got.dueAt, DateTime(2026, 10, 18, 23, 40));
    expect(got.dueAt!.isUtc, isFalse);
  });

  test('落盘的 key 名逐字照抄总纲 §五，值是 JSON 数组', () async {
    await store.writeSnapshot([_item('a', due: DateTime(2026, 10, 18))]);
    expect(prefs.getString('chaoxing.notify.snapshot'), isNotNull);
    expect(prefs.getString(kChaoxingSnapshotKey), startsWith('['));
  });

  test('空列表：写进去读回来还是空，不抛', () async {
    await store.writeSnapshot(const <ChaoxingSnapshotItem>[]);
    expect(await store.readSnapshot(), isEmpty);
  });

  test('没写过：读回来是空表', () async {
    expect(await store.readSnapshot(), isEmpty);
  });

  test('JSON 损坏 → 空表 + 不抛', () async {
    await prefs.setString(kChaoxingSnapshotKey, '{"不是数组"');
    expect(await store.readSnapshot(), isEmpty);
    await prefs.setString(kChaoxingSnapshotKey, ']["');
    expect(await store.readSnapshot(), isEmpty);
  });

  test('顶层是对象而不是数组：也返回空表，不抛', () async {
    await prefs.setString(kChaoxingSnapshotKey, '{"key":"a","due":1760000000000}');
    expect(await store.readSnapshot(), isEmpty,
        reason: '形态不对就当没有，别把半截数据当真（这条与下面一条都由外层兜住）');
  });

  test('顶层是数组但元素不是对象：整体按空处理，不抛', () async {
    await prefs.setString(kChaoxingSnapshotKey, '["裸字符串", 42]');
    expect(await store.readSnapshot(), isEmpty);
  });

  test('单条字段坏了只丢那一条，其余保留', () async {
    await prefs.setString(kChaoxingSnapshotKey, '[{"title":"没有 key"},'
        '{"key":"ok","course":"C","title":"T","due":1760000000000}]');
    final List<ChaoxingSnapshotItem> got = await store.readSnapshot();
    expect(got.map((ChaoxingSnapshotItem e) => e.key), ['ok']);
  });

  test('clearSnapshot：退出登录 / 关掉总开关后读回来是空', () async {
    await store.writeSnapshot([_item('a', due: DateTime(2026, 10, 18))]);
    expect(await store.readSnapshot(), isNotEmpty);
    await store.clearSnapshot();
    expect(await store.readSnapshot(), isEmpty);
    expect(prefs.getString(kChaoxingSnapshotKey), isNull);
  });

  test('上限 300：写 350 条只留 dueAt 最早的 300 条', () async {
    final List<ChaoxingSnapshotItem> many = <ChaoxingSnapshotItem>[
      for (int i = 0; i < 350; i++)
        _item('k${i.toString().padLeft(3, '0')}',
            due: DateTime(2026, 10, 18).add(Duration(minutes: i)))
    ];
    await store.writeSnapshot(many);
    final List<ChaoxingSnapshotItem> got = await store.readSnapshot();
    expect(got.length, kChaoxingSnapshotMax);
    expect(got.first.key, 'k000');
    expect(got.last.key, 'k299', reason: '丢的是最晚那 50 条');
    for (int i = 1; i < got.length; i++) {
      expect(got[i].dueAt!.isAfter(got[i - 1].dueAt!), isTrue,
          reason: '第 $i 条没有晚于前一条：升序被破坏');
    }
  });

  test('无 dueAt 的项排在最后，截断时先丢它们', () async {
    final List<ChaoxingSnapshotItem> many = <ChaoxingSnapshotItem>[
      for (int i = 0; i < 290; i++)
        _item('k${i.toString().padLeft(3, '0')}',
            due: DateTime(2026, 10, 18).add(Duration(minutes: i))),
      for (int i = 0; i < 30; i++) _item('x$i'),
    ];
    await store.writeSnapshot(many);
    final List<ChaoxingSnapshotItem> got = await store.readSnapshot();
    expect(got.length, kChaoxingSnapshotMax);
    expect(got.where((ChaoxingSnapshotItem e) => e.dueAt == null).length, 10,
        reason: '只挤进 10 条空 dueAt 的（300 - 290）');
  });

  test('同刻的项按 key 定序：截断结果可复现', () async {
    final DateTime same = DateTime(2026, 10, 18, 12, 0);
    await store.writeSnapshot(
        [_item('zz', due: same), _item('aa', due: same), _item('mm', due: same)]);
    expect((await store.readSnapshot()).map((ChaoxingSnapshotItem e) => e.key),
        ['aa', 'mm', 'zz']);
  });
}
