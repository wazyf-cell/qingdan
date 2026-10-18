import 'dart:math';

/// 应用内实体 id 生成器（纯函数，无 IO）。
///
/// 约束：不引入第三方依赖（任务铁律），因此不用 uuid 包，改用
/// 「微秒时间戳(base36) + 进程内自增计数 + 随机数」拼接：
/// - 同一微秒内靠计数器与随机数区分，冲突概率可忽略；
/// - 主键为 TEXT，与迁移 DDL 一致。
class IdGenerator {
  IdGenerator._();

  static int _counter = 0;
  static final Random _random = Random();

  /// 生成一个进程内唯一、跨进程基本不冲突的 id（约 18 字符）。
  static String next() {
    final String ts = DateTime.now().toUtc().microsecondsSinceEpoch
        .toRadixString(36);
    final String counter =
        (_counter++ & 0xFFF).toRadixString(36).padLeft(2, '0');
    final String rand =
        _random.nextInt(0x10000).toRadixString(36).padLeft(2, '0');
    return '$ts$counter$rand';
  }
}
