import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/privacy/privacy_vault_controller.dart';
import '../../utils/theme/app_colors.dart';

class VaultPasswordSetupDialog extends StatefulWidget {
  const VaultPasswordSetupDialog({
    super.key,
    required this.controller,
  });

  final PrivacyVaultController controller;

  static Future<bool> show(
    BuildContext context, {
    required PrivacyVaultController controller,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VaultPasswordSetupDialog(controller: controller),
    );
    return result == true;
  }

  @override
  State<VaultPasswordSetupDialog> createState() =>
      _VaultPasswordSetupDialogState();
}

class _VaultPasswordSetupDialogState extends State<VaultPasswordSetupDialog> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _error = null);
    final hasOld = widget.controller.hasPassword;

    if (hasOld) {
      final oldPin = _oldController.text.trim();
      if (!widget.controller.verifyPassword(oldPin)) {
        HapticFeedback.heavyImpact();
        setState(() => _error = '原密码不正确');
        return;
      }
    }

    final newPin = _newController.text.trim();
    final confirmPin = _confirmController.text.trim();

    if (newPin.length < 4) {
      setState(() => _error = '新密码长度至少需要 4 位');
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }

    widget.controller.setPassword(newPin);
    HapticFeedback.mediumImpact();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final hasOld = widget.controller.hasPassword;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.security_rounded,
              color: AppColors.hongguoRed, size: 24),
          const SizedBox(width: 8),
          Text(hasOld ? '修改隐私库密码' : '设置隐私库密码'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasOld) ...[
              TextField(
                controller: _oldController,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: '当前原密码',
                  hintText: '请输入原密码进行验证',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _newController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: '新密码',
                hintText: '至少 4 位数字或字符',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: '确认新密码',
                hintText: '请再次输入新密码',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: !_obscure,
                  activeColor: AppColors.hongguoRed,
                  onChanged: (val) => setState(() => _obscure = !(val ?? false)),
                ),
                const Text('显示密码内容', style: TextStyle(fontSize: 12)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.hongguoRed,
          ),
          child: const Text('保存密码'),
        ),
      ],
    );
  }
}
