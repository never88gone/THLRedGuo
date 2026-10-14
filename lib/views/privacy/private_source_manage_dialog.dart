import 'package:flutter/material.dart';

import '../../local_store.dart';
import '../../utils/privacy/privacy_vault_controller.dart';
import '../../utils/theme/app_colors.dart';
import 'vault_password_dialog.dart';
import 'vault_password_setup_dialog.dart';

class PrivateSourceManageDialog extends StatefulWidget {
  const PrivateSourceManageDialog({
    super.key,
    required this.store,
    required this.vaultController,
  });

  final LocalStore store;
  final PrivacyVaultController vaultController;

  static Future<void> show(
    BuildContext context, {
    required LocalStore store,
    required PrivacyVaultController vaultController,
  }) async {
    if (!vaultController.hasPassword) {
      final setupSuccess = await VaultPasswordSetupDialog.show(
        context,
        controller: vaultController,
      );
      if (!setupSuccess) return;
    } else {
      final verified = await VaultPasswordDialog.show(
        context,
        controller: vaultController,
        title: '隐私数据源验证',
        hint: '请输入隐私密码进行管理',
      );
      if (!verified) return;
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => PrivateSourceManageDialog(
        store: store,
        vaultController: vaultController,
      ),
    );
  }

  @override
  State<PrivateSourceManageDialog> createState() =>
      _PrivateSourceManageDialogState();
}

class _PrivateSourceManageDialogState extends State<PrivateSourceManageDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final sources = widget.store.sources;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.shield_rounded,
                color: AppColors.hongguoRed,
                size: 24,
              ),
              SizedBox(width: 8),
              Text('隐私数据源管理'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '被设为隐私的数据源在切换时需输入密码验证，且其观看记录绝不出现在最近观看中。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sources.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      color: AppColors.darkBorderSubtle,
                    ),
                    itemBuilder: (context, index) {
                      final site = sources[index];
                      final isPrivate = widget.store.isPrivateSource(site.id);

                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Text(
                              site.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            if (isPrivate) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSubtle12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '隐私',
                                  style: TextStyle(
                                    color: AppColors.hongguoRed,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          site.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                          ),
                        ),
                        value: isPrivate,
                        activeThumbColor: AppColors.hongguoRed,
                        activeTrackColor: AppColors.accentTrack35,
                        onChanged: (val) {
                          widget.store.setSourcePrivate(site.id, val);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.hongguoRed,
              ),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}
