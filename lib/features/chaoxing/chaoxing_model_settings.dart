part of 'chaoxing_model.dart';

/// 工具栏开关与隐藏项写操作：每个动作都是「改内存 → 通知 → 落盘」。
///
/// 与 [_mutate] 一样顺序固定：先让界面立刻响应，再等偏好写入（写盘失败不
/// 回滚内存，下次启动会回到旧值——比让用户点了没反应好）。
extension ChaoxingModelSettings on ChaoxingModel {
  void tick() {
    now = _clock();
    _changed();
  }

  Future<void> toggleOnlyUnfinished() =>
      _mutate(settings.copyWith(onlyUnfinished: !settings.onlyUnfinished));

  Future<void> toggleOnlySubmittable() =>
      _mutate(settings.copyWith(onlySubmittable: !settings.onlySubmittable));

  Future<void> setSortBy(ChaoxingSortBy s) =>
      _mutate(settings.copyWith(sortBy: s));

  Future<void> setTab(ChaoxingTab t) => _mutate(settings.copyWith(tab: t));

  /// 筛选弹层的「重置」：只清筛选，页签与隐藏集是两回事，不能顺手抹掉。
  Future<void> resetFilters() => _mutate(ChaoxingViewSettings(
        hidden: settings.hidden,
        tab: settings.tab,
      ));

  /// 隐藏一条：key 进隐藏集，展示元数据进 `chaoxing.hidden.meta`。
  Future<void> hide(ChaoxingTask t) async {
    await _mutate(
        settings.copyWith(hidden: Set<String>.of(settings.hidden)..add(t.key)));
    await _saveHiddenMeta(withHiddenAdded(hiddenEntries, t, now));
  }

  /// 恢复单条（隐藏列表页的「恢复」）。
  Future<void> unhide(String key) async {
    await _mutate(settings.copyWith(
        hidden: Set<String>.of(settings.hidden)..remove(key)));
    await _saveHiddenMeta(withoutHidden(hiddenEntries, key));
  }

  Future<void> unhideAll() async {
    await _mutate(settings.copyWith(hidden: const <String>{}));
    await _saveHiddenMeta(const <ChaoxingHiddenEntry>[]);
  }

  /// 清掉「本次刷新里已经不再出现」的隐藏项（隐藏列表页的「清理已失效」）。
  /// 隐藏键也一并删掉：条目本身都没了，留着键只会挡住将来同 id 的新待办。
  Future<void> purgeDead() async {
    final List<String> keys = deadHiddenKeys(hiddenEntries);
    if (keys.isEmpty) return;
    await _mutate(settings.copyWith(
        hidden: Set<String>.of(settings.hidden)..removeAll(keys)));
    await _saveHiddenMeta(withoutDead(hiddenEntries));
  }

  Future<void> _saveHiddenMeta(List<ChaoxingHiddenEntry> next) async {
    hiddenEntries = next;
    _changed();
    await _prefs.saveHiddenMeta(next);
  }

  Future<void> _mutate(ChaoxingViewSettings next) async {
    settings = next;
    _changed();
    await _prefs.save(next);
  }
}
