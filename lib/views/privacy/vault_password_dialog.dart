import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/privacy/privacy_vault_controller.dart';
import '../../utils/theme/app_colors.dart';

class VaultPasswordDialog extends StatefulWidget {
  const VaultPasswordDialog({
    super.key,
    required this.controller,
    this.title = '进入隐私短剧库',
    this.hint = '请输入隐私库密码',
  });

  final PrivacyVaultController controller;
  final String title;
  final String hint;

  static Future<bool> show(
    BuildContext context, {
    required PrivacyVaultController controller,
    String title = '进入隐私短剧库',
    String hint = '请输入隐私库密码',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VaultPasswordDialog(
        controller: controller,
        title: title,
        hint: hint,
      ),
    );
    return result == true;
  }

  @override
  State<VaultPasswordDialog> createState() => _VaultPasswordDialogState();
}

class _VaultPasswordDialogState extends State<VaultPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _verify() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    final success = widget.controller.verifyPassword(text);
    if (success) {
      HapticFeedback.lightImpact();
      Navigator.pop(context, true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = '密码错误，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppColors.hongguoRed, size: 24),
          const SizedBox(width: 8),
          Text(widget.title),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 12),
          const Text(
            '隐私短剧受本地安全加密保护，密码仅保存在本机。',
            style: TextStyle(fontSize: 12, color: AppColors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _verify,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.hongguoRed,
          ),
          child: const Text('确认进入'),
        ),
      ],
    );
  }
}
