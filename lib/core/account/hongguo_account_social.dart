import 'package:flutter/foundation.dart';
import '../../models/catalog/models.dart';
import 'hongguo_account_service.dart';
import 'hongguo_account_session.dart';
import 'hongguo_social_models.dart';

class HongguoAccountSocial extends ChangeNotifier {
  HongguoAccountSocial({HongguoAccountService? service})
    : service = service ?? HongguoAccountService() {
    _revision = this.service.session.revision;
    this.service.session.addListener(_changed);
  }
  static final shared = HongguoAccountSocial();
  final HongguoAccountService service;
  late int _revision;
  final _snapshots = <String, HongguoSocialSnapshot>{};
  final _generations = <String, int>{};
  final _pending = <String>{};
  Future<void> _writes = Future.value();
  bool get active => service.session.loggedIn;
  HongguoSocialSnapshot? snapshot(Drama drama) =>
      _snapshots[drama.cleanSourceId];
  bool busy(Drama drama) => _pending.contains(drama.cleanSourceId);
  void _changed() {
    if (_revision != service.session.revision) {
      _revision = service.session.revision;
      _snapshots.clear();
      _pending.clear();
      _generations.clear();
      notifyListeners();
    }
  }

  void _check(int revision) {
    if (!active || revision != service.session.revision) {
      throw const HongguoAccountFailure('账号已切换，请重新打开', 'CANCELLED');
    }
  }

  Future<void> load(Drama drama) async {
    final owner = _revision, id = drama.cleanSourceId;
    final generation = _generations[id] ?? 0;
    _check(owner);
    final result = await service.social(drama);
    _check(owner);
    if ((_generations[id] ?? 0) == generation) {
      _snapshots[id] = result;
      notifyListeners();
    }
  }

  Future<void> _write(
    Drama drama,
    Future<HongguoSocialSnapshot> Function() run,
  ) async {
    final owner = _revision, id = drama.cleanSourceId;
    _check(owner);
    if (_pending.contains(id)) return;
    _pending.add(id);
    notifyListeners();
    final previous = _writes;
    final task = previous.catchError((Object _) {}).then((_) async {
      _check(owner);
      final result = await run();
      _check(owner);
      _generations[id] = (_generations[id] ?? 0) + 1;
      _snapshots[id] = result;
      notifyListeners();
    });
    _writes = task.catchError((Object _) {});
    try {
      await task;
    } finally {
      if (owner == _revision) {
        _pending.remove(id);
        notifyListeners();
      }
    }
  }

  Future<void> like(Drama drama, HongguoEpisodeLike episode, bool liked) =>
      _write(drama, () => service.setLiked(drama, episode, liked));
  Future<void> follow(Drama drama, HongguoCreator creator, bool followed) =>
      _write(drama, () async {
        final rows = await service.setCreatorFollowing(
          drama,
          creator,
          followed,
        );
        return HongguoSocialSnapshot(snapshot(drama)?.episodes ?? [], rows);
      });
  @override
  void dispose() {
    service.session.removeListener(_changed);
    service.dispose();
    super.dispose();
  }
}
