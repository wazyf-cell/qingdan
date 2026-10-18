/// 隐藏列表页（M6B §B6）：⋮ → 隐藏列表 进来的整页，可查看并恢复/移除隐藏项。
///
/// 数据来自 prefs 的 `chaoxing.view.hidden`（隐藏集）+ `chaoxing.hidden.meta`
/// （展示元数据）。**不进业务库、不参与同步**（学习通域的既有定案）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/chaoxing/chaoxing_time.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_keys.dart';
import 'chaoxing_hidden_entry.dart';
import 'chaoxing_model.dart';

Future<void> showChaoxingHiddenList(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => const ChaoxingHiddenPage(),
    ));

class ChaoxingHiddenPage extends StatelessWidget {
  const ChaoxingHiddenPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Consumer<ChaoxingModel>(
      builder: (BuildContext _, ChaoxingModel model, Widget? _) {
        // 复制一份再排序：model 里的列表可能是 const（直接 sort 会抛 UnsupportedError）。
        final List<ChaoxingHiddenEntry> entries =
            List<ChaoxingHiddenEntry>.of(model.hiddenEntries)
              ..sort((ChaoxingHiddenEntry a, ChaoxingHiddenEntry b) =>
                  b.hiddenAtMs.compareTo(a.hiddenAtMs));
        final int deadCount =
            entries.where((ChaoxingHiddenEntry e) => e.dead).length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('隐藏列表', style: AppTypography.panelTitle),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: AppDimens.s16, bottom: AppDimens.s8),
                  child: Text('${entries.length} 项',
                      style: AppTypography.meta
                          .copyWith(color: colors.textSecondary)),
                ),
              ),
            ),
            actions: <Widget>[
              if (deadCount > 0)
                TextButton(
                  key: ChaoxingKeys.vkey(ChaoxingKeys.hiddenPurgeDead),
                  onPressed: model.purgeDead,
                  child: Text('清理已失效（$deadCount）')),
              TextButton(
                // 只留一个「全部恢复」：`cx-hidden-clear` 与它语义相同，
                // 不放两个长得一样的按钮（B 文档 §B6 的合并约定）。
                key: ChaoxingKeys.vkey(ChaoxingKeys.hiddenRestoreAll),
                onPressed:
                    entries.isEmpty ? null : () => _confirmRestoreAll(context, model),
                child: const Text('全部恢复'),
              ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Text('没有隐藏的待办',
                      style: AppTypography.meta
                          .copyWith(color: colors.textFaint)),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (BuildContext _, int _) => Divider(
                      height: 1, color: colors.divider),
                  itemBuilder: (BuildContext _, int i) =>
                      _row(context, model, entries[i], colors),
                ),
        );
      },
    );
  }

  Widget _row(BuildContext context, ChaoxingModel model,
      ChaoxingHiddenEntry e, AppColors colors) {
    return ListTile(
      key: ChaoxingKeys.vkey(ChaoxingKeys.hiddenRow(e.key)),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s16),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                    color: e.dead ? colors.textFaint : colors.textPrimary)),
          ),
          if (e.dead) ...<Widget>[
            const SizedBox(width: AppDimens.s8),
            _deadTag(colors),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(e.courseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTypography.meta.copyWith(color: colors.textSecondary)),
          Text(_dueLine(e, model.now),
              style: AppTypography.meta.copyWith(color: colors.textFaint)),
        ],
      ),
      trailing: TextButton(
        key: ChaoxingKeys.vkey(ChaoxingKeys.hiddenRestore(e.key)),
        onPressed: () => model.unhide(e.key),
        child: Text(e.dead ? '移除' : '恢复'),
      ),
    );
  }

  /// dead 行也复用同一行截止文案：隐藏项可能已经过了点，写「已逾期」比不写诚实。
  String _dueLine(ChaoxingHiddenEntry e, DateTime now) {
    final DateTime? due = e.dueAt;
    return due == null ? '无截止时间' : formatDeadlineLine(due, now);
  }

  Widget _deadTag(AppColors colors) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(4)),
        child: Text('已失效',
            style: AppTypography.meta.copyWith(color: colors.textFaint)),
      );

  Future<void> _confirmRestoreAll(
      BuildContext context, ChaoxingModel model) async {
    final int n = model.hiddenEntries.length;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('恢复 $n 项？'),
        content: const Text('这些待办会重新出现在学习通列表里。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('恢复')),
        ],
      ),
    );
    if (go == true) await model.unhideAll();
  }
}
