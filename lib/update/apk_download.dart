/// 把发布页里的 APK 下到缓存目录：流式写盘、可取消、带进度与 sha256。
///
/// 只有用户点了「下载并安装」才会走到这里——**没有后台自动下载**。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'update_checker.dart';

/// 下载被用户取消。与外层失败分开：取消不报错、不弹红字。
class DownloadCanceled implements Exception {
  const DownloadCanceled();
}

/// 下载失败的「人话原因」，直接显示在弹层里。
class DownloadFailed implements Exception {
  const DownloadFailed(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

typedef ApkFetcher = Future<void> Function({
  required Uri url,
  required File target,
  required void Function(int received, int total) onProgress,
  required bool Function() canceled,
});

typedef TextFetcher = Future<String> Function(Uri url);

/// 测试注入点（与学习通的 launcher  seams 同一套路）：widget 测试里没有
/// 平台通道也没有真网络，只能把这两件事换掉。
ApkFetcher? debugApkFetcher;
TextFetcher? debugTextFetcher;
Directory Function()? debugDownloadDir;

/// 下载到 `缓存目录/update/<文件名>`。已存在的旧副本先删掉，避免把两次下载写混。
Future<File> downloadApk(
  ReleaseAsset asset, {
  required void Function(int received, int total) onProgress,
  required bool Function() canceled,
}) async {
  final Directory dir = debugDownloadDir != null
      ? debugDownloadDir!()
      : await getTemporaryDirectory();
  final File target = File('${dir.path}/update/${asset.name}');
  await target.parent.create(recursive: true);
  if (await target.exists()) await target.delete();
  final ApkFetcher fetch = debugApkFetcher ?? _httpDownload;
  try {
    await fetch(
      url: Uri.parse(asset.url),
      target: target,
      onProgress: onProgress,
      canceled: canceled,
    );
  } on DownloadCanceled {
    await _deleteQuietly(target);
    rethrow;
  } on DownloadFailed {
    await _deleteQuietly(target);
    rethrow;
  } catch (e) {
    await _deleteQuietly(target);
    throw DownloadFailed('下载失败（${e.runtimeType}）');
  }
  if (canceled()) {
    await _deleteQuietly(target);
    throw const DownloadCanceled();
  }
  return target;
}

/// 取校验和正文；拿不到就返回 null（跳过校验，不让「多要一个文件」卡住安装）。
Future<String?> fetchSums(ReleaseAsset asset) async {
  try {
    final TextFetcher fetch = debugTextFetcher ?? _httpText;
    return await fetch(Uri.parse(asset.url));
  } catch (_) {
    return null;
  }
}

/// 文件的 sha256（小写十六进制）。分块读，25MB 也不会整份进内存。
Future<String> sha256OfFile(File file) async {
  final Digest d = await sha256.bind(file.openRead()).first;
  return d.toString();
}

/// 清掉上次留下的安装包（缓存目录，装完/放弃后不该一直占 25MB）。
///
/// 只删超过 [olderThan] 的：刚下载完还在等系统安装器的那个必须留着。
Future<void> cleanupOldDownloads({Duration olderThan = const Duration(hours: 1)}) async {
  try {
    final Directory dir = debugDownloadDir != null
        ? debugDownloadDir!()
        : await getTemporaryDirectory();
    final Directory sub = Directory('${dir.path}/update');
    if (!await sub.exists()) return;
    final DateTime cutoff = DateTime.now().subtract(olderThan);
    await for (final FileSystemEntity e in sub.list()) {
      if (e is! File) continue;
      final DateTime at = (await e.stat()).modified;
      if (at.isBefore(cutoff)) await _deleteQuietly(e);
    }
  } catch (_) {
    // 清理是顺手的事，失败不该打扰任何人。
  }
}

Future<void> _deleteQuietly(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

Future<void> _httpDownload({
  required Uri url,
  required File target,
  required void Function(int received, int total) onProgress,
  required bool Function() canceled,
}) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  IOSink? sink;
  try {
    final HttpClientRequest req = await client.getUrl(url);
    req.headers.set(HttpHeaders.userAgentHeader, 'qingdan-app');
    final HttpClientResponse res =
        await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != HttpStatus.ok) {
      throw DownloadFailed('下载地址返回 HTTP ${res.statusCode}');
    }
    final int total = res.contentLength;
    sink = target.openWrite();
    int received = 0;
    // 每 200ms 报一次进度：每个块都 setState 会把主线程拖成幻灯片。
    final Stopwatch tick = Stopwatch()..start();
    await for (final List<int> chunk in res.timeout(const Duration(seconds: 30))) {
      if (canceled()) throw const DownloadCanceled();
      sink.add(chunk);
      received += chunk.length;
      if (tick.elapsedMilliseconds >= 200) {
        tick.reset();
        onProgress(received, total);
      }
    }
    onProgress(received, total);
  } on TimeoutException {
    throw const DownloadFailed('下载超时，请检查网络后重试');
  } on SocketException {
    throw const DownloadFailed('连不上 GitHub（这台设备当前没有网络）');
  } on HttpException {
    throw const DownloadFailed('下载连接中断，请重试');
  } finally {
    await sink?.close();
    client.close(force: true);
  }
}

Future<String> _httpText(Uri url) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final HttpClientRequest req = await client.getUrl(url);
    req.headers.set(HttpHeaders.userAgentHeader, 'qingdan-app');
    final HttpClientResponse res =
        await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != HttpStatus.ok) {
      throw DownloadFailed('HTTP ${res.statusCode}');
    }
    return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
  } finally {
    client.close(force: true);
  }
}
