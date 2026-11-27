import 'dart:async';

import 'package:flutter/material.dart';

import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/core/cast/haw_cast_service.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/player/haw_cast_sheet_cards.dart';

Future<bool> showHawCastSheet(
  BuildContext context, {
  required Future<bool> Function(HawCastDevice device) onCastToDevice,
  Future<bool> Function()? onStartAirPlay,
  VoidCallback? onDisconnect,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.transparent,
    builder: (ctx) => _HawCastSheet(
      onCastToDevice: onCastToDevice,
      onStartAirPlay: onStartAirPlay,
      onDisconnect: onDisconnect,
    ),
  );
  return result == true;
}

class _HawCastSheet extends StatefulWidget {
  const _HawCastSheet({
    required this.onCastToDevice,
    this.onStartAirPlay,
    this.onDisconnect,
  });

  final Future<bool> Function(HawCastDevice device) onCastToDevice;
  final Future<bool> Function()? onStartAirPlay;
  final VoidCallback? onDisconnect;

  @override
  State<_HawCastSheet> createState() => _HawCastSheetState();
}

class _HawCastSheetState extends State<_HawCastSheet> {
  final HawCastService _service = HawCastService.instance;
  final TextEditingController _ipController = TextEditingController();

  bool _showManualInput = false;
  bool _probing = false;
  String? _connectingId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_service.startDiscovery());
  }

  @override
  void dispose() {
    unawaited(_service.stopDiscovery(notify: false));
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connectDevice(HawCastDevice device) async {
    if (_connectingId != null || _probing) return;
    setState(() {
      _connectingId = device.id;
      _errorMessage = null;
    });
    final ok = await widget.onCastToDevice(device);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _connectingId = null;
        _errorMessage = '投屏至「${device.name}」失败，请确认双方处于同一局域网并已开启接收端';
      });
    }
  }

  Future<void> _connectManual() async {
    final text = _ipController.text.trim();
    if (text.isEmpty || _probing || _connectingId != null) return;
    setState(() {
      _probing = true;
      _errorMessage = null;
    });
    final device = await _service.probeManualDevice(text);
    if (!mounted) return;
    setState(() => _probing = false);
    if (device == null) {
      setState(() {
        _errorMessage = '未能连接 $text，请核对 IP 地址与接收端端口（默认 18188）';
      });
      return;
    }
    await _connectDevice(device);
  }

  Future<void> _triggerAirPlay() async {
    final fn = widget.onStartAirPlay;
    if (fn == null || _probing || _connectingId != null) return;
    setState(() {
      _probing = true;
      _errorMessage = null;
    });
    final ok = await fn();
    if (!mounted) return;
    setState(() => _probing = false);
    if (ok) {
      Navigator.of(context).pop(false);
    } else {
      setState(() {
        _errorMessage = '无法准备 AirPlay 视频流，请确认当前网络状态后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightSurfaceHigh;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        maxWidth: 560,
      ),
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final devices = _service.devices;
          final activeId = _service.activeDevice?.id;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cast_connected_rounded,
                      color: AppColors.hongguoRed,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '投屏到电视 / 接收端',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新设备',
                      onPressed: _connectingId != null
                          ? null
                          : () => unawaited(_service.startDiscovery()),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              if (_service.scanning || _connectingId != null || _probing)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.hongguoRed,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.hongguoRedWithAlpha(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.hongguoRedWithAlpha(0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        color: AppColors.hongguoRed,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '糖葫芦专属私有投屏协议 · 支持加密视频流无损直投',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_service.isAirPlaySupported && widget.onStartAirPlay != null)
                HawCastAirPlayCard(
                  cardBg: cardBg,
                  borderColor: borderColor,
                  onTap: (_probing || _connectingId != null)
                      ? null
                      : _triggerAirPlay,
                ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentSubtle12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                ),
              Flexible(
                child: devices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tv_off_rounded,
                              size: 40,
                              color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _service.scanning
                                  ? '正在扫描同一 Wi-Fi 下的糖葫芦接收端...'
                                  : '暂未发现支持的接收端设备',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _service.scanError ??
                                  '请在电视或手机接收端打开「糖葫芦投屏接收器」，确保与当前设备在同一局域网内',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                        itemCount: devices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return HawCastDeviceCard(
                            device: device,
                            cardBg: cardBg,
                            borderColor: borderColor,
                            isConnected: _service.isCasting && activeId == device.id,
                            isBusy: _connectingId == device.id,
                            onTap: _connectingId != null
                                ? null
                                : () => _connectDevice(device),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showManualInput)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ipController,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _connectManual(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '输入接收端 IP（如 192.168.1.50）',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _probing ? null : _connectManual,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.hongguoRed,
                                foregroundColor: AppColors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                              ),
                              child: const Text('连接'),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _showManualInput = !_showManualInput,
                          ),
                          icon: Icon(
                            _showManualInput
                                ? Icons.keyboard_hide_rounded
                                : Icons.lan_rounded,
                            size: 18,
                          ),
                          label: Text(_showManualInput ? '收起手动连接' : '手动输入 IP'),
                        ),
                        const Spacer(),
                        if (_service.isCasting && widget.onDisconnect != null)
                          TextButton.icon(
                            onPressed: () {
                              widget.onDisconnect!();
                              Navigator.of(context).pop(false);
                            },
                            icon: const Icon(
                              Icons.cast_rounded,
                              size: 18,
                              color: AppColors.error,
                            ),
                            label: const Text(
                              '退出投屏',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
