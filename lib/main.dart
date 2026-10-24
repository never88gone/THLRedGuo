import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/utils/screen/app_orientation.dart';
import 'package:THLRedLook/utils/theme/app_theme.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/utils/navigation/app_route_observer.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/pages/profiles/profiles_page.dart';
import 'package:THLRedLook/core/media/media_library.dart';
import 'package:THLRedLook/utils/smoke/package_smoke.dart';
import 'package:THLRedLook/core/lan/lan_controller.dart';
import 'package:THLRedLook/pages/player/player_page.dart';
import 'package:THLRedLook/core/player/pip_manager.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_assets.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/screen/screen_wake_controller.dart';
import 'package:THLRedLook/pages/privacy/privacy_lock_page.dart';
import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(CatPawJsRuntime.preloadDeviceSession());
  DiaryService.add(
    '[App] 应用启动，版本: $appVersion, 平台: ${Platform.operatingSystem}',
  );
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(AppTheme.systemBars(Brightness.dark));
  }
  if (Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    if (Platform.isMacOS) {
      const windowOptions = WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(960, 540),
        center: true,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }
  MediaKit.ensureInitialized();
  VideoEnhancementAssets.registerLicenses();
  if (Platform.isWindows && arguments.firstOrNull == '--package-smoke') {
    await runPackageSmoke(arguments);
    return;
  }
  final device = await AppDevice.detect();
  runApp(AppBootstrap(device: device));
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.device = const AppDevice()});
  final AppDevice device;
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  final repository = NativeRepository();
  final navigator = GlobalKey<NavigatorState>();
  LocalStore? store;
  PrivacyLockController? privacyController;
  Object? error;
  late AppDevice device = widget.device;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    privacyController?.dispose();
    LanController.current?.dispose();
    LanController.current = null;
    MediaLibrary.current?.dispose();
    MediaLibrary.current = null;
    store?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    privacyController?.handleLifecycleChange(state);
    if (state == AppLifecycleState.resumed) {
      if (store?.keepScreenOn == true) {
        ScreenWakeController.instance.handleAppResume(true);
      }
      if (Platform.isAndroid) {
        unawaited(_refreshDevice());
      }
    }
    if (!Platform.isIOS) return;
    final library = MediaLibrary.current;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (library != null) {
        library.suspended = true;
        unawaited(library.cancel());
      }
      unawaited(
        NativeRepository(
          background: true,
        ).controlDownloads('pauseAll').catchError((Object _) {}),
      );
    } else if (state == AppLifecycleState.resumed) {
      if (library != null) library.suspended = false;
    }
  }

  Future<void> _refreshDevice() async {
    final detected = await AppDevice.detect(fallback: device);
    if (!mounted ||
        (device.television == detected.television &&
            device.version == detected.version)) {
      return;
    }
    setState(() => device = detected);
  }

  Future<void> _initialize() async {
    setState(() {
      error = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await _refreshDevice();
      await repository.initialize();
      final jsSourceService = JsSourceService(repository);
      await jsSourceService.initialize();
      if (mounted) {
        final privacy = PrivacyLockController(preferences);
        final localStore = LocalStore(preferences);
        if (localStore.source.isNotEmpty) {
          await jsSourceService.switchSource(localStore.source);
        }
        setState(() {
          privacyController = privacy;
          store = localStore;
          repository.access = store;
          PipManager.instance.initialize(
            navigatorKey: navigator,
            repository: repository,
            store: store,
          );
          MediaLibrary.attach(repository, store!);
          LanController.current?.dispose();
          final link = LanController(
            repository,
            store!,
            kind: device.television
                ? 'tv'
                : Platform.isWindows
                ? 'computer'
                : 'phone',
          );
          LanController.current = link;
          link.openPlayback = (request) async {
            final epoch = request.profileEpoch;
            if (request.cancelled ||
                !mounted ||
                store!.locked ||
                !link.receiving ||
                store!.profileEpoch != epoch ||
                !store!.allowsSource(request.detail.drama.source)) {
              throw StateError('当前用户不能接收播放');
            }
            await link.playbackHost?.stop();
            if (request.cancelled ||
                !mounted ||
                store!.locked ||
                store!.profileEpoch != epoch ||
                !link.receiving) {
              throw StateError('播放接收已取消');
            }
            final navigation = navigator.currentState;
            if (navigation == null) throw StateError('接收设备界面尚未就绪');
            unawaited(
              navigation.pushAndRemoveUntil<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerScreen(
                    detail: request.detail,
                    initialIndex: request.index,
                    initialPosition: request.position,
                    repository: repository,
                    store: store!,
                    handoff: request,
                  ),
                ),
                (route) => route.isFirst,
              ),
            );
          };
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DuanjuApp(
    repository: repository,
    store: store,
    privacyController: privacyController,
    bootstrapError: error?.toString(),
    onRetry: _initialize,
    television: device.television,
    isPad: device.isPad,
    version: device.version,
    navigatorKey: navigator,
  );
}

class DuanjuApp extends StatelessWidget {
  const DuanjuApp({
    super.key,
    required this.repository,
    this.store,
    this.privacyController,
    this.bootstrapError,
    this.onRetry,
    this.television = false,
    this.isPad = false,
    this.version = appVersion,
    this.navigatorKey,
  });
  final AppRepository repository;
  final LocalStore? store;
  final PrivacyLockController? privacyController;
  final String? bootstrapError;
  final VoidCallback? onRetry;
  final bool television;
  final bool isPad;
  final String version;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([store, privacyController]),
    builder: (_, _) => _application(),
  );

  Widget _application() => MaterialApp(
    navigatorObservers: [appRouteObserver],
    navigatorKey: navigatorKey,
    title: appName,
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: AppTheme.mode(store?.themeMode ?? 'system'),
    builder: (context, child) {
      final mode = store?.displayMode ?? 'auto';
      final tv = mode == 'television' || mode == 'auto' && television;
      final theme = Theme.of(context);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(theme.brightness),
        child: ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: AppOrientationScope(
            television: tv,
            child: AppLayout(
              television: tv,
              pad: isPad,
              version: version,
              child: Theme(
                data: tv ? televisionTheme(theme) : theme,
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(
                      LogicalKeyboardKey.select,
                      includeRepeats: false,
                    ): ActivateIntent(),
                    SingleActivator(
                      LogicalKeyboardKey.gameButtonA,
                      includeRepeats: false,
                    ): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
                  },
                  child: Stack(
                    children: [
                      FocusTraversalGroup(child: child!),
                      if (privacyController?.isLocked == true)
                        Positioned.fill(
                          child: PrivacyLockPage(
                            controller: privacyController!,
                          ),
                        ),
                      if (privacyController?.isBlurred == true &&
                          privacyController?.isLocked != true)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ClipRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 25,
                                  sigmaY: 25,
                                ),
                                child: Container(
                                  color: AppColors.playerGestureHudBackground,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    home: store != null
        ? store!.locked
              ? ProfilesScreen(store: store!, locked: true)
              : HomeScreen(
                  key: ValueKey(
                    'profile-${store!.profile.id}-${store!.profileEpoch}',
                  ),
                  repository: repository,
                  store: store!,
                )
        : Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_fill_rounded,
                      color: AppColors.hongguoRed,
                      size: 72,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      bootstrapError ?? '正在打开$appName',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    if (bootstrapError == null)
                      const CircularProgressIndicator()
                    else
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('重新打开'),
                      ),
                  ],
                ),
              ),
            ),
          ),
  );
}
