import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/update/update_checker.dart';

/// 更新通道的纯逻辑部分（解析 GitHub 的发布 JSON、比版本、把失败折算成人话）。
///
/// 真实网络那半条（超时 / DNS 挂 / 连不上）在测试环境里碰不到——
/// `TestWidgetsFlutterBinding` 会把 HttpClient 换成会抛的假实现，
/// 所以这里只钉「拿到什么内容 → 说什么话」，联网那步留给设备实测。
void main() {
  group('版本号归一', () {
    test('去掉 v 前缀、+build 与 -预发布后缀', () {
      expect(normalizeVersion('v1.0.2+3'), '1.0.2');
      expect(normalizeVersion('1.0.2'), '1.0.2');
      expect(normalizeVersion('V1.2.3-beta.1'), '1.2.3');
      expect(normalizeVersion('v1.0.2-beta.1+3'), '1.0.2');
    });

    test('段里混进非数字时按 0 算，不整条比较崩掉', () {
      // GitHub 上的 tag 是人手打的，`v1.0.x` 这种写法真会出现。
      expect(compareVersions('1.0.x', '1.0.0'), 0);
      expect(compareVersions('v1.0.2', '1.0.x'), greaterThan(0));
    });

    test('逐段按数字比：1.0.10 必须大于 1.0.2', () {
      // 这是 String.compareTo 会答错的那一条：字典序下 "1.0.10" < "1.0.2"，
      // 后果是「发布了第 10 个小版本，界面却告诉用户已经是最新」。
      expect(compareVersions('1.0.10', '1.0.2'), greaterThan(0));
      expect(compareVersions('1.0.2', '1.0.10'), lessThan(0));
      expect(compareVersions('1.1', '1.0.9'), greaterThan(0));
      expect(compareVersions('2.0', '1.99.99'), greaterThan(0));
    });

    test('相等与段数不等（缺的段按 0 算）', () {
      expect(compareVersions('1.0.2', 'v1.0.2+3'), 0);
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.0.1', '1.0'), greaterThan(0));
    });
  });

  group('发布 JSON 解析', () {
    test('完整载荷：版本、地址、发布时间、附件名都取到', () {
      final ReleaseInfo? r = ReleaseInfo.fromJson(<String, dynamic>{
        'tag_name': 'v1.0.2',
        'html_url': 'https://github.com/wazyf-cell/qingdan/releases/tag/v1.0.2',
        'published_at': '2026-10-19T06:00:00Z',
        'assets': <dynamic>[
          <String, dynamic>{'name': 'app-arm64-v8a-release.apk'},
          <String, dynamic>{'name': ''}, // 空名不算一个文件
          <String, dynamic>{'label': '没有 name 字段'},
        ],
      });
      expect(r, isNotNull);
      expect(r!.version, '1.0.2');
      expect(r.tagName, 'v1.0.2');
      expect(r.url, endsWith('/releases/tag/v1.0.2'));
      expect(r.publishedAt!.toUtc().hour, 6);
      expect(r.assetNames, <String>['app-arm64-v8a-release.apk']);
    });

    test('没有 tag_name 时返回 null，不退化成 v0.0.0', () {
      expect(ReleaseInfo.fromJson(<String, dynamic>{'name': 'untitled'}), isNull);
      expect(ReleaseInfo.fromJson(<String, dynamic>{'tag_name': '   '}), isNull);
    });

    test('缺 html_url 时回落到发布列表，不给一个空地址', () {
      final ReleaseInfo? r =
          ReleaseInfo.fromJson(<String, dynamic>{'tag_name': 'v1.0.2'});
      expect(r!.url, isNotEmpty);
      expect(r.url, startsWith('https://github.com/'));
      expect(r.publishedAt, isNull);
      expect(r.assetNames, isEmpty);
    });
  });

  group('检查结论', () {
    UpdateChecker checkerReturning(Map<String, dynamic> json) =>
        UpdateChecker(fetch: (_) async => json);

    test('GitHub 上更新 → available，副文案同时带两个版本号', () async {
      final UpdateResult r =
          await checkerReturning(<String, dynamic>{'tag_name': 'v1.0.2'})
              .check('1.0.1');
      expect(r.status, UpdateStatus.available);
      expect(r.summary, contains('1.0.2'));
      expect(r.summary, contains('1.0.1'));
      expect(r.summary, startsWith('发现新版本'));
    });

    test('版本相同 → upToDate（不许把「一样」报成「有新版本」）', () async {
      final UpdateResult r =
          await checkerReturning(<String, dynamic>{'tag_name': 'v1.0.2'})
              .check('1.0.2');
      expect(r.status, UpdateStatus.upToDate);
      expect(r.summary, '已是最新版 v1.0.2');
    });

    test('GitHub 上还更旧 → 仍算 upToDate，不谎报', () async {
      final UpdateResult r =
          await checkerReturning(<String, dynamic>{'tag_name': 'v1.0.1'})
              .check('1.0.2');
      expect(r.status, UpdateStatus.upToDate);
    });

    test('请求打的是 latest，且带上仓库地址', () async {
      String? hit;
      await UpdateChecker(fetch: (String url) async {
        hit = url;
        return <String, dynamic>{'tag_name': 'v1.0.2'};
      }).check('1.0.1');
      expect(hit, 'https://api.github.com/repos/$kRepoSlug/releases/latest');
      expect(kRepoUrl, 'https://github.com/wazyf-cell/qingdan');
    });

    test('解析不出版本号 → failed，并说明是发布页的问题', () async {
      final UpdateResult r =
          await checkerReturning(<String, dynamic>{}).check('1.0.1');
      expect(r.status, UpdateStatus.failed);
      expect(r.summary, contains('发布页里没有版本号'));
    });

    test('可执行的失败原因原样透出', () async {
      final UpdateResult r = await UpdateChecker(
        fetch: (_) async =>
            throw const UpdateFetchException('连不上 GitHub（这台设备当前没有网络）'),
      ).check('1.0.1');
      expect(r.status, UpdateStatus.failed);
      expect(r.summary, '检查失败：连不上 GitHub（这台设备当前没有网络）');
    });

    test('没预料到的异常不冒泡到界面，只留类型不留原文', () async {
      // 原文可能含 URL 或系统报错里的路径，界面上一概不显示。
      final UpdateResult r = await UpdateChecker(
        fetch: (_) async => throw StateError('不该冒出来的东西'),
      ).check('1.0.1');
      expect(r.status, UpdateStatus.failed);
      expect(r.error, contains('出了点意外'));
      expect(r.error, isNot(contains('不该冒出来的东西')));
    });

    test('任何一条结论都不会抛异常出来', () async {
      for (final Future<Map<String, dynamic>> Function() f in
          <Future<Map<String, dynamic>> Function()>[
        () async => <String, dynamic>{},
        () async => throw const UpdateFetchException('x'),
        () async => throw Exception('boom'),
      ]) {
        final UpdateResult r =
            await UpdateChecker(fetch: (_) => f()).check('1.0.1');
        expect(r.status, isA<UpdateStatus>());
        expect(r.summary, isNotEmpty);
      }
    });
  });

  group('HTTP 状态码文案', () {
    test('404 / 403 / 429 各说各的事，其余带状态码', () {
      expect(githubStatusReason(404), contains('找不到'));
      expect(githubStatusReason(403), contains('太多次'));
      expect(githubStatusReason(429), contains('太多次'));
      expect(githubStatusReason(500), contains('500'));
      expect(githubStatusReason(503), 'GitHub 返回 HTTP 503');
    });
  });
}
