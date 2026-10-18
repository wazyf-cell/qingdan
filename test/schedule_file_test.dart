import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_convert/gbk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/course/schedule_file.dart';

/// 文件读取与编码探测（导入向导步骤 1）。
///
/// **直接吃仓库里的真实样本**，不只看 prose：`相关来源或素材/课表模板.xlsx`
/// 的单元格全是共享字符串（`1`、`2` 是文本不是数字），这条必须被测出来。
void main() {
  const String samplePath = '相关来源或素材/课表模板.xlsx';

  test('真实 xlsx 样本：表头 7 列 + 3 行数据，数字按文本读出', () {
    final File f = File(samplePath);
    expect(f.existsSync(), isTrue,
        reason: '样本文件不在，这条测试就什么都没验（路径相对包根目录）');

    final ScheduleTable t = readScheduleTable(f.readAsBytesSync());
    expect(t.encoding, FileEncoding.xlsx);
    expect(t.sheetName, isNotNull);
    expect(
        t.rows.first.take(7).toList(),
        <String>[
          '课程名称', '星期', '开始节数', '结束节数', '老师', '地点', '周数',
        ]);
    expect(t.rows[1], <String>[
      '高等数学', '1', '1', '2', '小明', '逸夫楼201', '1-5、7-11单、12-16双',
    ]);
    expect(t.rows[2][0], '线性代数');
    expect(t.rows[3][0], '大学英语');
    expect(t.rows[3][6], '2、5、8');
    expect(t.dataRowCount, 3);
    expect(t.columnCount, 7);
  });

  test('UTF-8 无 BOM 的 CSV', () {
    final ScheduleTable t =
        readScheduleTable(Uint8List.fromList(utf8.encode('课程名称,星期\n高数,1\n')));
    expect(t.encoding, FileEncoding.utf8);
    expect(t.rows[1], <String>['高数', '1']);
  });

  test('UTF-8 带 BOM：BOM 不污染第一个表头单元格', () {
    final List<int> bytes = <int>[
      0xEF, 0xBB, 0xBF,
      ...utf8.encode('课程名称,星期\n高数,1\n'),
    ];
    final ScheduleTable t = readScheduleTable(Uint8List.fromList(bytes));
    expect(t.encoding, FileEncoding.utf8Bom);
    expect(t.rows.first.first, '课程名称');
    expect(t.rows.first.first.codeUnitAt(0), isNot(0xFEFF));
  });

  test('GBK 中文 CSV：探测到 GBK 并解出正确汉字（§3.1 探测链第三步）', () {
    final List<int> bytes = gbk.encode('课程名称,星期,周数\n高等数学,1,1-5\n');
    final ScheduleTable t = readScheduleTable(Uint8List.fromList(bytes));
    expect(t.encoding, FileEncoding.gbk);
    expect(t.rows.first, <String>['课程名称', '星期', '周数']);
    expect(t.rows[1], <String>['高等数学', '1', '1-5']);
  });

  test('强制切换编码：UTF-8 读 GBK 字节要报错而不是给乱码，切到 GBK 就读对', () {
    final List<int> bytes = gbk.encode('课程名称,星期\n高等数学,1\n');
    expect(
        () => readScheduleTable(Uint8List.fromList(bytes),
            forceEncoding: FileEncoding.utf8),
        throwsA(isA<ScheduleFileException>()));
    expect(
        readScheduleTable(Uint8List.fromList(bytes),
                forceEncoding: FileEncoding.gbk)
            .rows[1][0],
        '高等数学');
  });

  test('分隔符自动探测：分号 CSV 也能切开', () {
    final ScheduleTable t = readScheduleTable(
        Uint8List.fromList(utf8.encode('课程名称;星期;周数\n高数;1;1-5\n')));
    expect(t.rows[1], <String>['高数', '1', '1-5']);
  });

  test('空文件与全空表报错，不返回空表冒充成功', () {
    expect(() => readScheduleTable(Uint8List(0)),
        throwsA(isA<ScheduleFileException>()));
    expect(
        () => readScheduleTable(Uint8List.fromList(utf8.encode('\n\n , , \n'))),
        throwsA(isA<ScheduleFileException>()));
  });

  test('describeEncoding 覆盖四种结论（界面直接展示这段文案）', () {
    expect(describeEncoding(FileEncoding.xlsx), contains('xlsx'));
    expect(describeEncoding(FileEncoding.utf8Bom), contains('BOM'));
    expect(describeEncoding(FileEncoding.gbk), 'GBK');
  });
}
