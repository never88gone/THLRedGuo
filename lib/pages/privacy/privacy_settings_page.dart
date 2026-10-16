import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/privacy/privacy_vault_controller.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/privacy/private_source_manage_dialog.dart';
import 'package:THLRedLook/views/privacy/vault_password_dialog.dart';
import 'package:THLRedLook/views/privacy/vault_password_setup_dialog.dart';
import 'package:THLRedLook/views/settings/settings_group_view.dart';
import 'package:THLRedLook/pages/privacy/privacy_gesture_setup_page.dart';
import 'package:THLRedLook/pages/privacy/privacy_vault_page.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({
    super.key,
    required this.controller,
    this.vaultController,
    this.repository,
    this.store,
  });

  final PrivacyLockController controller;
  final PrivacyVaultController? vaultController;
  final AppRepository? repository;
  final LocalStore? store;

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  late final PrivacyVaultController _vaultController;

  @override
  void initState() {
    super.initState();
    _vaultController = widget.vaultController ??
        PrivacyVaultController(widget.controller.preferences);
  }

  Future<void> _togglePrivacyMode(bool value) async {
    if (value && !widget.controller.hasGesture) {
      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => PrivacyGestureSetupPage(
            controller: widget.controller,
          ),
        ),
      );
      if (success != true) return;
    } else {
      await widget.controller.setEnabled(value);
    }
    if (mounted) setState(() {});
  }

  Future<void> _changeGesture() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => PrivacyGestureSetupPage(
          controller: widget.controller,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _setVaultPassword() async {
    final success = await VaultPasswordSetupDialog.show(
      context,
      controller: _vaultController,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('隐私库密码已更新')),
      );
      setState(() {});
    }
  }

  Future<void> _openVault() async {
    if (widget.repository == null || widget.store == null) return;
    if (!_vaultController.hasPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置隐私库密码')),
      );
      await _setVaultPassword();
      if (!_vaultController.hasPassword) return;
    }

    if (!_vaultController.isUnlocked) {
      if (!mounted) return;
      final unlocked = await VaultPasswordDialog.show(
        context,
        controller: _vaultController,
      );
      if (!unlocked || !mounted) return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PrivacyVaultPage(
          controller: _vaultController,
          repository: widget.repository!,
          store: widget.store!,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _clearVault() async {
    if (_vaultController.vaultCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('隐私库暂无剧集')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空隐私短剧库？'),
        content: const Text('确认清空隐私库中保存的全部短剧吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _vaultController.clearVault();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('隐私库已清空')),
        );
        setState(() {});
      }
    }
  }

  Future<void> _chooseTimeout() async {
    final options = [
      {'label': '离开后台 1 分钟后（推荐）', 'seconds': 60},
      {'label': '离开后台 30 秒后', 'seconds': 30},
      {'label': '离开后台 5 分钟后', 'seconds': 300},
      {'label': '立即锁定', 'seconds': 0},
    ];

    final selected = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '后台自动锁定触发时机',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final opt in options)
              ListTile(
                title: Text(opt['label'] as String),
                trailing: widget.controller.autoLockSeconds == opt['seconds']
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.hongguoRed)
                    : null,
                onTap: () => Navigator.pop(context, opt['seconds'] as int),
              ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      await widget.controller.setAutoLockSeconds(selected);
      setState(() {});
    }
  }

  String _timeoutLabel(int seconds) {
    return switch (seconds) {
      0 => '立即锁定',
      30 => '离开后台 30 秒',
      60 => '离开后台 1 分钟',
      300 => '离开后台 5 分钟',
      _ => '$seconds 秒',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = widget.controller.enabled;
    final hasGesture = widget.controller.hasGesture;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('隐私与安全设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          SettingsGroupCard(
            title: '应用手势锁保护',
            icon: Icons.security_rounded,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_person_rounded),
                title: const Text('启用手势隐私锁'),
                subtitle: const Text('冷启动或从后台切回时需输入九宫格手势解锁'),
                value: enabled,
                activeThumbColor: AppColors.hongguoRed,
                activeTrackColor: AppColors.accentTrack35,
                onChanged: _togglePrivacyMode,
              ),
              if (enabled || hasGesture) ...[
                ListTile(
                  leading: const Icon(Icons.lock_reset_rounded),
                  title: const Text('修改手势密码'),
                  subtitle: const Text('重新绘制并更新九宫格图案'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _changeGesture,
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('后台自动锁定'),
                  subtitle: Text(_timeoutLabel(widget.controller.autoLockSeconds)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _chooseTimeout,
                ),
              ],
            ],
          ),
          SettingsGroupCard(
            title: '隐私短剧库管理',
            icon: Icons.shield_rounded,
            children: [
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('隐私库访问密码'),
                subtitle: Text(
                  _vaultController.hasPassword ? '已设置（点击修改）' : '未设置（点击设置）',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _setVaultPassword,
              ),
              if (widget.repository != null && widget.store != null)
                ListTile(
                  leading: const Icon(Icons.video_library_rounded),
                  title: const Text('进入隐私短剧库'),
                  subtitle: Text('已加密保护 ${_vaultController.vaultCount} 部短剧'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openVault,
                ),
              if (widget.store != null)
                ListTile(
                  leading: const Icon(Icons.source_rounded),
                  title: const Text('隐私数据源管理'),
                  subtitle: Text(
                    '已将 ${widget.store!.privateSources.length} 个数据源设为隐私',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    PrivateSourceManageDialog.show(
                      context,
                      store: widget.store!,
                      vaultController: _vaultController,
                    );
                  },
                ),
              if (_vaultController.vaultCount > 0)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_rounded,
                      color: AppColors.error),
                  title: const Text('清空隐私短剧库',
                      style: TextStyle(color: AppColors.error)),
                  subtitle: const Text('清空隐私库中所有的私密短剧'),
                  onTap: _clearVault,
                ),
            ],
          ),
          SettingsGroupCard(
            title: '功能说明',
            icon: Icons.info_outline_rounded,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '1. 隐私短剧库：可将任意短剧加入隐私库。加入后将在公开追剧列表中自动隐藏，唯有通过密码鉴权方可查看与播放。\n'
                  '2. 应用手势锁：冷启动或切入后台离开后重新进入时触发九宫格解锁。\n'
                  '3. 后台虚化保护：App 切入后台或多任务预览时自动进行高斯模糊虚化，防止隐私泄露。\n'
                  '4. 隐私数据源模式：设为隐私的数据源切换时需输入密码，且最近观看记录不会显示该数据源的内容。\n'
                  '5. 本地安全：所有密码与隐私配置均使用加盐安全哈希于本地离线存储，绝不上报云端，严格保护您的私密观影体验。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

