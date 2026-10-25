import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/update/update_cache.dart';

/// ETag 缓存：重复检查时能带 If-None-Match，304 不计入 GitHub 匿名额度。
void main() {
  test('写入后能读回同一份 ETag 与响应体', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final UpdateHttpCache cache =
        UpdateHttpCache(prefs: prefs, repoSlug: 'wazyf-cell/qingdan');
    expect(await cache.read(), isNull);

    await cache.write('W/"abc"', '{"tag_name":"v1.0.10"}');
    final ({String etag, String body})? got = await cache.read();
    expect(got?.etag, 'W/"abc"');
    expect(got?.body, contains('v1.0.10'));
  });

  test('不同仓库互不串缓存', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final UpdateHttpCache a =
        UpdateHttpCache(prefs: prefs, repoSlug: 'a/b');
    final UpdateHttpCache b =
        UpdateHttpCache(prefs: prefs, repoSlug: 'c/d');
    await a.write('etag-a', '{"tag_name":"v1"}');
    expect(await a.read(), isNotNull);
    expect(await b.read(), isNull);
  });

  test('空 ETag 视为没有缓存，不会带着空头发条件请求', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final UpdateHttpCache cache =
        UpdateHttpCache(prefs: prefs, repoSlug: 'x/y');
    await cache.write('', '{"tag_name":"v1"}');
    expect(await cache.read(), isNull);
  });
}
