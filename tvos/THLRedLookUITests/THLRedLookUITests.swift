import XCTest

final class THLRedLookUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func captureScreen(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // 保存到 /tmp 供测试脚本提取
        let dest = URL(fileURLWithPath: "/tmp/tvos_screenshot_\(name).png")
        try? screenshot.pngRepresentation.write(to: dest)
    }

    func test01_CatalogAndTabs() throws {
        // 1. 验证首页大屏呈现
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5.0), "顶部 TabBar 应当正常渲染")
        sleep(2)
        captureScreen(named: "01_catalog_home")

        // 2. 遥控器向下聚焦到海报卡片
        XCUIRemote.shared.press(.down)
        sleep(1)
        captureScreen(named: "02_card_focused")
    }

    func test02_DetailAndPlayback() throws {
        // 1. 进入第一部剧详情
        XCUIRemote.shared.press(.down)
        sleep(1)
        XCUIRemote.shared.press(.select)
        sleep(2)
        captureScreen(named: "03_drama_detail")

        // 2. 点击“立即播放 / 继续播放”
        XCUIRemote.shared.press(.select)
        sleep(3)
        captureScreen(named: "04_player_playing")

        // 3. 点击呼出控制条
        XCUIRemote.shared.press(.select)
        sleep(1)
        captureScreen(named: "05_player_controls")

        // 4. 返回详情页
        XCUIRemote.shared.press(.menu)
        sleep(1)
        // 再次返回首页
        XCUIRemote.shared.press(.menu)
        sleep(1)
    }

    func test03_RecommendationsAndRankings() throws {
        // 切换到“推荐”Tab
        let recTab = app.tabBars.buttons["推荐"]
        if recTab.exists {
            recTab.tap()
        } else {
            XCUIRemote.shared.press(.up)
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.select)
        }
        sleep(2)
        captureScreen(named: "06_recommendations")

        // 切换到“榜单”Tab
        let rankTab = app.tabBars.buttons["榜单"]
        if rankTab.exists {
            rankTab.tap()
        } else {
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.select)
        }
        sleep(2)
        captureScreen(named: "07_rankings")
    }

    func test04_SearchFlow() throws {
        // 切换到“搜索”Tab
        let searchTab = app.tabBars.buttons["搜索"]
        if searchTab.exists {
            searchTab.tap()
        }
        sleep(2)
        captureScreen(named: "08_search_page")
    }

    func test05_SavedLibraryAndDownloads() throws {
        // 切换到“追剧与历史”Tab
        let libTab = app.tabBars.buttons["追剧与历史"]
        if libTab.exists {
            libTab.tap()
        }
        sleep(2)
        captureScreen(named: "09_saved_library")

        // 切换到“下载”Tab
        let dlTab = app.tabBars.buttons["下载"]
        if dlTab.exists {
            dlTab.tap()
        }
        sleep(2)
        captureScreen(named: "10_downloads")
    }

    func test06_LanAndSettings() throws {
        // 切换到“互联”Tab
        let lanTab = app.tabBars.buttons["互联"]
        if lanTab.exists {
            lanTab.tap()
        }
        sleep(2)
        captureScreen(named: "11_lan_sync")

        // 切换到“设置”Tab
        let settingsTab = app.tabBars.buttons["设置"]
        if settingsTab.exists {
            settingsTab.tap()
        }
        sleep(2)
        captureScreen(named: "12_settings")
    }

    func test07_PlayerControlsFocusAndExit() throws {
        app.terminate()
        app.launchArguments = ["--uitesting", "-testPage", "controls"]
        app.launch()
        sleep(3)
        captureScreen(named: "13_player_initial_play_focused")

        // 1. 向上按键：验证焦点从播放按钮切换到顶部（弹幕/返回）
        XCUIRemote.shared.press(.up)
        sleep(1)
        captureScreen(named: "14_player_top_focused")

        // 2. 向下按键：验证焦点从顶部回到中间播放按钮
        XCUIRemote.shared.press(.down)
        sleep(1)
        captureScreen(named: "15_player_back_to_center")

        // 3. 再次向下按键：验证焦点从播放按钮切换到底部（选集列表）
        XCUIRemote.shared.press(.down)
        sleep(1)
        captureScreen(named: "16_player_bottom_focused")

        // 4. 向上按键：验证焦点从底部回到中间播放按钮
        XCUIRemote.shared.press(.up)
        sleep(1)
        captureScreen(named: "17_player_center_recovered")

        // 5. 向左按键：验证快退 10s 获得焦点
        XCUIRemote.shared.press(.left)
        sleep(1)
        captureScreen(named: "18_player_seek_backward_focused")

        // 6. 向右按键两下：切到播放，再切到快进 10s 获得焦点
        XCUIRemote.shared.press(.right)
        sleep(1)
        XCUIRemote.shared.press(.right)
        sleep(1)
        captureScreen(named: "19_player_seek_forward_focused")

        // 7. 点击 Menu 键：验证控制器浮层隐藏
        XCUIRemote.shared.press(.menu)
        sleep(1)
        captureScreen(named: "20_player_overlay_hidden")

        // 8. 再次点击 Menu 键：验证播放器页面完全退出，回到主页面
        XCUIRemote.shared.press(.menu)
        sleep(2)
        captureScreen(named: "21_player_exited_to_main")
    }
}
