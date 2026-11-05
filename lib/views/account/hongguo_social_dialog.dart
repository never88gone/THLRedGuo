import 'package:flutter/material.dart';
import '../../core/account/hongguo_account_social.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../models/catalog/models.dart';

class HongguoSocialButton extends StatelessWidget {
  const HongguoSocialButton({super.key, required this.drama, this.episode = 1});
  final Drama drama;
  final int episode;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: HongguoAccountSocial.shared,
    builder: (context, _) =>
        drama.source == 'hongguo' && HongguoAccountSocial.shared.active
        ? TextButton.icon(
            key: const ValueKey('account-social-open'),
            onPressed: () => showHongguoSocialDialog(context, drama, episode),
            icon: const Icon(Icons.favorite_border, size: 18),
            label: const Text('点赞与关注'),
          )
        : const SizedBox.shrink(),
  );
}

Future<void> showHongguoSocialDialog(
  BuildContext context,
  Drama drama,
  int episode,
) => showDialog<void>(
  context: context,
  builder: (_) => _SocialDialog(drama: drama, episode: episode),
);

class _SocialDialog extends StatefulWidget {
  const _SocialDialog({required this.drama, required this.episode});
  final Drama drama;
  final int episode;
  @override
  State<_SocialDialog> createState() => _SocialDialogState();
}

class _SocialDialogState extends State<_SocialDialog> {
  final model = HongguoAccountSocial.shared;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    await _run(() => model.load(widget.drama));
    if (mounted) setState(() => loading = false);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => error = null);
    } catch (issue) {
      if (mounted) {
        setState(
          () => error = issue is HongguoAccountFailure
              ? issue.message
              : '互动请求失败，请重试',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final data = model.snapshot(widget.drama),
          like = model.snapshot(widget.drama)?.episode(widget.episode);
      final busy = model.busy(widget.drama) || loading;
      return AlertDialog(
        title: const Text('点赞与关注'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.drama.title),
                if (!model.active)
                  const Text('请先登录红果账号')
                else ...[
                  if (loading) const LinearProgressIndicator(),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (data != null) ...[
                    const SizedBox(height: 12),
                    if (like != null)
                      FilledButton.icon(
                        key: const ValueKey('account-episode-like'),
                        onPressed: busy
                            ? null
                            : () => _run(
                                () =>
                                    model.like(widget.drama, like, !like.liked),
                              ),
                        icon: Icon(
                          like.liked ? Icons.favorite : Icons.favorite_border,
                        ),
                        label: Text(
                          '第 ${like.number} 集 · ${like.liked ? "取消点赞" : "点赞"} · ${like.count}',
                        ),
                      )
                    else
                      Text('第 ${widget.episode} 集暂未提供点赞状态'),
                    const SizedBox(height: 20),
                    const Text(
                      '创作者／演员',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (data.creatorError != null)
                      Text('关注列表获取失败：${data.creatorError}')
                    else if (data.creators.isEmpty)
                      const Text('本剧暂无可关注的创作者账号'),
                    for (final creator in data.creators)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                creator.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              key: ValueKey('account-creator-${creator.id}'),
                              onPressed:
                                  busy ||
                                      creator.following == null ||
                                      (!creator.canFollow &&
                                          creator.following != true) ||
                                      creator.id == model.service.session.id
                                  ? null
                                  : () => _run(
                                      () => model.follow(
                                        widget.drama,
                                        creator,
                                        !creator.following!,
                                      ),
                                    ),
                              child: Text(
                                creator.following == null
                                    ? '状态不可用'
                                    : creator.following!
                                    ? '取消关注'
                                    : '关注',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (model.active)
            TextButton(onPressed: busy ? null : _load, child: const Text('刷新')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
