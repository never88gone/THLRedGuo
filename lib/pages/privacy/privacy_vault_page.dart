import 'package:flutter/material.dart';

import '../../core_bridge.dart';
import '../../detail_screen.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../../player_screen.dart';
import '../../utils/privacy/privacy_vault_controller.dart';
import '../../utils/theme/app_colors.dart';
import '../../widgets.dart';

class PrivacyVaultPage extends StatefulWidget {
  const PrivacyVaultPage({
    super.key,
    required this.controller,
    required this.repository,
    required this.store,
  });

  final PrivacyVaultController controller;
  final AppRepository repository;
  final LocalStore store;

  @override
  State<PrivacyVaultPage> createState() => _PrivacyVaultPageState();
}

class _PrivacyVaultPageState extends State<PrivacyVaultPage> {
  void _openDetail(Drama drama) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          drama: drama,
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
  }

  void _playDrama(Drama drama) async {
    try {
      final detail = await widget.repository.detail(drama);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            detail: detail,
            initialIndex: 0,
            repository: widget.repository,
            store: widget.store,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载播放失败: $e')),
        );
      }
    }
  }

  Future<void> _removeFromVault(Drama drama) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出隐私库？'),
        content: Text('确认将《${drama.title}》移出隐私库吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.controller.removeFromVault(drama.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dramas = widget.controller.vaultDramas;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          widget.controller.lock();
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        appBar: AppBar(
          title: Text('隐私短剧库 · ${dramas.length}'),
          actions: [
            IconButton(
              tooltip: '安全锁定并退出',
              icon: const Icon(Icons.lock_rounded, color: AppColors.hongguoRed),
              onPressed: () {
                widget.controller.lock();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: dramas.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.accentSubtle12,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: AppColors.hongguoRed,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '隐私短剧库暂无内容',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '可在任何短剧的更多操作菜单或详情页中，选择「加入隐私库」进行加密守护。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: dramas.length,
                itemBuilder: (context, index) {
                  final drama = dramas[index];
                  return DramaTile(
                    drama: drama,
                    repository: widget.repository,
                    onTap: () => _openDetail(drama),
                    onMore: () => _removeFromVault(drama),
                    actions: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '立即播放',
                          icon: const Icon(Icons.play_arrow_rounded,
                              color: AppColors.hongguoRed),
                          onPressed: () => _playDrama(drama),
                        ),
                        IconButton(
                          tooltip: '移出隐私库',
                          icon: const Icon(Icons.lock_open_rounded, size: 20),
                          onPressed: () => _removeFromVault(drama),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
