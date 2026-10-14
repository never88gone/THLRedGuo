import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/app_theme.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/models/privacy/privacy_settings.dart';
import 'package:THLRedLook/pages/privacy/privacy_lock_page.dart';
import 'package:THLRedLook/pages/privacy/privacy_settings_page.dart';
import 'package:THLRedLook/source_switcher_sheet.dart';
import 'package:THLRedLook/utils/privacy/gesture_hasher.dart';
import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/privacy/privacy_vault_controller.dart';
import 'package:THLRedLook/views/privacy/pattern_lock_view.dart';
import 'package:THLRedLook/views/privacy/private_source_manage_dialog.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('隐私模式核心逻辑测试', () {
    test('GestureHasher 哈希与恒时比对一致性', () {
      final salt = GestureHasher.generateSalt();
      expect(salt.length, 32);

      const pattern1 = [0, 1, 2, 5, 8];
      const pattern2 = [0, 1, 2, 5, 8];
      const pattern3 = [0, 1, 2, 4, 8];

      final hash1 = GestureHasher.hashPattern(pattern1, salt);
      final hash2 = GestureHasher.hashPattern(pattern2, salt);
      final hash3 = GestureHasher.hashPattern(pattern3, salt);

      expect(hash1, equals(hash2));
      expect(hash1, isNot(equals(hash3)));
      expect(GestureHasher.constantTimeCompare(hash1, hash2), isTrue);
      expect(GestureHasher.constantTimeCompare(hash1, hash3), isFalse);
    });

    test('PrivacySettings 序列化与数据完整性', () {
      const settings = PrivacySettings(
        enabled: true,
        hasGesture: true,
        autoLockSeconds: 30,
      );
      final json = settings.toJson();
      final restored = PrivacySettings.fromJson(json);

      expect(restored.enabled, isTrue);
      expect(restored.hasGesture, isTrue);
      expect(restored.autoLockSeconds, 30);
    });

    test('PrivacyLockController 保存与验证手势', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);

      expect(controller.enabled, isFalse);
      expect(controller.hasGesture, isFalse);
      expect(controller.isLocked, isFalse);

      expect(() => controller.saveGesture([0, 1, 2]), throwsArgumentError);

      await controller.saveGesture([0, 1, 2, 5]);
      expect(controller.hasGesture, isTrue);
      expect(controller.enabled, isTrue);

      controller.lock();
      expect(controller.isLocked, isTrue);

      final wrong = controller.verifyGesture([0, 1, 2, 4]);
      expect(wrong, isFalse);
      expect(controller.isLocked, isTrue);

      final right = controller.verifyGesture([0, 1, 2, 5]);
      expect(right, isTrue);
      expect(controller.isLocked, isFalse);
    });

    test('PrivacyLockController 后台生命周期超时锁定与控制栏防误触', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);
      await controller.saveGesture([0, 1, 2, 5]);
      // 默认 autoLockSeconds 应为 60
      expect(controller.autoLockSeconds, 60);

      controller.unlock();
      expect(controller.isLocked, isFalse);

      // 下拉控制栏或通知栏（触发 inactive），不应锁定
      controller.handleLifecycleChange(AppLifecycleState.inactive);
      expect(controller.isLocked, isFalse);
      controller.handleLifecycleChange(AppLifecycleState.resumed);
      expect(controller.isLocked, isFalse);

      // 设置为立即锁定 (0秒) 后，切到 paused 应触发锁定
      await controller.setAutoLockSeconds(0);
      controller.unlock();
      expect(controller.isLocked, isFalse);

      controller.handleLifecycleChange(AppLifecycleState.paused);
      expect(controller.isLocked, isTrue);

      controller.verifyGesture([0, 1, 2, 5]);
      expect(controller.isLocked, isFalse);
    });
  });

  group('隐私模式 UI 与手势交互测试', () {
    testWidgets('PatternLockView 连线与完成回调触发', (tester) async {
      List<int>? completedPattern;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: PatternLockView(
                dimension: 300,
                onComplete: (pattern) => completedPattern = pattern,
              ),
            ),
          ),
        ),
      );

      final centerFinder = find.byType(PatternLockView);
      final center = tester.getCenter(centerFinder);

      final cell = 300.0 / 3;
      final start = Offset(center.dx - cell, center.dy - cell);
      final mid = Offset(center.dx, center.dy - cell);
      final end = Offset(center.dx + cell, center.dy - cell);

      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(mid);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(end);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(completedPattern, isNotNull);
      expect(completedPattern, containsAllInOrder([0, 1, 2]));
    });

    testWidgets('PrivacyLockPage 解锁验证与错误提示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);
      await controller.saveGesture([0, 1, 2, 5]);
      controller.lock();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PrivacyLockPage(controller: controller),
        ),
      );

      expect(find.text('真果·鉴 隐私保护'), findsOneWidget);
      expect(find.text('请绘制手势图案解锁'), findsOneWidget);

      final centerFinder = find.byType(PatternLockView);
      final center = tester.getCenter(centerFinder);
      final cell = 300.0 / 3;

      final gesture = await tester.startGesture(Offset(center.dx - cell, center.dy - cell));
      await gesture.moveTo(Offset(center.dx, center.dy - cell));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('至少连接 4 个点，请重新绘制'), findsOneWidget);
    });

    testWidgets('PrivacySettingsPage 页面渲染与超时选择', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);
      await controller.saveGesture([0, 1, 2, 5]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PrivacySettingsPage(controller: controller),
        ),
      );

      expect(find.text('隐私与安全设置'), findsOneWidget);
      expect(find.text('启用手势隐私锁'), findsOneWidget);
      expect(find.text('修改手势密码'), findsOneWidget);
      expect(find.text('后台自动锁定'), findsOneWidget);
      expect(find.text('隐私库访问密码'), findsOneWidget);

      await tester.tap(find.text('后台自动锁定'));
      await tester.pumpAndSettle();

      expect(find.text('后台自动锁定触发时机'), findsOneWidget);
      expect(find.text('离开后台 30 秒后'), findsOneWidget);

      await tester.tap(find.text('离开后台 30 秒后'));
      await tester.pumpAndSettle();

      expect(controller.autoLockSeconds, 30);
    });

    test('PrivacyVaultController 密码设置与短剧加锁/移出/隐藏验证', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final vault = PrivacyVaultController(prefs);

      expect(vault.hasPassword, isFalse);
      expect(vault.isUnlocked, isFalse);
      expect(vault.vaultCount, 0);

      // 密码长度校验
      expect(() => vault.setPassword('123'), throwsArgumentError);

      // 设置有效密码
      await vault.setPassword('8888');
      expect(vault.hasPassword, isTrue);
      expect(vault.isUnlocked, isTrue);

      // 锁定状态
      vault.lock();
      expect(vault.isUnlocked, isFalse);

      // 密码验证
      expect(vault.verifyPassword('0000'), isFalse);
      expect(vault.isUnlocked, isFalse);
      expect(vault.verifyPassword('8888'), isTrue);
      expect(vault.isUnlocked, isTrue);

      // 短剧加入隐私库
      const testDrama = Drama(
        id: 'vault_test_drama_01',
        source: 'hongguo',
        title: '绝密娇妻不可欺',
        cover: 'http://dummy.image/1.jpg',
        category: '都市',
      );
      expect(vault.isInVault(testDrama.id), isFalse);

      await vault.addToVault(testDrama);
      expect(vault.isInVault(testDrama.id), isTrue);
      expect(vault.vaultCount, 1);
      expect(vault.vaultDramas.first.title, '绝密娇妻不可欺');

      // 短剧移出隐私库
      await vault.removeFromVault(testDrama.id);
      expect(vault.isInVault(testDrama.id), isFalse);
      expect(vault.vaultCount, 0);

      // 再次加入并清空
      await vault.addToVault(testDrama);
      expect(vault.vaultCount, 1);
      await vault.clearVault();
      expect(vault.vaultCount, 0);
    });

    test('后台切换触发 isBlurred 虚化状态与切回前台恢复', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);

      // 未启用隐私锁时，不触发虚化
      controller.handleLifecycleChange(AppLifecycleState.inactive);
      expect(controller.isBlurred, isFalse);

      // 设置手势并启用
      await controller.saveGesture([0, 1, 2, 4]);
      expect(controller.enabled, isTrue);
      expect(controller.hasGesture, isTrue);
      expect(controller.isBlurred, isFalse);

      // App 切入 inactive (多任务预览准备)
      controller.handleLifecycleChange(AppLifecycleState.inactive);
      expect(controller.isInBackground, isTrue);
      expect(controller.isBlurred, isTrue);

      // App 切入 paused (完全退入后台)
      controller.handleLifecycleChange(AppLifecycleState.paused);
      expect(controller.isInBackground, isTrue);
      expect(controller.isBlurred, isTrue);

      // App 切回前台 resumed
      controller.handleLifecycleChange(AppLifecycleState.resumed);
      expect(controller.isInBackground, isFalse);
      expect(controller.isBlurred, isFalse);
    });

    test('隐私数据源配置与最近观看隐匿过滤', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = testStore(prefs);
      addTearDown(store.dispose);
      addTearDown(SourceSite.resetRuntimeActivation);
      await store.activateZhenguojian();

      // 默认无隐私数据源
      expect(store.privateSources.isEmpty, isTrue);
      expect(store.isPrivateSource('hanxiaoquan'), isFalse);

      // 添加两条观看记录：hongguo 和 hanxiaoquan
      const dramaHongguo = Drama(
        id: 'hongguo:drama_hg_1',
        source: 'hongguo',
        title: '红果普通短剧',
        cover: 'http://dummy.image/hg.jpg',
        category: '都市',
      );
      const dramaHanxiaoquan = Drama(
        id: 'hanxiaoquan:drama_hxq_1',
        source: 'hanxiaoquan',
        title: '韩圈私密短剧',
        cover: 'http://dummy.image/hxq.jpg',
        category: '爱情',
      );

      await store.saveWatch(
        WatchEntry(
          drama: dramaHongguo,
          episode: 1,
          position: 300.0,
          duration: 600.0,
          updatedAt: DateTime.now(),
        ),
      );
      await store.saveWatch(
        WatchEntry(
          drama: dramaHanxiaoquan,
          episode: 2,
          position: 180.0,
          duration: 480.0,
          updatedAt: DateTime.now(),
        ),
      );

      // 未设置隐私模式时，history 和 watched 均能查到两条记录
      expect(store.history.length, 2);
      expect(store.watched('hongguo:drama_hg_1'), isNotNull);
      expect(store.watched('hanxiaoquan:drama_hxq_1'), isNotNull);

      // 将 hanxiaoquan 设置为隐私数据源
      await store.setSourcePrivate('hanxiaoquan', true);
      expect(store.isPrivateSource('hanxiaoquan'), isTrue);
      expect(store.privateSources.contains('hanxiaoquan'), isTrue);

      // 验证：最近观看中已彻底过滤隐匿 hanxiaoquan 的数据
      final historyAfterPrivate = store.history;
      expect(historyAfterPrivate.length, 1);
      expect(historyAfterPrivate.first.drama.id, 'hongguo:drama_hg_1');
      expect(store.watched('hanxiaoquan:drama_hxq_1'), isNull);
      expect(store.watched('hongguo:drama_hg_1'), isNotNull);

      // 取消隐私数据源模式
      await store.setSourcePrivate('hanxiaoquan', false);
      expect(store.isPrivateSource('hanxiaoquan'), isFalse);
      expect(store.history.length, 2);
      expect(store.watched('hanxiaoquan:drama_hxq_1'), isNotNull);
    });

    testWidgets('切换隐私数据源需要输入密码验证', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = testStore(prefs);
      addTearDown(store.dispose);
      addTearDown(SourceSite.resetRuntimeActivation);
      await store.activateZhenguojian();

      // 设置隐私库密码
      final vault = PrivacyVaultController(prefs);
      await vault.setPassword('9999');

      // 将韩小圈设为隐私数据源
      await store.setSourcePrivate('hanxiaoquan', true);

      SourceSite? selectedSource;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showSourceSwitcherSheet(
                    context,
                    store: store,
                    currentSource: SourceSite.hongguo,
                    onSelect: (site) {
                      selectedSource = site;
                    },
                  );
                },
                child: const Text('选择数据源'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('选择数据源'));
      await tester.pumpAndSettle();

      // 韩小圈显示并且有隐私标记
      expect(find.text('韩小圈'), findsOneWidget);
      expect(find.text('隐私'), findsWidgets);

      // 点击切换至韩小圈，由于是隐私数据源，应弹出密码验证弹窗
      await tester.tap(find.text('韩小圈'));
      await tester.pumpAndSettle();

      expect(find.text('切换至隐私数据源'), findsOneWidget);
      expect(find.text('确认进入'), findsOneWidget);

      // 输入错误密码
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('确认进入'));
      await tester.pumpAndSettle();

      expect(find.text('密码错误，请重试'), findsOneWidget);
      expect(selectedSource, isNull);

      // 输入正确密码并确认
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('确认进入'));
      await tester.pumpAndSettle();

      // 验证成功，切换成功
      expect(selectedSource?.id, 'hanxiaoquan');
      expect(find.text('已验证并切换至隐私数据源：韩小圈'), findsOneWidget);
    });

    testWidgets('PrivateSourceManageDialog 验证密码后管理并切换站源隐私状态', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = testStore(prefs);
      addTearDown(store.dispose);
      addTearDown(SourceSite.resetRuntimeActivation);
      await store.activateZhenguojian();

      final vault = PrivacyVaultController(prefs);
      await vault.setPassword('8888');

      expect(store.isPrivateSource('hongguo'), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PrivateSourceManageDialog.show(
                    context,
                    store: store,
                    vaultController: vault,
                  );
                },
                child: const Text('管理隐私数据源'),
              ),
            ),
          ),
        ),
      );

      // 打开弹窗：先弹出密码验证
      await tester.tap(find.text('管理隐私数据源'));
      await tester.pumpAndSettle();

      expect(find.text('隐私数据源验证'), findsOneWidget);

      // 输入正确密码验证
      await tester.enterText(find.byType(TextField), '8888');
      await tester.tap(find.text('确认进入'));
      await tester.pumpAndSettle();

      // 进入隐私数据源管理弹窗
      expect(find.text('隐私数据源管理'), findsOneWidget);
      expect(find.text('红果'), findsOneWidget);

      // 找到第一个 Switch（红果对应的 Switch）并点击切换
      final switchFinder = find.byType(Switch).first;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // 验证已将红果设为隐私数据源
      expect(store.isPrivateSource('hongguo'), isTrue);

      // 点击完成关闭弹窗
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('隐私数据源管理'), findsNothing);
    });
  });
}


