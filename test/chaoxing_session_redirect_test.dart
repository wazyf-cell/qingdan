/// 会话失效判据：被 302 到登录页必须抛「未登录」，而不是当成「这一页没有待办」。
///
/// 这条规则原来只看响应体首字符是不是 `<`，而超星的登录页本身就是合法 HTML，
/// 于是 cookie 过期时列表静默变空。判据与详情页 WebView 的 `_onLoadStop` 同源。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/chaoxing/chaoxing_client.dart';

void main() {
  test('跳到 passport / /login 的落点算会话失效', () {
    expect(
        ChaoxingClient.bouncedToLogin(
            <Uri>[Uri.parse('https://passport2.chaoxing.com/login?refer=')]),
        isTrue);
    expect(
        ChaoxingClient.bouncedToLogin(
            <Uri>[Uri.parse('https://mooc1.chaoxing.com/fe/login/index')]),
        isTrue);
  });

  test('课程页自己的中间跳转不算失效', () {
    expect(
        ChaoxingClient.bouncedToLogin(<Uri>[
          Uri.parse('https://mooc1.chaoxing.com/visit/stucoursemiddle?courseid=1'),
          Uri.parse('https://mooc1-api.chaoxing.com/work/stuWorkList'),
        ]),
        isFalse);
    expect(ChaoxingClient.bouncedToLogin(const <Uri>[]), isFalse);
  });
}
