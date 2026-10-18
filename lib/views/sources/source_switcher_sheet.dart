import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/sources/source_gate_dialog.dart';
import 'package:THLRedLook/utils/privacy/privacy_vault_controller.dart';
import 'package:THLRedLook/views/privacy/private_source_manage_dialog.dart';
import 'package:THLRedLook/views/privacy/vault_password_dialog.dart';
import 'package:THLRedLook/views/privacy/vault_password_setup_dialog.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';
import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/pages/settings/js_sources_page.dart';

/// 弹出数据源切换底部面板，支持用户直观浏览所有已解锁站源并一键切换。
Future<SourceSite?> showSourceSwitcherSheet(
  BuildContext context, {
  required LocalStore store,
  AppRepository? repository,
  SourceSite? currentSource,
  ValueChanged<SourceSite>? onSelect,
}) =>
    showModalBottomSheet<SourceSite>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _SourceSwitcherContent(
        store: store,
        repository: repository,
        currentSource: currentSource ?? SourceSite.byId(store.source),
        onSelect: onSelect,
      ),
    );

class _SourceSwitcherContent extends StatelessWidget {
  const _SourceSwitcherContent({
    required this.store,
    this.repository,
    required this.currentSource,
    this.onSelect,
  });

  final LocalStore store;
  final AppRepository? repository;
  final SourceSite currentSource;
  final ValueChanged<SourceSite>? onSelect;

  IconData _iconForSource(String id) {
    switch (id) {
      case 'hongguo':
        return Icons.play_circle_filled_rounded;
      default:
        return Icons.video_library_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final sources = store.sources;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '切换数据源',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '当前共有 ${sources.length} 个可用数据源，轻触切换，长按可删除',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '导入数据源插件',
                    icon: const Icon(Icons.extension_rounded),
                    onPressed: () {
                      Navigator.pop(context);
                  final repo = repository ?? NativeRepository();
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => JsSourcesPage(
                        repository: repo,
                        store: store,
                      ),
                    ),
                  );
                    },
                  ),
                  IconButton(
                    tooltip: '隐私数据源设置',
                    icon: const Icon(Icons.shield_outlined),
                    onPressed: () {
                      final vaultController =
                          PrivacyVaultController(store.preferences);
                      PrivateSourceManageDialog.show(
                        context,
                        store: store,
                        vaultController: vaultController,
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '站源密码与管理',
                    icon: const Icon(Icons.lock_outline_rounded),
                    onPressed: () {
                      Navigator.pop(context);
                      showSourceGateDialog(context, store);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sources.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final site = sources[index];
                    final selected = site.id == currentSource.id;
                    final isPrivate = store.isPrivateSource(site.id);
                    return Card(
                      elevation: 0,
                      color: selected
                          ? AppColors.accentSubtle12
                          : (isDark ? AppColors.darkCard : AppColors.greyLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: selected
                              ? AppColors.hongguoRed
                              : AppColors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: selected
                              ? AppColors.hongguoRed
                              : AppColors.darkSurfaceHighest,
                          foregroundColor: selected
                              ? AppColors.white
                              : AppColors.hongguoRed,
                          child: Icon(_iconForSource(site.id), size: 22),
                        ),
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                site.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                                  color: selected ? AppColors.hongguoRed : null,
                                ),
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
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_rounded,
                                      size: 11,
                                      color: AppColors.hongguoRed,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      '隐私',
                                      style: TextStyle(
                                        color: AppColors.hongguoRed,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          site.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.hongguoRed,
                              )
                            : const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.grey,
                              ),
                        onTap: () async {
                          if (selected) {
                            Navigator.pop(context, site);
                            return;
                          }
                          if (isPrivate) {
                            final vaultController =
                                PrivacyVaultController(store.preferences);
                            if (!vaultController.hasPassword) {
                              final setupSuccess =
                                  await VaultPasswordSetupDialog.show(
                                context,
                                controller: vaultController,
                              );
                              if (!setupSuccess || !context.mounted) return;
                            } else {
                              final verified =
                                  await VaultPasswordDialog.show(
                                context,
                                controller: vaultController,
                                title: '切换至隐私数据源',
                                hint: '请输入隐私密码进行切换',
                              );
                              if (!verified || !context.mounted) return;
                            }
                          }
                          if (!context.mounted) return;
                          Navigator.pop(context, site);
                          if (onSelect != null) {
                            onSelect!(site);
                          }
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isPrivate
                                    ? '已验证并切换至隐私数据源：${site.name}'
                                    : '已切换至数据源：${site.name}',
                              ),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        onLongPress: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: AppColors.hongguoRed),
                                  SizedBox(width: 8),
                                  Text('删除数据源'),
                                ],
                              ),
                              content: Text('确定要删除数据源「${site.name}」(${site.id}) 吗？\n删除后本地脚本将被移除。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.hongguoRed),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('确认删除'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true && context.mounted) {
                            final service = JsSourceService.current;
                            if (service != null) {
                              final ok = await service.removeSource(site.id);
                              if (ok && context.mounted) {
                                if (store.source == site.id) {
                                  final nextSource = service.activeSourceId.isNotEmpty
                                      ? service.activeSourceId
                                      : (store.sources.isNotEmpty ? store.sources.first.id : 'hongguo');
                                  try {
                                    await store.setSource(nextSource);
                                  } catch (_) {}
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('已成功删除数据源：${site.name}'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: () async {
                  final service = JsSourceService.current;
                  if (service != null) {
                    final count = await importPresetSources(service);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已导入 $count 个预置数据源插件'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.flash_on_rounded, size: 18),
                label: const Text('一键导入预置数据源'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  final repo = repository ?? NativeRepository();
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => JsSourcesPage(
                        repository: repo,
                        store: store,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text('导入外部插件 / 管理 JS 数据源'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
