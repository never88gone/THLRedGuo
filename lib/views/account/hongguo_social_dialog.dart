import 'package:flutter/material.dart';
import '../../core/account/hongguo_account_social.dart';
import '../../models/catalog/models.dart';
import '../../utils/theme/app_colors.dart';

class HongguoSocialButton extends StatelessWidget {
  const HongguoSocialButton({super.key, required this.drama, this.episode = 1});
  final Drama drama;
  final int episode;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: HongguoAccountSocial.shared,
    builder: (context, _) {
      final model = HongguoAccountSocial.shared;
      if (drama.source != 'hongguo' || !model.active) {
        return const SizedBox.shrink();
      }
      final data = model.snapshot(drama);
      final like = data?.episode(episode);
      final creator = data?.creators.firstOrNull;
      final busy = model.busy(drama);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('account-social-like-btn'),
              style: FilledButton.styleFrom(
                foregroundColor: (like?.liked ?? false) ? AppColors.hongguoRed : null,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: busy
                  ? null
                  : () {
                      if (data == null) {
                        model.load(drama);
                        return;
                      }
                      if (like != null) {
                        model.like(drama, like, !like.liked);
                      }
                    },
              icon: Icon(
                (like?.liked ?? false) ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: (like?.liked ?? false) ? AppColors.hongguoRed : null,
              ),
              label: Text(
                like != null
                    ? (like.liked ? '已赞 (${like.count})' : '点赞 (${like.count})')
                    : '点赞',
              ),
            ),
            if (creator != null)
              OutlinedButton.icon(
                key: ValueKey('account-creator-${creator.id}'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: busy ||
                        creator.following == null ||
                        (!creator.canFollow && creator.following != true) ||
                        creator.id == model.service.session.id
                    ? null
                    : () {
                        model.follow(drama, creator, !creator.following!);
                      },
                icon: Icon(
                  (creator.following ?? false) ? Icons.check : Icons.add,
                  size: 16,
                ),
                label: Text(
                  creator.following == true
                      ? '${creator.name} · 已关注'
                      : '关注主播 ${creator.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
    },
  );
}

Future<void> showHongguoSocialDialog(
  BuildContext context,
  Drama drama,
  int episode,
) async {
  // 点赞与关注已改为直接操作，不再显示浮层弹窗
  final model = HongguoAccountSocial.shared;
  if (!model.active) return;
  final data = model.snapshot(drama);
  if (data == null) {
    await model.load(drama);
  }
}
