import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/update/apk_download.dart';
import 'package:qingdan/update/update_checker.dart';

/// `apk_download.dart` 里注入点之外的部分：真 HttpClient 流式写盘、取消、
/// 404、校验和取不到时放行、旧安装包清理。
///
/// 这里起的是本机 HttpServer，不走外网——只证明「线上下载」这条代码路径
/// 能在真 socket 上跑通，不证明 GitHub 在某台设备上可达。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('apk_dl_test');
    debugDownloadDir = () => dir;
    debugApkFetcher = null;
    debugTextFetcher = null;
  });

  tearDown(() async {
    debugDownloadDir = null;
    debugApkFetcher = null;
    debugTextFetcher = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final List<int> body = List<int>.generate(200000, (i) => i % 251);

  ReleaseAsset apk(int port, {String name = 'app.apk'}) =>
      ReleaseAsset(name: name, url: 'http://127.0.0.1:$port/$name');

  test('sha256OfFile 分块读，结果与 crypto 一致', () async {
    final File f = File('${dir.path}/x.bin');
    await f.writeAsBytes(body);
    expect(await sha256OfFile(f), sha256.convert(body).toString());
  });

  test('真 HTTP 下载：字节完整、进度收尾等于总长', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) async {
      req.response.contentLength = body.length;
      for (int i = 0; i < body.length; i += 8192) {
        req.response.add(body.sublist(i, (i + 8192).clamp(0, body.length)));
        await req.response.flush();
      }
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final List<(int, int)> progress = <(int, int)>[];
    final File f = await downloadApk(
      apk(server.port),
      onProgress: (int r, int t) => progress.add((r, t)),
      canceled: () => false,
    );

    expect(await f.readAsBytes(), body);
    expect(progress, isNotEmpty);
    expect(progress.last, (body.length, body.length));
  });

  test('HTTP 404 抛 DownloadFailed(含状态码) 且不留半个文件', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) async {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      downloadApk(apk(server.port), onProgress: (_, _) {}, canceled: () => false),
      throwsA(isA<DownloadFailed>().having((DownloadFailed e) => e.reason, 'reason', contains('404'))),
    );
    expect(await File('${dir.path}/update/app.apk').exists(), isFalse);
  });

  test('中途取消：抛 DownloadCanceled 且删掉残包', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) async {
      req.response.contentLength = body.length;
      try {
        for (int i = 0; i < body.length; i += 8192) {
          req.response.add(body.sublist(i, (i + 8192).clamp(0, body.length)));
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await req.response.close();
      } catch (_) {
        // 客户端取消后写会失败，正常。
      }
    });
    addTearDown(() => server.close(force: true));

    bool canceled = false;
    Timer(const Duration(milliseconds: 60), () => canceled = true);

    await expectLater(
      downloadApk(
        apk(server.port),
        onProgress: (_, _) {},
        canceled: () => canceled,
      ),
      throwsA(isA<DownloadCanceled>()),
    );
    expect(await File('${dir.path}/update/app.apk').exists(), isFalse);
  });

  test('取校验和失败返回 null，不挡安装', () async {
    debugTextFetcher = (Uri url) async => throw const SocketException('no net');
    expect(await fetchSums(apk(1, name: 'sha256sums.txt')), isNull);

    debugTextFetcher = (Uri url) async => 'abc  app.apk\n';
    expect(await fetchSums(apk(1, name: 'sha256sums.txt')), 'abc  app.apk\n');
  });

  test('只清一小时前的安装包，新包和目录留着', () async {
    final Directory sub = Directory('${dir.path}/update')..createSync(recursive: true);
    final File old = File('${sub.path}/old.apk')..writeAsBytesSync(<int>[1]);
    final File fresh = File('${sub.path}/fresh.apk')..writeAsBytesSync(<int>[2]);
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
    Directory('${sub.path}/nested').createSync();

    await cleanupOldDownloads();

    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await Directory('${sub.path}/nested').exists(), isTrue);
  });

  test('没有 update 目录时清理安静返回', () async {
    await cleanupOldDownloads();
  });
}
