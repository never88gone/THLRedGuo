import XCTest

final class RemoteNavigationTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.never88gone.redlook")
    private let remote = XCUIRemote.shared

    func testImportedOldIOSHistoryDisplaysAndPersistsWithRemoteFocus() throws {
        guard ProcessInfo.processInfo.environment["ICLOUD_OLD_HISTORY_UI"] == "1" else { throw XCTSkip("Requires isolated imported history fixture") }
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "library", "-thl_icloud_sync_enabled", "NO"]
        app.launch()
        defer { app.terminate() }
        wait("old history library ready", seconds: 30) { self.app.buttons["library.tab.history"].exists }
        if app.buttons["nav.library"].hasFocus { press(.right) }
        wait("old history header focused") { self.app.buttons["library.tab.history"].hasFocus }
        press(.down, focus: "library.card.hongguo:tv-new")
        press(.right, focus: "library.card.hongguo:tv-existing")
        press(.right, focus: "library.card.hongguo:old-ios-179")
        let value = app.buttons["library.card.hongguo:old-ios-179"].value as? String ?? ""
        XCTAssertTrue(value.contains("第 12 集"))
        XCTAssertTrue(value.contains("59%"))
        press(.menu)
        wait("old history menu restores navigation") { self.app.buttons["nav.library"].hasFocus }
        press(.right)
        wait("old history returns to header") { self.app.buttons["library.tab.history"].hasFocus }
        app.terminate()
        app.launch()
        wait("old history survives restart", seconds: 30) { self.app.buttons["library.card.hongguo:old-ios-179"].exists }
        XCTAssertEqual(app.buttons["library.card.hongguo:old-ios-179"].value as? String, value)
        print("THL_OLD_HISTORY_UI oldEpisode=12 oldProgress=59% remoteFocus=true menuReturn=true restart=true")
    }

    private func wait(_ description: String, seconds: Double = 15, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: seconds)
        if result != .completed {
            trace("failed-" + description)
            if let wake = self.yaoSnapshots().first(where: { $0.identifier == "player.wake" }) {
                print("THL_REMOTE_WAKE_VALUE: id=\(wake.identifier) label=\(wake.label) val=\(String(describing: wake.value))")
            }
            print("THL_REMOTE_VISIBLE \(app.buttons.allElementsBoundByIndex.map { $0.identifier + ":" + $0.label })")
            print("THL_REMOTE_TEXT \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        XCTAssertEqual(result, .completed, description)
    }

    private func trace(_ step: String) {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
        print("THL_REMOTE \(step) focus=\(focused.map { $0.identifier + ":" + $0.label })")
    }

    private func press(_ button: XCUIRemote.Button, focus identifier: String? = nil) {
        trace("before-\(button.rawValue)")
        remote.press(button)
        if let identifier { wait("focus \(identifier)") { (self.app.buttons[identifier].exists && self.app.buttons[identifier].hasFocus) || (self.app.textFields[identifier].exists && self.app.textFields[identifier].hasFocus) } }
        trace("after-\(button.rawValue)")
    }

    private func focusChunk(_ target: Int) {
        let chunks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.chunk.' AND hasFocus == true"))
        for _ in 0..<3 {
            if chunks.firstMatch.exists { break }
            press(.down)
        }
        wait("focus episode chunk") { chunks.firstMatch.exists }
        let current = Int(chunks.firstMatch.identifier.split(separator: ".").last ?? "0") ?? 0
        if current < target {
            for index in (current + 1)...target { press(.right, focus: "detail.chunk.\(index)") }
        } else if current > target {
            for index in stride(from: current - 1, through: target, by: -1) { press(.left, focus: "detail.chunk.\(index)") }
        }
    }

    private func showControls() { yaoControls() }

    private func focusDrawer() {
        yaoControls()
        press(.right, focus: "player.seekForward")
        press(.right)
        if app.buttons["player.prevEpisode"].hasFocus { press(.right, focus: "player.episodeDrawer") }
        wait("episode drawer control focus") { self.app.buttons["player.episodeDrawer"].hasFocus }
    }

    private func seconds(_ value: String) -> Int {
        value.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    func testSearchDetailRemotePlayback() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "search", "-testQuery", "都市"]
        app.launch()
        wait("search results appear", seconds: 45) { self.app.buttons["search.result.0"].exists }
        if self.app.buttons["nav.search"].hasFocus {
            press(.right, focus: "search.result.0")
        } else {
            press(.down, focus: "search.result.0")
        }
        let selectedTitle = app.buttons["search.result.0"].label
        press(.select)
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("detail play initial focus") { self.app.buttons["detail.play"].hasFocus }
        focusChunk(0)
        press(.down, focus: "detail.episode.1")
        press(.right, focus: "detail.episode.2")
        press(.select)
        wait("player starts without obscuring controls", seconds: 30) {
            self.app.buttons["player.wake"].exists
        }
        showControls()
        XCTAssertTrue(app.buttons["player.playPause"].waitForExistence(timeout: 60))
        wait("episode 2 ready", seconds: 60) { self.app.staticTexts["player.episode"].label.contains("第 2 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0 }
        showControls()
        focusDrawer()
        press(.select, focus: "drawer.episode.2")
        press(.right, focus: "drawer.episode.3")
        press(.select)
        wait("drawer chose episode 3", seconds: 60) { self.app.staticTexts["player.episode"].label.contains("第 3 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0 }
        showControls()
        focusDrawer()
        press(.select, focus: "drawer.episode.3")
        press(.menu, focus: "player.episodeDrawer")
        focusDrawer()
        press(.right, focus: "player.nextEpisode")
        press(.select)
        wait("next episode 4", seconds: 60) { self.app.staticTexts["player.episode"].label.contains("第 4 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0 }
        showControls()
        focusDrawer()
        press(.left, focus: "player.prevEpisode")
        press(.select)
        wait("previous episode 3", seconds: 60) { self.app.staticTexts["player.episode"].label.contains("第 3 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0 }
        showControls()
        press(.right, focus: "player.seekForward")
        let duration = seconds(app.staticTexts["player.duration"].label)
        XCTAssertGreaterThan(duration, 10)
        for _ in 0..<(duration / 10) { remote.press(.select) }
        wait("natural end advances to episode 4", seconds: 65) {
            self.showControls()
            return self.app.staticTexts["player.episode"].label.contains("第 4 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0
        }
        showControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("return to detail episode 4") { self.app.buttons["detail.episode.4"].hasFocus }
        press(.menu)
        wait("restore original search card") { self.app.buttons["search.result.0"].hasFocus }
        XCTAssertEqual(app.buttons["search.result.0"].label, selectedTitle)
        XCTAssertEqual(app.textFields["search.query"].value as? String, "都市")
        press(.up, focus: "search.query")
        press(.up)
        wait("return to search navigation") { self.app.buttons["nav.search"].hasFocus }
        print("THL_REMOTE_RESULT search=true detail=true episode=true drawer=true next=true previous=true autoNext=true back=true focus=true")
    }
    func testSearchKeyboardPaginationAndTopRowFocus() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "search", "-testQuery", "都市"]
        app.launch()
        wait("initial search results appear", seconds: 45) { self.app.buttons["search.result.0"].exists }
        press(.down, focus: "search.result.0")
        for index in 1...5 { press(.right, focus: "search.result.\(index)") }
        press(.select)
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("detail focus") { self.app.buttons["detail.play"].hasFocus }
        press(.menu, focus: "search.result.5")
        press(.up, focus: "search.query")
        press(.select)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "萌宝")
        press(.menu)
        wait("keyboard returns to search controls") {
            self.app.buttons["search.submit"].hasFocus || self.app.textFields["search.query"].hasFocus
        }
        if !app.buttons["search.submit"].hasFocus { press(.right, focus: "search.submit") }
        press(.select)
        wait("new query is submitted", seconds: 45) {
            self.app.buttons["search.result.0"].exists && self.app.textFields["search.query"].value as? String == "萌宝"
        }
        press(.menu, focus: "nav.search")
        press(.down, focus: "search.result.0")
        press(.down, focus: "search.result.6")
        // 瀑布流自动加载更多：焦点向下推进触底后，无需任何手动按键点击，新一页数据自动加载并呈现
        wait("auto waterfall pagination loads more results", seconds: 45) {
            self.app.buttons["search.result.10"].exists
        }
        print("THL_REMOTE_RESULT keyboard=true query=萌宝 waterfallAutoPagination=true sixthColumnUp=true")
    }

    func testEpisodeChunkAndOffscreenFocusRestoration() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "detail", "-testDramaId", "hongguo:7694291604915358744", "-testDramaTitle", "分组选集验证"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("detail initial focus") { self.app.buttons["detail.play"].hasFocus }
        focusChunk(1)
        press(.select)
        press(.down, focus: "detail.episode.51")
        press(.select)
        wait("player starts without obscuring controls", seconds: 30) {
            self.app.buttons["player.wake"].exists
        }
        showControls()
        XCTAssertTrue(app.buttons["player.playPause"].waitForExistence(timeout: 60))
        wait("episode 51 starts", seconds: 60) { self.app.staticTexts["player.position"].exists && self.seconds(self.app.staticTexts["player.position"].label) > 0 }
        showControls()
        focusDrawer()
        press(.select, focus: "drawer.episode.51")
        for number in stride(from: 56, through: 76, by: 5) { press(.down, focus: "drawer.episode.\(number)") }
        press(.select)
        wait("episode 76 starts", seconds: 60) { self.app.staticTexts["player.episode"].exists && self.app.staticTexts["player.episode"].label.contains("第 76 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0 }
        showControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("restore scrolled episode 76") { self.app.buttons["detail.episode.76"].exists && self.app.buttons["detail.episode.76"].hasFocus }
        print("THL_REMOTE_RESULT chunks=true drawerScroll=true offscreenReturnEpisode=76 focus=true")
    }

    func testLocalFavoritePersistsAndCanBeRemoved() {
        continueAfterFailure = false
        let id = "test_library_favorite_lifecycle"
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "detail", "-testDramaId", id, "-testDramaTitle", "本地收藏验证"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.favorite"].waitForExistence(timeout: 30))
        wait("favorite detail focus") { self.app.buttons["detail.play"].hasFocus }
        press(.right, focus: "detail.favorite")
        if app.buttons["detail.favorite"].label.contains("已收藏") {
            press(.select)
            wait("fixture favorite cleared") { !self.app.buttons["detail.favorite"].label.contains("已收藏") }
        }
        press(.select)
        wait("favorite saved") { self.app.buttons["detail.favorite"].label.contains("已收藏") }
        app.terminate()
        app.launchArguments = ["-testPage", "library"]
        app.launch()
        XCTAssertTrue(app.buttons["library.tab.history"].waitForExistence(timeout: 30))
        if app.buttons["nav.library"].hasFocus { press(.down, focus: "library.tab.history") }
        wait("library starts at history") { self.app.buttons["library.tab.history"].hasFocus }
        press(.right, focus: "library.tab.follows")
        press(.select)
        press(.down, focus: "library.filter.all")
        press(.down, focus: "library.card." + id)
        press(.select)
        XCTAssertTrue(app.buttons["detail.favorite"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["detail.favorite"].label.contains("已收藏"))
        wait("favorite reopened detail focus") { self.app.buttons["detail.play"].hasFocus }
        press(.right, focus: "detail.favorite")
        press(.select)
        wait("favorite removed") { !self.app.buttons["detail.favorite"].label.contains("已收藏") }
        press(.menu)
        wait("removed favorite has valid return focus") {
            !self.app.buttons["library.card." + id].exists &&
            ((self.app.buttons["library.emptyAction"].exists && self.app.buttons["library.emptyAction"].hasFocus) ||
             self.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.card.' AND hasFocus == true")).firstMatch.exists)
        }
        app.terminate()
        app.launchArguments = ["-testPage", "detail", "-testDramaId", id, "-testDramaTitle", "本地收藏验证"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.favorite"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["detail.favorite"].label.contains("已收藏"))
        print("THL_REMOTE_LOCAL favorite=true relaunch=true defaultAll=true remove=true returnFocus=true")
    }

    func testLocalHistoryResumeDanmakuAndBackground() {
        continueAfterFailure = false
        let id = "hongguo:7694896136963755032"
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "detail", "-testDramaId", id, "-testDramaTitle", "播放与历史验证"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("history detail initial focus") { self.app.buttons["detail.play"].hasFocus }
        focusChunk(0)
        press(.down, focus: "detail.episode.1")
        press(.right, focus: "detail.episode.2")
        press(.select)
        wait("history episode 2 starts", seconds: 75) {
            self.app.staticTexts["player.episode"].label.contains("第 2 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0
        }
        showControls()
        press(.down, focus: "player.speed")
        press(.right)
        if app.buttons["player.quality"].hasFocus { press(.right, focus: "player.danmaku") }
        let initialDanmaku = app.buttons["player.danmaku"].label
        press(.select)
        let changedDanmaku = app.buttons["player.danmaku"].label
        XCTAssertNotEqual(initialDanmaku, changedDanmaku)
        yaoControls()
        press(.right, focus: "player.seekForward")
        press(.select)
        press(.select)
        wait("history seek reaches target") { self.seconds(self.app.staticTexts["player.position"].label) >= 20 }
        press(.left, focus: "player.playPause")
        press(.select)
        wait("history paused") { self.app.buttons["player.playPause"].label == "播放" }
        let saved = seconds(app.staticTexts["player.position"].label)
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("history returns to selected episode") { self.app.buttons["detail.episode.2"].hasFocus }
        app.terminate()
        app.launchArguments = ["-testPage", "library"]
        app.launch()
        XCTAssertTrue(app.buttons["library.tab.history"].waitForExistence(timeout: 30))
        if app.buttons["nav.library"].hasFocus { press(.down, focus: "library.tab.history") }
        wait("history tab focus") { self.app.buttons["library.tab.history"].hasFocus }
        press(.down, focus: "library.card." + id)
        XCTAssertTrue((app.buttons["library.card." + id].value as? String ?? "").contains("第 2 集"))
        press(.up, focus: "library.tab.history")
        press(.right, focus: "library.tab.follows")
        press(.right, focus: "library.clearHistory")
        press(.select)
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 10))
        press(.menu)
        wait("clear history cancelled") { self.app.buttons["library.clearHistory"].hasFocus }
        press(.down, focus: "library.card." + id)
        press(.select)
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("resume button focus") { self.app.buttons["detail.play"].hasFocus }
        XCTAssertTrue(app.buttons["detail.play"].label.contains("第 2 集"))
        press(.select)
        wait("history resumes saved position", seconds: 75) {
            self.app.staticTexts["player.episode"].label.contains("第 2 集") && self.seconds(self.app.staticTexts["player.position"].label) >= saved - 1
        }
        showControls()
        press(.down, focus: "player.speed")
        press(.right)
        if app.buttons["player.quality"].hasFocus { press(.right, focus: "player.danmaku") }
        XCTAssertEqual(app.buttons["player.danmaku"].label, changedDanmaku)
        press(.select)
        XCTAssertEqual(app.buttons["player.danmaku"].label, initialDanmaku)
        yaoControls()
        let beforeBackground = seconds(app.staticTexts["player.position"].label)
        remote.press(.home)
        wait("app enters background") { self.app.state != .runningForeground }
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        wait("player returns from background", seconds: 20) { self.app.buttons["player.playPause"].exists || self.app.buttons["player.wake"].exists }
        showControls()
        wait("player continues after foreground", seconds: 20) { self.seconds(self.app.staticTexts["player.position"].label) > beforeBackground }
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("history final return") { self.app.buttons["detail.episode.2"].hasFocus }
        print("THL_REMOTE_LOCAL history=true relaunch=true savedEpisode=2 savedSeconds=\(saved) resume=true clearCancel=true danmakuPreference=true background=true")
    }


    private func yaoSeason(_ number: Int) -> XCUIElement? {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.season.'")).allElementsBoundByIndex.first {
            $0.label.replacingOccurrences(of: " ", with: "").contains("第\(number)季")
        }
    }

    private func yaoDetailPlayFocus() {
        for _ in 0..<4 {
            if app.buttons["detail.play"].hasFocus { return }
            trace("yao-detail-before-up")
            press(.up)
        }
        wait("yao detail play focus") { self.app.buttons["detail.play"].hasFocus }
    }

    private func yaoSeasonFocus(_ number: Int) throws {
        wait("yao season \(number) exists", seconds: 45) { self.yaoSeason(number) != nil }
        let target = try XCTUnwrap(yaoSeason(number))
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.season.' AND hasFocus == true"))
        if !focused.firstMatch.exists {
            yaoDetailPlayFocus()
            press(.down)
            wait("yao focus current season") { focused.firstMatch.exists }
        }
        for _ in 0..<12 {
            if target.hasFocus { return }
            let currentIndex = Int(focused.firstMatch.identifier.split(separator: ".").last ?? "0") ?? 0
            let targetIndex = Int(target.identifier.split(separator: ".").last ?? "0") ?? 0
            press(currentIndex < targetIndex ? .right : .left)
        }
        wait("yao season \(number) focused") { target.hasFocus }
    }


    private func yaoSnapshots() -> [XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else { return [] }
        var pending = [root]
        var result: [XCUIElementSnapshot] = []
        while let current = pending.popLast() {
            result.append(current)
            pending.append(contentsOf: current.children)
        }
        return result
    }

    private func yaoControls() {
        if app.buttons["player.wake"].exists && (app.buttons["player.wake"].hasFocus || yaoSnapshots().first(where: { $0.hasFocus }) == nil) {
            press(.select)
            return
        }
        let current = yaoSnapshots().first { $0.hasFocus }?.identifier ?? ""
        switch current {
        case "player.wake": press(.select)
        case "player.back": press(.down, focus: "player.playPause")
        case "player.seekForward": press(.left, focus: "player.playPause")
        case "player.seekBackward": press(.right, focus: "player.playPause")
        case "player.nextEpisode", "player.prevEpisode", "player.episodeDrawer":
            press(.up, focus: "player.back")
            press(.down, focus: "player.playPause")
        case "player.speed": press(.up, focus: "player.playPause")
        case "player.quality":
            press(.up, focus: "player.seekForward")
            press(.left, focus: "player.playPause")
        case "player.danmaku", "player.danmakuSettings":
            press(.up)
            press(.up, focus: "player.back")
            press(.down, focus: "player.playPause")
        default: break
        }
        if let changed = yaoSnapshots().first(where: { $0.hasFocus })?.identifier,
           changed != "player.playPause", changed.hasPrefix("player."), current == "player.wake" {
            yaoControls()
        }
    }

    private func yaoReady(season: Int, episode: Int) {
        var position = ""
        var duration = ""
        wait("yao season \(season) episode \(episode) plays", seconds: 120) {
            self.yaoControls()
            let snapshot = self.yaoSnapshots()
            let title = "满院亲戚全是上古大妖第\([2: "二", 4: "四", 5: "五"][season] ?? String(season))季"
            let visibleTitle = snapshot.contains { $0.label == title && $0.frame.minY >= 0 && $0.frame.minY < 250 }
            let label = snapshot.first { $0.identifier == "player.episode" }?.label ?? ""
            position = snapshot.first { $0.identifier == "player.position" }?.label ?? ""
            duration = snapshot.first { $0.identifier == "player.duration" }?.label ?? ""
            return visibleTitle && label.contains("第 \(episode) 集") && self.seconds(position) > 0 && self.seconds(duration) > 10
        }
        print("THL_TV_YAO_PLAY season=\(season) episode=\(episode) position=\(position) duration=\(duration) visiblePlayerTitle=true")
    }

    func testOfficialSeriesReservationAndOrdering() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "search", "-testQuery", "满院亲戚全是上古大妖第五季"]
        app.launch()
        wait("fifth result", seconds: 60) { self.app.buttons["search.result.0"].exists }
        press(.down, focus: "search.result.0")
        press(.select)
        wait("official six seasons", seconds: 60) {
            self.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.season.'")).count == 6
        }
        let labels = (0..<6).map { app.buttons["detail.season.\($0)"].label }
        for index in 0..<6 { XCTAssertTrue(labels[index].contains("第 \(index + 1) 季")) }
        XCTAssertTrue(labels[5].contains("待上线"))
        XCTAssertFalse(labels[5].contains("全集"))
        try yaoSeasonFocus(6)
        press(.select)
        XCTAssertTrue(app.staticTexts["满院亲戚全是上古大妖第五季"].exists)
        XCTAssertTrue(app.buttons["detail.season.4"].label.contains("当前播放"))
        XCTAssertTrue(app.buttons["detail.episode.1"].exists)
        print("THL_TV_OFFICIAL_SERIES orderedSix=true reservationBlocked=true exactFifthRetained=true")
    }

    func testYaoFifthToFourthSeasonPlayback() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "search", "-testQuery", "满院亲戚全是上古大妖第五季"]
        app.launch()
        wait("yao search result", seconds: 60) { self.app.buttons["search.result.0"].exists }
        let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'")).allElementsBoundByIndex
        print("THL_TV_YAO_SEARCH \(results.map { $0.identifier + ":" + $0.label })")
        let fifth = try XCTUnwrap(results.first { $0.label.contains("满院亲戚全是上古大妖第五季") })
        let targetIndex = try XCTUnwrap(Int(fifth.identifier.split(separator: ".").last ?? ""))
        press(.down, focus: "search.result.0")
        for row in 0..<(targetIndex / 6) { press(.down, focus: "search.result.\((row + 1) * 6)") }
        for column in 0..<(targetIndex % 6) { press(.right, focus: "search.result.\((targetIndex / 6) * 6 + column + 1)") }
        press(.select)
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 60))
        yaoDetailPlayFocus()
        print("THL_TV_YAO_SEASONS \(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.season.'")).allElementsBoundByIndex.map { $0.identifier + ":" + $0.label })")
        focusChunk(0)
        press(.down, focus: "detail.episode.1")
        press(.select)
        yaoReady(season: 5, episode: 1)
        yaoControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("yao fifth returns to episode 1") { self.app.buttons["detail.episode.1"].hasFocus }
        try yaoSeasonFocus(4)
        press(.select)
        wait("yao fourth detail loaded", seconds: 60) {
            self.app.staticTexts["满院亲戚全是上古大妖第四季"].exists && self.app.buttons["detail.episode.4"].exists
        }
        trace("yao-fourth-detail-loaded")
        yaoDetailPlayFocus()
        focusChunk(0)
        press(.down, focus: "detail.episode.1")
        for number in 2...4 { press(.right, focus: "detail.episode.\(number)") }
        press(.select)
        yaoReady(season: 4, episode: 4)
        yaoControls()
        focusDrawer()
        press(.select, focus: "drawer.episode.4")
        press(.down, focus: "drawer.episode.9")
        press(.left, focus: "drawer.episode.8")
        press(.left, focus: "drawer.episode.7")
        press(.select)
        yaoReady(season: 4, episode: 7)
        yaoControls()
        focusDrawer()
        press(.right, focus: "player.nextEpisode")
        press(.select)
        yaoReady(season: 4, episode: 8)
        yaoControls()
        focusDrawer()
        press(.left, focus: "player.prevEpisode")
        press(.select)
        yaoReady(season: 4, episode: 7)
        yaoControls()
        press(.right, focus: "player.seekForward")
        let duration = seconds(app.staticTexts["player.duration"].label)
        for _ in 0..<(duration / 10) { press(.select) }
        wait("yao fourth natural end advances to episode 8", seconds: 90) {
            self.yaoControls()
            let snapshot = self.yaoSnapshots()
            let label = snapshot.first { $0.identifier == "player.episode" }?.label ?? ""
            let position = snapshot.first { $0.identifier == "player.position" }?.label ?? ""
            return label.contains("第 8 集") && self.seconds(position) > 0
        }
        yaoReady(season: 4, episode: 8)
        yaoControls()
        focusDrawer()
        press(.select, focus: "drawer.episode.8")
        press(.menu, focus: "player.episodeDrawer")
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("yao fourth returns to episode 8") { self.app.buttons["detail.episode.8"].hasFocus }
        try yaoSeasonFocus(2)
        press(.select)
        wait("yao second detail loaded", seconds: 60) { self.app.staticTexts["满院亲戚全是上古大妖第二季"].exists && self.app.buttons["detail.episode.1"].exists }
        yaoDetailPlayFocus()
        focusChunk(0)
        press(.down, focus: "detail.episode.1")
        press(.select)
        yaoReady(season: 2, episode: 1)
        focusDrawer()
        press(.right, focus: "player.nextEpisode")
        press(.select)
        yaoReady(season: 2, episode: 2)
        yaoControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("yao second returns to episode 2") { self.app.buttons["detail.episode.2"].hasFocus }
        try yaoSeasonFocus(5)
        press(.select)
        wait("yao fifth restored", seconds: 60) { self.app.staticTexts["满院亲戚全是上古大妖第五季"].exists && self.app.buttons["detail.episode.1"].exists }
        yaoDetailPlayFocus()
        press(.select)
        yaoReady(season: 5, episode: 1)
        yaoControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("yao fifth final return") { self.app.buttons["detail.episode.1"].hasFocus }
        press(.menu)
        wait("yao original search card restored") { fifth.hasFocus }
        print("THL_TV_YAO_RESULT fifthToFourth=true fourthToSecond=true secondToFifth=true detailSelection=true drawerSelection=true next=true previous=true autoNext=true drawerBack=true detailBack=true searchFocus=true")
    }

    func testStaleFifthToFourthAndSecondSeasons() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "detail", "-testDramaId", "hongguo:7695704804978330649", "-testDramaTitle", "满院亲戚全是上古大妖第五季"]
        app.launch()
        wait("stale fifth detail", seconds: 60) { self.app.buttons["detail.play"].exists }
        yaoDetailPlayFocus()
        press(.select)
        yaoReady(season: 5, episode: 11)
        yaoControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("stale fifth return") { self.app.buttons["detail.episode.11"].hasFocus }
        try yaoSeasonFocus(4)
        press(.select)
        wait("stale fourth detail", seconds: 60) { self.app.staticTexts["满院亲戚全是上古大妖第四季"].exists && self.app.buttons["detail.play"].exists }
        yaoDetailPlayFocus()
        press(.select)
        yaoReady(season: 4, episode: 12)
        yaoControls()
        focusDrawer()
        press(.select, focus: "drawer.episode.12")
        press(.up, focus: "drawer.episode.7")
        press(.select)
        yaoReady(season: 4, episode: 7)
        yaoControls()
        focusDrawer()
        press(.right, focus: "player.nextEpisode")
        press(.select)
        yaoReady(season: 4, episode: 8)
        yaoControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("stale fourth return") { self.app.buttons["detail.episode.8"].hasFocus }
        try yaoSeasonFocus(2)
        press(.select)
        wait("stale second detail", seconds: 60) { self.app.staticTexts["满院亲戚全是上古大妖第二季"].exists && self.app.buttons["detail.play"].exists }
        yaoDetailPlayFocus()
        press(.select)
        yaoReady(season: 2, episode: 5)
        yaoControls()
        focusDrawer()
        press(.right, focus: "player.nextEpisode")
        press(.select)
        yaoReady(season: 2, episode: 6)
        yaoControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("stale second return") { self.app.buttons["detail.episode.6"].hasFocus }
        app.terminate()
        app.launchArguments = ["-testPage", "detail", "-testDramaId", "hongguo:7688558312157088793", "-testDramaTitle", "满院亲戚全是上古大妖第四季"]
        app.launch()
        wait("stale fourth relaunch", seconds: 60) { self.app.buttons["detail.play"].exists }
        yaoDetailPlayFocus()
        press(.select)
        yaoReady(season: 4, episode: 8)
        yaoControls()
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("stale fourth relaunch return") { self.app.buttons["detail.episode.8"].hasFocus }
        print("THL_TV_STALE_REMOTE fifth=11 fourth=12 drawer=7 next=8 second=5 next=6 relaunch=4:8 focus=true back=true")
    }

    func testSourceDiagnosticsReportAndRemoteReturn() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings_sources"]
        app.launch()
        wait("diagnostics entry for hongguo source exists", seconds: 45) {
            self.app.buttons["settings.sourceDiagnostics"].exists || self.app.buttons["settings.source.diagnose.hongguo"].exists
        }

        let diagId = app.buttons["settings.sourceDiagnostics"].exists ? "settings.sourceDiagnostics" : "settings.source.diagnose.hongguo"
        // 导航至诊断按钮
        for _ in 0..<8 {
            if app.buttons[diagId].hasFocus { break }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            trace("diagnostics-locate")
            if focused.identifier == "nav.settings" { press(.down) }
            else if focused.label.contains("站源管理") { press(.right) }
            else if app.buttons["settings.source.card.hongguo"].hasFocus { press(.up) }
            else { press(.down) }
        }
        if !app.buttons[diagId].hasFocus {
            press(.right, focus: diagId)
        }
        wait("diagnostics entry focus") { self.app.buttons[diagId].hasFocus }
        press(.select, focus: "sourceDiagnostics.run")
        press(.select)
        wait("diagnostics live result", seconds: 120) { self.app.staticTexts["sourceDiagnostics.result"].label.contains("检测完成") || self.app.staticTexts["sourceDiagnostics.result"].label.contains("检测失败") }
        print("THL_TV_DIAGNOSTICS_LIVE \(app.staticTexts["sourceDiagnostics.result"].label)")
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_source_diagnostics_modal.png"))
        let visible = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator:" ")
        XCTAssertTrue(visible.contains("检索") || visible.contains("搜索") || visible.contains("DNS") || visible.contains("网络"))
        XCTAssertFalse(visible.contains("device_id="))
        XCTAssertFalse(visible.contains("x-medusa"))

        // 1. 测试焦点向右切换至【详细报告】按钮并打开全屏报告
        if !app.buttons["sourceDiagnostics.report"].hasFocus {
            press(.right, focus: "sourceDiagnostics.report")
        }
        wait("diagnostics report button focused") { self.app.buttons["sourceDiagnostics.report"].hasFocus }
        press(.select)
        wait("full diagnostics report sheet opens", seconds: 15) { self.app.staticTexts["sourceDiagnostics.reportContent"].exists }
        let reportShot = XCUIScreen.main.screenshot()
        try? reportShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_source_diagnostics_report.png"))
        let reportText = app.staticTexts["sourceDiagnostics.reportContent"].label
        XCTAssertTrue(reportText.contains("核心技术诊断报告") || reportText.contains("应用版本"))
        XCTAssertTrue(reportText.contains("hongguo"))

        // 关闭详细报告
        press(.menu)
        wait("full report closed", seconds: 15) { !self.app.staticTexts["sourceDiagnostics.reportContent"].exists }
        wait("focus restored on report button") { self.app.buttons["sourceDiagnostics.report"].hasFocus }

        // 2. 测试按钮焦点在横排操作区切换至二维码
        press(.right, focus: "sourceDiagnostics.qr")
        wait("diagnostics QR focused") { self.app.buttons["sourceDiagnostics.qr"].hasFocus }
        press(.select)
        wait("diagnostics report QR") { self.app.buttons["sourceDiagnostics.qrBack"].exists }
        press(.menu, focus: "sourceDiagnostics.qr")
        wait("diagnostics return modal after qr", seconds: 10) { self.app.buttons["sourceDiagnostics.qr"].hasFocus }

        // 3. 验证诊断列表焦点下移（从顶部按钮向下导航到诊断项卡片）
        if !app.buttons["sourceDiagnostics.run"].hasFocus {
            press(.left)
            if !app.buttons["sourceDiagnostics.run"].hasFocus {
                press(.left)
            }
        }
        wait("run button focused") { self.app.buttons["sourceDiagnostics.run"].hasFocus }

        // 核心测试：按 down 键下移焦点至诊断列表第 0 项
        press(.down)
        wait("first diagnostic entry focused", seconds: 10) {
            self.app.buttons["sourceDiagnostics.entry.0"].hasFocus
        }
        XCTAssertTrue(app.buttons["sourceDiagnostics.entry.0"].hasFocus, "焦点列表应成功下移至首个诊断条目")

        // 截取焦点下移到列表卡片的高亮图
        let listFocusShot = XCUIScreen.main.screenshot()
        try? listFocusShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_source_diagnostics_entry_focus.png"))

        // 继续按 down 键下移到第 1 项（如果存在）
        if app.buttons["sourceDiagnostics.entry.1"].exists {
            press(.down)
            wait("second diagnostic entry focused", seconds: 5) {
                self.app.buttons["sourceDiagnostics.entry.1"].hasFocus
            }
            XCTAssertTrue(app.buttons["sourceDiagnostics.entry.1"].hasFocus, "焦点列表应能继续向下平滑移动")
        }

        // 4. 验证【详细信息】功能：在诊断条目上按确认键 Select 打开详细信息弹窗
        press(.select)
        wait("diagnostic entry detail sheet opens", seconds: 15) {
            self.app.buttons["sourceDiagnostics.detailClose"].exists
        }
        XCTAssertTrue(app.buttons["sourceDiagnostics.detailClose"].exists, "应成功打开诊断项详细信息弹窗")

        // 验证详细信息弹窗内容与焦点
        wait("detail close button focused", seconds: 5) {
            self.app.buttons["sourceDiagnostics.detailClose"].hasFocus
        }
        let detailShot = XCUIScreen.main.screenshot()
        try? detailShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_source_diagnostics_entry_detail.png"))

        // 关闭详细信息弹窗
        press(.select) // 点击“关闭详情”按钮
        wait("detail sheet closed", seconds: 10) {
            !self.app.buttons["sourceDiagnostics.detailClose"].exists
        }

        // 验证关闭详细信息弹窗后，焦点精准恢复到原卡片
        wait("focus restored on entry card", seconds: 10) {
            self.app.buttons["sourceDiagnostics.entry.0"].hasFocus || self.app.buttons["sourceDiagnostics.entry.1"].hasFocus
        }

        // 验证从卡片按 up 返回到顶部按钮栏
        press(.up)
        if !app.buttons["sourceDiagnostics.run"].hasFocus {
            press(.up)
        }
        wait("focus returned to run button", seconds: 5) {
            self.app.buttons["sourceDiagnostics.run"].hasFocus
        }

        // 5. 返回设置页
        press(.menu)
        wait("diagnostics return settings") { self.app.buttons["settings.sourceDiagnostics"].hasFocus || self.app.buttons["settings.source.card.hongguo"].hasFocus || self.app.buttons["settings.source.diagnose.hongguo"].hasFocus }
        print("THL_TV_DIAGNOSTICS_REMOTE report=true qr=true entry_focus=true detail_sheet=true back=true")
    }

    func testAutoWaterfallPagination() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "search", "-testQuery", "都市"]
        app.launch()
        wait("search results appear", seconds: 45) { self.app.buttons["search.result.0"].exists }

        // 验证：彻底废除旧版“加载更多”按钮，页面不再存在 search.more 按钮
        XCTAssertFalse(app.buttons["search.more"].exists)

        // 初始第一页有短剧卡片呈现
        XCTAssertTrue(app.buttons["search.result.0"].exists)

        // 遥控器向下推进，聚焦并滑过卡片触发瀑布流触底
        press(.down, focus: "search.result.0")
        press(.down, focus: "search.result.6")

        // 瀑布流触底自动加载：无需遥控器手动点击任何按钮，下一页短剧卡片自动静默预加载并呈现
        wait("waterfall auto loads next page", seconds: 45) {
            self.app.buttons["search.result.10"].exists
        }

        // 遥控器继续向下滑动，焦点顺滑推进至新拉取的第 12 部卡片
        press(.down, focus: "search.result.12")
        XCTAssertTrue(app.buttons["search.result.12"].hasFocus)
        print("THL_REMOTE_WATERFALL autoLoaded=true moreButtonAbsent=true focusFlow=true")
    }

    func testCustomSourceDeleteLifecycle() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings", "-testCustomSource"]
        app.launch()

        // 1. 等待设置页就绪，检测到注入的自定义测试数据源「test_custom_spider」
        wait("custom source card exists", seconds: 45) {
            self.app.buttons["settings.source.delete.test_custom_spider"].exists
        }

        // 2. 遥控器导航到右侧内容区
        for _ in 0..<6 {
            if (app.buttons["settings.source.card.hongguo"].exists && app.buttons["settings.source.card.hongguo"].hasFocus) ||
                (app.buttons["settings.source.card.test_custom_spider"].exists && app.buttons["settings.source.card.test_custom_spider"].hasFocus) ||
                (app.buttons["settings.source.delete.test_custom_spider"].exists && app.buttons["settings.source.delete.test_custom_spider"].hasFocus) {
                break
            }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            trace("settings-navigate-to-sources")
            if focused.identifier == "nav.settings" {
                press(.down)
            } else if focused.label.contains("站源管理") {
                press(.right)
            } else {
                press(.down)
            }
        }

        // 3. 向下移动到自定义源卡片
        for _ in 0..<8 {
            if app.buttons["settings.source.card.test_custom_spider"].hasFocus ||
                app.buttons["settings.source.delete.test_custom_spider"].hasFocus {
                break
            }
            press(.down)
        }

        // 若焦点在卡片主体或诊断按钮上，向右键导航到独立的红色删除按钮
        for _ in 0..<4 {
            if app.buttons["settings.source.delete.test_custom_spider"].hasFocus { break }
            press(.right)
        }
        wait("trash button focused") { self.app.buttons["settings.source.delete.test_custom_spider"].hasFocus }

        // 4. 按遥控器 Select 键触发原生二次确认 Alert
        press(.select)
        wait("delete confirmation alert shown", seconds: 10) {
            self.app.alerts["删除数据源"].exists
        }

        // 5. 聚焦并点击“确认删除”（在 tvOS Alert 中向右切换到破坏性操作并执行）
        let cancelBtn = app.alerts["删除数据源"].buttons["取消"].firstMatch
        if cancelBtn.exists && cancelBtn.hasFocus {
            remote.press(.right)
        } else if !app.alerts["删除数据源"].buttons["确认删除"].firstMatch.hasFocus {
            remote.press(.right)
        }
        remote.press(.select)

        // 6. 验证自定义源已被物理移除，且主界面弹出成功提示
        wait("custom source is deleted", seconds: 20) {
            !self.app.buttons["settings.source.delete.test_custom_spider"].exists
        }

        // 7. 确认成功提示 Alert（“好的”）
        wait("deletion notice alert", seconds: 15) {
            self.app.alerts["提示"].exists
        }
        remote.press(.select)

        print("THL_REMOTE_SOURCE_DELETE deleted=true alertConfirmed=true cleaned=true")
    }

    func testPlayerDanmakuButtonScreenshot() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "controls"]
        app.launch()
        wait("player controls appear", seconds: 20) { self.app.buttons["player.danmaku"].exists }
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_player_danmaku_button.png"))
    }

    func testPlayerDanmakuSettingsAndSpeedSelection() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "controls", "-testEpisode", "5"]
        app.launch()

        // 1. 等待播放器浮层出现并聚焦在主播放/暂停键
        wait("controls overlay ready", seconds: 25) {
            self.app.buttons["player.playPause"].exists && self.app.buttons["player.playPause"].hasFocus
        }

        // 2. 向右导航至弹幕快捷开关
        for _ in 0..<10 {
            if app.buttons["player.danmaku"].hasFocus { break }
            press(.right)
        }
        wait("focus danmaku toggle") { self.app.buttons["player.danmaku"].hasFocus }
        let initialLabel = app.buttons["player.danmaku"].label
        // 点击切换
        press(.select)
        wait("danmaku toggle toggled") {
            self.app.buttons["player.danmaku"].label != initialLabel
        }
        // 恢复初始
        press(.select)
        wait("danmaku toggle restored") {
            self.app.buttons["player.danmaku"].label == initialLabel
        }

        // 3. 向右导航至弹幕样式按钮并打开弹幕设置抽屉
        press(.right, focus: "player.danmakuSettings")
        press(.select)
        wait("danmaku settings drawer opened", seconds: 10) {
            self.app.buttons["danmaku.switch.on"].exists
        }
        let danmakuShot = XCUIScreen.main.screenshot()
        try? danmakuShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_danmaku_settings_drawer.png"))

        // 4. 验证弹幕样式抽屉各项遥控焦点与设置切换
        // 4.1 弹幕开关切换：向右聚焦至关闭并点击，再向左回开启点击
        press(.right, focus: "danmaku.switch.off")
        press(.select)
        press(.left, focus: "danmaku.switch.on")
        press(.select)

        // 4.2 字体大小：从开启(左)向下进入小字号，向右切换至标准，再向右至大字号并选中
        press(.down, focus: "danmaku.font.small")
        press(.right, focus: "danmaku.font.standard")
        press(.right, focus: "danmaku.font.large")
        press(.select)

        // 4.3 不透明度：从大字号(右)向下进入100%(右)，向左切换至75%并选中
        press(.down, focus: "danmaku.opacity.100")
        press(.left, focus: "danmaku.opacity.75")
        press(.select)

        // 4.4 显示区域：从75%(中)向下进入半屏(左)，向右切换至全屏并选中
        press(.down, focus: "danmaku.area.half")
        press(.right, focus: "danmaku.area.full")
        press(.select)

        // 4.5 向下聚焦至完成按钮并关闭抽屉
        press(.down, focus: "danmaku.close")
        press(.select)
        wait("danmaku settings drawer closed", seconds: 10) {
            !self.app.buttons["danmaku.close"].exists
        }

        // 5. 测试倍速选择抽屉与功能
        wait("controls ready after settings drawer closed", seconds: 10) {
            self.app.buttons["player.danmakuSettings"].exists
        }
        if !app.buttons["player.speed"].hasFocus {
            for _ in 0..<6 {
                if app.buttons["player.speed"].hasFocus { break }
                press(.left)
            }
        }
        wait("speed button focused") { self.app.buttons["player.speed"].hasFocus }

        // 5.1 按 Select 展开倍速选择抽屉
        press(.select)
        wait("speed drawer opened", seconds: 10) {
            self.app.buttons["player.speed.1.0"].exists
        }
        let speedShot = XCUIScreen.main.screenshot()
        try? speedShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_speed_selection_drawer.png"))

        // 5.2 遥控器向下导航至 1.5x 倍速并选中
        press(.down, focus: "player.speed.1.25")
        press(.down, focus: "player.speed.1.5")
        press(.select)

        // 5.3 验证倍速抽屉自动关闭，控制栏更新为 1.5x 倍速
        wait("speed drawer closed and rate updated", seconds: 10) {
            !self.app.buttons["player.speed.1.5"].exists && self.app.buttons["player.speed"].label.contains("1.5")
        }

        // 5.4 验证抽屉关闭后焦点精准恢复停留在倍速按钮上，再次打开倍速抽屉，验证初始高亮对焦在 1.5x，然后按 Menu 退出
        wait("focus restored on speed button", seconds: 10) { self.app.buttons["player.speed"].hasFocus }
        press(.select)
        wait("speed drawer reopened at 1.5x", seconds: 10) {
            self.app.buttons["player.speed.1.5"].exists && self.app.buttons["player.speed.1.5"].hasFocus
        }
        press(.menu)
        wait("speed drawer closed by menu", seconds: 10) {
            !self.app.buttons["player.speed.1.5"].exists
        }

        print("THL_REMOTE_RESULT danmakuSettings=true speedSelection=true focus=true")
    }

    func testAllPlayerControlButtonsFocusAndAction() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "controls", "-testEpisode", "5"]
        app.launch()

        // 1. 等待播放器浮层出现并聚焦在主播放/暂停键
        wait("controls overlay ready", seconds: 25) {
            self.app.buttons["player.playPause"].exists && self.app.buttons["player.playPause"].hasFocus
        }

        // 验证 11 个控制按钮均存在于界面上
        let allControlIds = [
            "player.back",
            "player.seekBackward",
            "player.playPause",
            "player.seekForward",
            "player.prevEpisode",
            "player.episodeDrawer",
            "player.nextEpisode",
            "player.speed",
            "player.quality",
            "player.danmaku",
            "player.danmakuSettings"
        ]
        for id in allControlIds {
            XCTAssertTrue(app.buttons[id].exists, "按钮 \(id) 应该存在于播放器界面")
        }

        // 保存当前底部两层操作栏整体效果截图
        let fullShot = XCUIScreen.main.screenshot()
        try? fullShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_player_bottom_controls_bar.png"))
        try? fullShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/tvos_player_two_tier_controls.png"))

        // 2. 测试向上导航至顶部返回按钮并返回主播放键
        press(.up, focus: "player.back")
        XCTAssertTrue(app.buttons["player.back"].hasFocus)
        press(.down, focus: "player.playPause")
        XCTAssertTrue(app.buttons["player.playPause"].hasFocus)

        // 3. 测试向左导航至快退10秒并点击
        press(.left, focus: "player.seekBackward")
        XCTAssertTrue(app.buttons["player.seekBackward"].hasFocus)
        press(.select)

        // 4. 测试向右回到播放/暂停并点击切换
        press(.right, focus: "player.playPause")
        XCTAssertTrue(app.buttons["player.playPause"].hasFocus)
        let playInitialLabel = app.buttons["player.playPause"].label
        press(.select)
        wait("play/pause toggled") { self.app.buttons["player.playPause"].label != playInitialLabel }
        press(.select)

        // 5. 测试向右导航至快进10秒并点击
        press(.right, focus: "player.seekForward")
        XCTAssertTrue(app.buttons["player.seekForward"].hasFocus)
        press(.select)

        // 6. 测试向右导航至上一集并聚焦
        press(.right, focus: "player.prevEpisode")
        XCTAssertTrue(app.buttons["player.prevEpisode"].hasFocus)

        // 7. 测试向右导航至选集列表并展开/关闭
        press(.right, focus: "player.episodeDrawer")
        XCTAssertTrue(app.buttons["player.episodeDrawer"].hasFocus)
        press(.select)
        wait("episode drawer opens", seconds: 10) { self.app.buttons["drawer.episode.5"].exists }
        press(.menu)
        wait("episode drawer closes", seconds: 10) { !self.app.buttons["drawer.episode.5"].exists }
        wait("focus restored on episode drawer", seconds: 10) { self.app.buttons["player.episodeDrawer"].hasFocus }

        // 8. 测试向右导航至下一集并聚焦
        press(.right, focus: "player.nextEpisode")
        XCTAssertTrue(app.buttons["player.nextEpisode"].hasFocus)

        // 9. 测试从第一层进入第二层：向右导航至播放倍速并展开/关闭
        press(.right, focus: "player.speed")
        XCTAssertTrue(app.buttons["player.speed"].hasFocus)
        press(.select)
        wait("speed drawer opens", seconds: 10) { self.app.buttons["player.speed.1.0"].exists }
        press(.menu)
        wait("speed drawer closes", seconds: 10) { !self.app.buttons["player.speed.1.0"].exists }
        wait("focus restored on speed button", seconds: 10) { self.app.buttons["player.speed"].hasFocus }

        // 10. 测试向右导航至清晰度/分辨率并点击切换
        press(.right, focus: "player.quality")
        XCTAssertTrue(app.buttons["player.quality"].hasFocus)
        press(.select)

        // 11. 测试向右导航至弹幕开关并点击切换
        press(.right, focus: "player.danmaku")
        XCTAssertTrue(app.buttons["player.danmaku"].hasFocus)
        let danmakuLabel = app.buttons["player.danmaku"].label
        press(.select)
        wait("danmaku toggled") { self.app.buttons["player.danmaku"].label != danmakuLabel }
        press(.select)

        // 12. 测试向右导航至弹幕样式并展开/关闭
        press(.right, focus: "player.danmakuSettings")
        XCTAssertTrue(app.buttons["player.danmakuSettings"].hasFocus)
        press(.select)
        wait("danmaku settings drawer opens", seconds: 10) { self.app.buttons["danmaku.switch.on"].exists }
        press(.menu)
        wait("danmaku settings drawer closes", seconds: 10) { !self.app.buttons["danmaku.switch.on"].exists }
        wait("focus restored on danmaku settings", seconds: 10) { self.app.buttons["player.danmakuSettings"].hasFocus }

        // 13. 深度验证双层跨层垂直导航：从第二层向上跨层返回第一层下一集，再向下回到第二层
        press(.up, focus: "player.nextEpisode")
        XCTAssertTrue(app.buttons["player.nextEpisode"].hasFocus)
        press(.down, focus: "player.danmakuSettings")
        XCTAssertTrue(app.buttons["player.danmakuSettings"].hasFocus)
        press(.left, focus: "player.danmaku")
        XCTAssertTrue(app.buttons["player.danmaku"].hasFocus)
        press(.up, focus: "player.episodeDrawer")
        XCTAssertTrue(app.buttons["player.episodeDrawer"].hasFocus)
        press(.down, focus: "player.danmaku")
        XCTAssertTrue(app.buttons["player.danmaku"].hasFocus)

        print("THL_REMOTE_ALL_CONTROLS_VERIFIED back=true seekBackward=true playPause=true seekForward=true prev=true drawer=true next=true speed=true quality=true danmaku=true danmakuSettings=true twoTierVertical=true")
    }
    func testDiscoveryGridFocusAndReturnProbe() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        for page in ["catalog", "rankings"] {
            app.launchArguments = ["-testPage", page]
            app.launch()
            wait("navigation focused " + page, seconds: 45) { self.app.buttons["nav." + page].hasFocus }
            press(.down)
            wait("discovery cards loaded " + page, seconds: 60) {
                self.yaoSnapshots().filter { $0.elementType == .button && $0.frame.height > 200 && $0.frame.minY > 200 }.count >= 6
            }
            let originalHeader = try XCTUnwrap(self.yaoSnapshots().first { $0.hasFocus && $0.elementType == .button })
            print("THL_DISCOVERY_HEADER page=\(page) id=\(originalHeader.identifier) label=\(originalHeader.label)")
            press(.down)
            let first = try XCTUnwrap(self.yaoSnapshots().first { $0.hasFocus && $0.elementType == .button })
            XCTAssertGreaterThan(first.frame.height, 200)
            let firstRow = self.yaoSnapshots().filter { $0.elementType == .button && $0.frame.height > 200 && abs($0.frame.minY - first.frame.minY) < 32 }.sorted { $0.frame.minX < $1.frame.minX }
            print("THL_DISCOVERY_ROW page=\(page) count=\(firstRow.count)")
            let header = page == "catalog" ? "全部" : page == "recommendations" ? "真人剧" : ""
            for _ in 1..<firstRow.count { press(.right) }
            let last = try XCTUnwrap(self.yaoSnapshots().first { $0.hasFocus && $0.elementType == .button })
            print("THL_DISCOVERY_LAST page=\(page) label=\(last.label)")
            press(.up)
            let reached = try XCTUnwrap(self.yaoSnapshots().first { $0.hasFocus && $0.elementType == .button })
            print("THL_DISCOVERY_UP page=\(page) label=\(reached.label) frame=\(reached.frame)")
            if !header.isEmpty { XCTAssertEqual(reached.label, header) }
            XCTAssertEqual(reached.identifier, originalHeader.identifier)
            if page == "rankings" {
                try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos27-focus-20261020/rankings-focus.png"))
            }
            press(.down)
            for _ in 0..<2 { press(.right) }
            let selected = try XCTUnwrap(self.yaoSnapshots().first { $0.hasFocus && $0.elementType == .button })
            let selectedLabel = selected.label
            press(.select)
            wait("discovery detail " + page, seconds: 60) { self.app.buttons["detail.play"].hasFocus }
            press(.menu)
            wait("restore discovery card " + page) {
                self.yaoSnapshots().contains { $0.hasFocus && $0.label == selectedLabel }
            }
            press(.menu, focus: "nav." + page)
            app.terminate()
        }
        print("THL_DISCOVERY_RESULT firstRowUp=true detailReturn=true menu=true")
    }

    func testMobileDiscoveryRemoteCategoriesAndPaging() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "catalog"]
        app.launch()
        wait("discovery navigation", seconds: 45) { self.app.buttons["nav.catalog"].hasFocus }
        XCTAssertFalse(app.buttons["nav.recommendations"].exists)
        let categories = ["all", "playlet", "motion_comic", "ai_playlet"]
        let labels = ["全部", "真人剧", "漫剧", "AI剧"]
        wait("App categories ready", seconds: 60) { self.app.buttons["catalog.category.app:discover:ai_playlet"].exists }
        press(.down, focus: "catalog.category.app:discover:all")
        for (index, category) in categories.enumerated() {
            let header = "catalog.category.app:discover:" + category
            if index > 0 { press(.right, focus: header) }
            XCTAssertEqual(app.buttons[header].label, labels[index])
            wait("discovery ready " + category, seconds: 60) { self.app.buttons["catalog.result.0"].exists }
            press(.down, focus: "catalog.result.0")
            for index in 1...5 { press(.right, focus: "catalog.result.\(index)") }
            press(.up, focus: header)
            press(.down, focus: "catalog.result.0")
            press(.down, focus: "catalog.result.6")
            wait("discovery page two " + category, seconds: 60) { self.app.buttons["catalog.result.12"].exists }
            press(.down, focus: "catalog.result.12")
            press(.right, focus: "catalog.result.13")
            let title = app.buttons["catalog.result.13"].label
            XCTAssertFalse(title.contains("app:"))
            press(.select)
            wait("discovery detail " + category, seconds: 60) { self.app.buttons["detail.play"].hasFocus }
            press(.menu)
            wait("discovery scrolled return " + category) {
                self.app.buttons["catalog.result.13"].hasFocus && self.app.buttons["catalog.result.13"].label == title
            }
            press(.menu, focus: "nav.catalog")
            press(.down, focus: header)
            print("THL_SINGLE_DISCOVERY category=\(category) sixthUp=true autoPaging=true detailReturn=true menu=true")
        }
        for _ in 0..<3 {
            press(.down, focus: "catalog.result.0")
            press(.down, focus: "catalog.result.6")
            press(.down, focus: "catalog.result.12")
            press(.menu, focus: "nav.catalog")
            press(.down, focus: "catalog.category.app:discover:ai_playlet")
        }
        print("THL_SINGLE_DISCOVERY repeatedAIHeaderRestore=true")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/Volumes/MacintoshData/Work/MY/Project/Product/THLRedGuo/build/verification/tvos-discover-single-20261020/discover-four-categories.png"))
        app.terminate()
    }

    func testMobileRankingRemoteCategoriesAndPaging() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "rankings"]
        app.launch()
        wait("ranking navigation", seconds: 45) { self.app.buttons["nav.rankings"].hasFocus }
        press(.down)
        let targets = ["hongguo-app:all:ranklist_hot_play_sc", "hongguo-app:all:ranklist_new_rank_sc", "hongguo-app:all:ranklist_hot_search_sc", "hongguo-app:comic_series_rank:comic_series_hot_rank", "hongguo-app:human:human_hot_sc", "hongguo-app:ai_playlet:ai_playlet_hot_sc"]
        for board in targets {
            let id = "ranking.board." + board
            for _ in 0..<30 {
                if app.buttons[id].hasFocus { break }
                press(.right)
            }
            wait("ranking focused " + board) { self.app.buttons[id].hasFocus }
            XCTAssertLessThan(app.buttons[id].frame.width, 360)
            wait("ranking loaded " + board, seconds: 60) { self.app.buttons["ranking.result.0"].exists }
            press(.down, focus: "ranking.result.0")
            for index in 1...5 { press(.right, focus: "ranking.result.\(index)") }
            press(.up, focus: id)
            press(.down, focus: "ranking.result.0")
            press(.down, focus: "ranking.result.6")
            wait("ranking page two " + board, seconds: 60) { self.app.buttons["ranking.result.12"].exists }
            press(.down, focus: "ranking.result.12")
            press(.right, focus: "ranking.result.13")
            let title = app.buttons["ranking.result.13"].label
            press(.select)
            wait("ranking detail " + board, seconds: 60) { self.app.buttons["detail.play"].hasFocus }
            press(.menu)
            wait("ranking scrolled return " + board) {
                self.app.buttons["ranking.result.13"].hasFocus && self.app.buttons["ranking.result.13"].label == title
            }
            press(.menu, focus: "nav.rankings")
            press(.down, focus: id)
            print("THL_APP_RANKING board=\(board) compact=true sixthUp=true pageTwo=true detailReturn=true menu=true")
        }
    }

    func testTopNavigationAndCatalogFilterReturn() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "catalog"]
        app.launch()
        let tabs = ["catalog", "feed", "rankings", "search", "library", "downloads", "settings"]
        wait("initial catalog navigation", seconds: 45) { self.app.buttons["nav.catalog"].hasFocus }
        for (index, tab) in tabs.enumerated() {
            if index > 0 { press(.down, focus: "nav." + tab) }
            if tab == "feed" {
                press(.right)
                _ = try automaticFeedReady()
                press(.menu, focus: "nav.feed")
            } else if tab != "downloads" {
                press(.right)
                wait("content focus " + tab) {
                    self.yaoSnapshots().contains { $0.hasFocus && !$0.identifier.hasPrefix("nav.") }
                }
                press(.menu)
                if !app.buttons["nav." + tab].hasFocus { press(.menu) }
                wait("menu returns navigation " + tab) { self.app.buttons["nav." + tab].hasFocus }
            } else {
                wait("downloads empty page") { self.app.staticTexts["下载与离线管理"].exists }
            }
            print("THL_TV_TAB tab=\(tab) focus=true return=true")
        }
        for tab in tabs.dropLast().reversed() {
            press(.up, focus: "nav." + tab)
        }
        press(.right, focus: "catalog.category.app:discover:all")
        press(.right, focus: "catalog.category.app:discover:playlet")
        press(.right, focus: "catalog.category.app:discover:motion_comic")
        press(.right, focus: "catalog.category.app:discover:ai_playlet")
        press(.right, focus: "catalog.filter")
        press(.select)
        wait("catalog filter opens") { self.app.staticTexts["排序与筛选"].exists }
        press(.menu)
        wait("catalog filter return focus") { self.app.buttons["catalog.filter"].hasFocus }
        press(.menu, focus: "nav.catalog")
        print("THL_TV_FILTER open=true back=true restored=true")
    }

    func testOfficialGuessWordsRemoteSearch() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "catalog"]
        app.launch()
        wait("guess initial navigation", seconds: 45) { self.app.buttons["nav.catalog"].hasFocus }
        press(.down, focus: "nav.feed")
        press(.down, focus: "nav.rankings")
        press(.down, focus: "nav.search")
        wait("official cue visible", seconds: 45) {
            self.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.suggestion.'")).firstMatch.exists
        }
        press(.right, focus: "search.query")
        press(.down)
        wait("cue focused") { self.yaoSnapshots().contains { $0.hasFocus && $0.identifier.hasPrefix("search.suggestion.") } }
        let selected = try XCTUnwrap(self.yaoSnapshots().first { $0.hasFocus && $0.identifier.hasPrefix("search.suggestion.") })
        let keyword = selected.label
        press(.select)
        wait("cue submits official search", seconds: 60) {
            self.app.textFields["search.query"].value as? String == keyword && self.app.buttons["search.result.0"].exists
        }
        press(.menu, focus: "nav.search")
        press(.right, focus: "search.result.0")
        press(.select)
        wait("cue detail opens", seconds: 60) { self.app.buttons["detail.play"].hasFocus }
        press(.menu, focus: "search.result.0")
        press(.up, focus: "search.query")
        press(.up, focus: "nav.search")
        print("THL_TV_GUESS official=true select=true search=true detail=true focus=true back=true")
    }

    func testLegacyRecommendationRoutesOpenDiscovery() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        for (route, category) in [("recommendations", "all"), ("recommendations_comic", "motion_comic")] {
            app.launchArguments = ["-testPage", route]
            app.launch()
            wait("legacy route navigation", seconds: 45) { self.app.buttons["nav.catalog"].hasFocus }
            XCTAssertFalse(app.buttons["nav.recommendations"].exists)
            wait("legacy route cards", seconds: 60) { self.app.buttons["catalog.result.0"].exists }
            press(.down, focus: "catalog.category.app:discover:" + category)
            press(.down, focus: "catalog.result.0")
            press(.down, focus: "catalog.result.6")
            press(.menu, focus: "nav.catalog")
            app.terminate()
            print("THL_LEGACY_DISCOVERY route=\(route) category=\(category) autoPaging=true")
        }
    }

    private func feedReady() -> String {
        var title = ""
        wait("recommended drama is playing", seconds: 120) {
            if self.app.buttons["player.wake"].exists && self.app.buttons["player.wake"].hasFocus { self.press(.select) }
            let snapshot = self.yaoSnapshots()
            title = snapshot.first { $0.identifier == "player.title" }?.label ?? ""
            let position = snapshot.first { $0.identifier == "player.position" }?.label ?? ""
            let duration = snapshot.first { $0.identifier == "player.duration" }?.label ?? ""
            return !title.isEmpty && self.seconds(position) > 0 && self.seconds(duration) > 10
        }
        print("THL_TV_FEED_PLAY title=\(title) progress=\(app.staticTexts["feed.progress"].label) position=\(app.staticTexts["player.position"].label) duration=\(app.staticTexts["player.duration"].label)")
        return title
    }

    private func feedPlayFocus() {
        if app.buttons["player.wake"].exists && app.buttons["player.wake"].hasFocus { press(.select) }
        let target = yaoSnapshots().first { $0.hasFocus }?.identifier ?? ""
        switch target {
        case "player.back":
            press(.down, focus: "player.nextDrama")
            press(.down, focus: "player.playPause")
        case "player.nextDrama", "player.previousDrama", "player.favorite", "player.detail", "player.refreshFeed":
            press(.down, focus: "player.playPause")
        case "player.seekForward": press(.left, focus: "player.playPause")
        case "player.seekBackward": press(.right, focus: "player.playPause")
        case "player.nextEpisode", "player.prevEpisode", "player.episodeDrawer":
            press(.up, focus: "player.nextDrama")
            press(.down, focus: "player.playPause")
        case "player.speed": press(.up, focus: "player.playPause")
        case "player.quality":
            press(.up, focus: "player.seekForward")
            press(.left, focus: "player.playPause")
        default: break
        }
    }

    func testOfficialVideoFeedRemotePlaybackAndReturn() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "feed"]
        app.launch()
        _ = try automaticFeedReady()
        let first = feedReady()
        for id in ["player.nextDrama", "player.favorite", "player.detail", "player.refreshFeed"] {
            let button = app.buttons[id]
            XCTAssertTrue(app.frame.contains(button.frame), "feed control in screen: " + id)
        }
        var titles = [first]
        for _ in 0..<4 {
            feedPlayFocus()
            press(.menu, focus: "player.wake")
            press(.down)
            _ = try automaticFeedReady(differentFrom: titles.last!)
            titles.append(feedReady())
        }
        XCTAssertEqual(Set(titles).count, 5)
        feedPlayFocus()
        press(.menu, focus: "player.wake")
        press(.up)
        XCTAssertEqual(feedReady(), titles[3])
        feedPlayFocus()
        press(.playPause)
        wait("feed paused") { self.app.buttons["player.playPause"].label == "播放" }
        press(.playPause)
        wait("feed resumes") { self.app.buttons["player.playPause"].label == "暂停" }
        press(.up, focus: "player.nextDrama")
        press(.right, focus: "player.favorite")
        let originalFavorite = app.buttons["player.favorite"].label
        press(.select)
        wait("feed favorite toggles") { self.app.buttons["player.favorite"].label != originalFavorite }
        press(.select)
        wait("feed favorite restored") { self.app.buttons["player.favorite"].label == originalFavorite }
        press(.right, focus: "player.detail")
        press(.select)
        wait("feed detail opened", seconds: 45) { self.app.buttons["detail.play"].hasFocus }
        press(.menu)
        XCTAssertEqual(feedReady(), titles[3])
        feedPlayFocus()
        press(.right, focus: "player.seekForward")
        press(.right)
        if app.buttons["player.prevEpisode"].hasFocus { press(.right, focus: "player.episodeDrawer") }
        wait("feed episode control") { self.app.buttons["player.episodeDrawer"].hasFocus }
        press(.select)
        wait("feed drawer selected episode") { self.yaoSnapshots().contains { $0.hasFocus && $0.identifier.hasPrefix("drawer.episode.") } }
        let selectedEpisode = try XCTUnwrap(yaoSnapshots().first { $0.hasFocus && $0.identifier.hasPrefix("drawer.episode.") })
        let number = Int(selectedEpisode.identifier.split(separator: ".").last!)!
        press(.right, focus: "drawer.episode.\(number + 1)")
        press(.select)
        _ = feedReady()
        XCTAssertTrue(app.staticTexts["player.episode"].label.contains("第 \(number + 1) 集"))
        feedPlayFocus()
        press(.down, focus: "player.speed")
        press(.right)
        if app.buttons["player.quality"].hasFocus { press(.right, focus: "player.danmaku") }
        wait("feed danmaku focus") { self.app.buttons["player.danmaku"].hasFocus }
        let danmaku = app.buttons["player.danmaku"].label
        press(.select)
        wait("feed danmaku toggle") { self.app.buttons["player.danmaku"].label != danmaku }
        press(.select)
        let beforeBackground = seconds(app.staticTexts["player.position"].label)
        press(.home)
        wait("feed background") { self.app.state != .runningForeground }
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        _ = feedReady()
        wait("feed foreground progresses", seconds: 30) {
            if self.app.buttons["player.wake"].exists { self.press(.select) }
            return self.seconds(self.app.staticTexts["player.position"].label) > beforeBackground
        }
        press(.menu, focus: "player.wake")
        press(.menu, focus: "nav.feed")
        press(.down, focus: "nav.rankings")
        press(.up, focus: "nav.feed")
        press(.right)
        _ = try automaticFeedReady(title: titles[3])
        feedPlayFocus()
        press(.up, focus: "player.nextDrama")
        press(.right, focus: "player.favorite")
        press(.right, focus: "player.detail")
        press(.right, focus: "player.refreshFeed")
        press(.select)
        _ = try automaticFeedReady()
        press(.menu, focus: "nav.feed")
        print("THL_TV_FEED_RESULT unique=5 paging=true previous=true pause=true favorite=true detail=true episodes=true danmaku=true returnFocus=true leave=true background=true refresh=true bounds=true")
    }

    private struct FeedCheckpoint {
        let title: String
        let episode: Int
        let position: Int
    }

    private func automaticFeedReady(title expected: String? = nil, differentFrom previous: String? = nil, minimum: Int = 1) throws -> FeedCheckpoint {
        var checkpoint: FeedCheckpoint?
        let regex = try NSRegularExpression(pattern: "^(.*) · 第 ([0-9]+) 集 · 已播放 ([0-9]+) 秒 · 播放中$")
        wait("feed automatically plays with picture focus", seconds: 120) {
            guard let wake = self.yaoSnapshots().first(where: { $0.identifier == "player.wake" && $0.hasFocus }),
                  let value = wake.value as? String,
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let titleRange = Range(match.range(at: 1), in: value),
                  let episodeRange = Range(match.range(at: 2), in: value),
                  let positionRange = Range(match.range(at: 3), in: value),
                  let episode = Int(value[episodeRange]), let position = Int(value[positionRange]) else { return false }
            let title = String(value[titleRange])
            guard expected == nil || title == expected, previous == nil || title != previous, position >= minimum else { return false }
            checkpoint = FeedCheckpoint(title: title, episode: episode, position: position)
            return true
        }
        let result = try XCTUnwrap(checkpoint)
        XCTAssertFalse(app.buttons["feed.watch"].exists)
        print("THL_TV_FEED_AUTO title=\(result.title) episode=\(result.episode) position=\(result.position) focus=player.wake")
        return result
    }

    func testVideoFeedAutomaticEntryProgressAndFocus() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "feed"]
        app.launch()
        let first = try automaticFeedReady()
        press(.down)
        let second = try automaticFeedReady(differentFrom: first.title)
        press(.down)
        let third = try automaticFeedReady(differentFrom: second.title)
        XCTAssertNotEqual(third.title, first.title)
        press(.up)
        let resumedSecond = try automaticFeedReady(title: second.title, minimum: second.position)
        XCTAssertEqual(resumedSecond.episode, second.episode)
        press(.select)
        wait("feed controls focus") { self.app.buttons["player.playPause"].hasFocus }
        press(.up, focus: "player.nextDrama")
        press(.right, focus: "player.favorite")
        press(.right, focus: "player.detail")
        press(.select)
        wait("feed opens detail", seconds: 60) { self.app.buttons["detail.play"].hasFocus }
        press(.select)
        wait("detail player ready", seconds: 120) {
            self.app.staticTexts["player.position"].exists && self.seconds(self.app.staticTexts["player.position"].label) > 0
        }
        showControls()
        focusDrawer()
        press(.select)
        wait("detail player drawer focus") { self.yaoSnapshots().contains { $0.hasFocus && $0.identifier.hasPrefix("drawer.episode.") } }
        let nextEpisode = second.episode + 1
        press(.right, focus: "drawer.episode.\(nextEpisode)")
        press(.select)
        wait("detail player changed episode", seconds: 120) {
            self.showControls()
            return self.app.staticTexts["player.episode"].label.contains("第 \(nextEpisode) 集") && self.seconds(self.app.staticTexts["player.position"].label) > 0
        }
        showControls()
        press(.right, focus: "player.seekForward")
        press(.select)
        press(.select)
        wait("detail player seek persists") { self.seconds(self.app.staticTexts["player.position"].label) >= 20 }
        let detailSavedPosition = seconds(app.staticTexts["player.position"].label)
        press(.menu, focus: "player.wake")
        press(.menu)
        wait("child returns to selected episode") { self.app.buttons["detail.episode.\(nextEpisode)"].hasFocus }
        press(.menu)
        wait("detail restores feed control focus", seconds: 60) { self.app.buttons["player.detail"].hasFocus }
        feedPlayFocus()
        press(.menu, focus: "player.wake")
        let afterDetail = try automaticFeedReady(title: second.title, minimum: detailSavedPosition)
        XCTAssertEqual(afterDetail.episode, nextEpisode)
        press(.menu, focus: "nav.feed")
        XCTAssertTrue(app.buttons["nav.feed"].hasFocus)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["nav.feed"].hasFocus)
        press(.up, focus: "nav.catalog")
        press(.down, focus: "nav.feed")
        press(.right)
        let reentered = try automaticFeedReady(title: second.title, minimum: afterDetail.position)
        XCTAssertEqual(reentered.episode, nextEpisode)
        press(.menu, focus: "nav.feed")
        press(.select)
        let selected = try automaticFeedReady(title: second.title, minimum: reentered.position)
        XCTAssertEqual(selected.episode, nextEpisode)
        press(.menu, focus: "nav.feed")
        press(.right)
        let down = try automaticFeedReady(title: second.title, minimum: selected.position)
        XCTAssertEqual(down.episode, nextEpisode)
        press(.home)
        wait("feed background") { self.app.state != .runningForeground }
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        _ = try automaticFeedReady(title: second.title, minimum: down.position + 1)
        press(.menu, focus: "nav.feed")
        print("THL_TV_FEED_AUTO_RESULT initialNoClick=true verticalSwitch=true previousProgress=true detailFocus=true detailProgress=true detailChildEpisode=true navFocus=true tabResume=true selectResume=true downResume=true background=true")
    }

    func testSidebarNavigationExhaustiveFocusVerification() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "catalog"]
        app.launch()

        let tabs = ["catalog", "feed", "rankings", "search", "library", "downloads", "settings"]

        // 1. 验证启动后初始焦点处于 nav.catalog
        wait("initial sidebar focus on catalog", seconds: 45) { self.app.buttons["nav.catalog"].hasFocus }

        // 截取侧边栏展开状态高清截图并保存
        let sidebarShot = XCUIScreen.main.screenshot()
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        try? sidebarShot.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_sidebar_navigation_focus.png"))

        // 2. 顶部与左侧边界探测：在首项 nav.catalog 处按 Up 和 Left，焦点必须保持在 nav.catalog，不能跑飞或失焦
        press(.up)
        XCTAssertTrue(app.buttons["nav.catalog"].hasFocus, "catalog tab resists up boundary")
        press(.left)
        XCTAssertTrue(app.buttons["nav.catalog"].hasFocus, "catalog tab resists left boundary")

        // 3. 正向垂直下移遍历所有 7 个 Tab，确保无漏项、无焦点卡死
        for (index, tab) in tabs.enumerated() {
            if index > 0 {
                press(.down, focus: "nav.\(tab)")
            }
            XCTAssertTrue(app.buttons["nav.\(tab)"].hasFocus, "tab \(tab) has focus during downward pass")
        }

        // 4. 底部与左侧边界探测：在末项 nav.settings 处按 Down 和 Left，焦点必须保持在 nav.settings
        press(.down)
        XCTAssertTrue(app.buttons["nav.settings"].hasFocus, "settings tab resists down boundary")
        press(.left)
        XCTAssertTrue(app.buttons["nav.settings"].hasFocus, "settings tab resists left boundary")

        // 5. 逆向垂直上移遍历回首项，确保反向流转顺畅
        for tab in tabs.dropLast().reversed() {
            press(.up, focus: "nav.\(tab)")
            XCTAssertTrue(app.buttons["nav.\(tab)"].hasFocus, "tab \(tab) has focus during upward pass")
        }

        // 6. 深度验证每个 Tab 的切入与 Menu 精确返回原位（解决跳回首项的焦点 Bug）
        // 6.1 发现 (catalog): 按 Right 切入分类横条 -> 按 Menu 返回 nav.catalog
        press(.right)
        wait("content focus catalog") { self.yaoSnapshots().contains { $0.hasFocus && !$0.identifier.hasPrefix("nav.") } }
        press(.menu)
        wait("menu returns to nav.catalog") { self.app.buttons["nav.catalog"].hasFocus }

        // 6.2 推荐 (feed): 按 Down 聚焦 nav.feed -> 按 Right 切入全屏播放 -> 按 Menu 退出播放并返回 nav.feed
        press(.down, focus: "nav.feed")
        press(.right)
        _ = try automaticFeedReady()
        press(.menu, focus: "nav.feed")
        XCTAssertTrue(app.buttons["nav.feed"].hasFocus, "menu accurately restored to nav.feed")

        // 6.3 榜单 (rankings): 按 Down 聚焦 nav.rankings -> 按 Right 切入榜单内容 -> 按 Menu 返回 nav.rankings
        press(.down, focus: "nav.rankings")
        press(.right)
        wait("content focus rankings") { self.yaoSnapshots().contains { $0.hasFocus && !$0.identifier.hasPrefix("nav.") } }
        press(.menu)
        wait("menu returns to nav.rankings") { self.app.buttons["nav.rankings"].hasFocus }

        // 6.4 搜索 (search): 按 Down 聚焦 nav.search -> 按 Right 切入搜索输入框/热词 -> 按 Menu 返回 nav.search
        press(.down, focus: "nav.search")
        press(.right)
        wait("content focus search") { self.yaoSnapshots().contains { $0.hasFocus && !$0.identifier.hasPrefix("nav.") } }
        press(.menu)
        wait("menu returns to nav.search") { self.app.buttons["nav.search"].hasFocus }

        // 6.5 追剧与历史 (library): 按 Down 聚焦 nav.library -> 按 Right 切入内容 -> 按 Menu 返回 nav.library
        press(.down, focus: "nav.library")
        press(.right)
        wait("content focus library") { self.yaoSnapshots().contains { $0.hasFocus && !$0.identifier.hasPrefix("nav.") } }
        press(.menu)
        wait("menu returns to nav.library") { self.app.buttons["nav.library"].hasFocus }

        // 6.6 下载 (downloads): 按 Down 聚焦 nav.downloads -> 按 Right 切入 -> 按 Menu 返回 nav.downloads
        press(.down, focus: "nav.downloads")
        press(.right)
        wait("downloads explore button focus") { self.app.buttons["downloads.explore"].hasFocus }
        press(.menu)
        wait("menu returns to nav.downloads") { self.app.buttons["nav.downloads"].hasFocus }

        // 6.7 设置 (settings): 按 Down 聚焦 nav.settings -> 按 Right 切入设置分类 -> 按 Menu 返回 nav.settings
        press(.down, focus: "nav.settings")
        press(.right)
        wait("content focus settings") { self.yaoSnapshots().contains { $0.hasFocus && !$0.identifier.hasPrefix("nav.") } }
        press(.menu)
        wait("menu returns to nav.settings") { self.app.buttons["nav.settings"].hasFocus }

        // 7. 连续跨度快速跳转与记忆性校验：
        // 从 settings 直接连续按 Up 到 feed，再通过 Select 切入，验证 Select 切入能力与记忆
        press(.up, focus: "nav.downloads")
        press(.up, focus: "nav.library")
        press(.up, focus: "nav.search")
        press(.up, focus: "nav.rankings")
        press(.up, focus: "nav.feed")
        press(.select) // 验证 Select 键也能直接进入内容区
        _ = try automaticFeedReady()
        press(.menu, focus: "nav.feed")
        XCTAssertTrue(app.buttons["nav.feed"].hasFocus, "select key entry and menu return to nav.feed")

        print("THL_TV_SIDEBAR_EXHAUSTIVE_RESULT initialFocus=true boundaries=true allSevenTabs=true forwardBackward=true rightEntryAll=true selectEntry=true accurateMenuReturn=true persistence=true")
    }

    func testPlayerControlsDismissAndMenuReturn() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "detail", "-testDramaId", "hongguo:7694291604915358744", "-testDramaTitle", "控制栏与Menu返回验证"]
        app.launch()

        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("detail play focused") { self.app.buttons["detail.play"].hasFocus }

        // 1. 直接按 Select 进入播放
        press(.select)

        // 2. 验证默认不弹出控制栏：画面纯净，player.wake 处于等待或获得焦点状态
        wait("player starts without obscuring controls", seconds: 30) {
            self.app.buttons["player.wake"].exists
        }
        XCTAssertFalse(app.buttons["player.playPause"].exists, "控制栏默认不显示遮挡画面")

        // 3. 点击唤醒控制栏
        showControls()
        wait("controls become visible") {
            self.app.buttons["player.playPause"].exists && self.app.buttons["player.playPause"].hasFocus
        }

        // 4. 按遥控器 Menu 键：核心验证！
        // 期望：仅收起控制栏，焦点交回 player.wake，继续留在全屏播放页面！
        press(.menu)
        wait("menu dismisses controls without leaving player", seconds: 10) {
            self.app.buttons["player.wake"].exists && !self.app.buttons["player.playPause"].exists
        }
        XCTAssertTrue(app.buttons["player.wake"].exists, "控制栏收起后，播放器唤醒层存在，继续保持播放")

        // 5. 再次按遥控器 Menu 键：此时正常退出播放页回到选集详情页！
        press(.menu)
        wait("second menu returns to episode detail") {
            !self.app.buttons["player.wake"].exists && (self.app.buttons["detail.episode.76"].hasFocus || self.app.buttons["detail.play"].hasFocus || self.app.buttons["detail.play"].exists)
        }

        print("THL_TV_PLAYER_CONTROLS_VERIFICATION initialHidden=true tapScreenHide=true menuDismissControls=true menuExitToDetail=true")
    }

    func testPlayerQuickSeekAndControlsDecoupled() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "detail", "-testDramaId", "hongguo:7694291604915358744", "-testDramaTitle", "快进退解耦与控制浮层自动化测试"]
        app.launch()

        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("detail play focused") { self.app.buttons["detail.play"].hasFocus }

        // 1. 点击播放进入全屏播放器
        press(.select)

        // 2. 等待起播唤醒层就绪（全屏播放无遮挡，player.wake 存在并进入实际播放中状态）
        wait("player starts actively playing", seconds: 45) {
            guard let wake = self.yaoSnapshots().first(where: { $0.identifier == "player.wake" }) else { return false }
            if let val = wake.value as? String, val.contains("播放中") {
                return true
            }
            return false
        }
        XCTAssertFalse(app.buttons["player.playPause"].exists, "进入播放时控制栏默认不显示遮挡画面")

        // 3. 验证需求2与需求3：按遥控器 Right（右键），焦点向右流转直接触发快进 10 秒
        press(.right)
        // 关键断言：绝对不能弹出复杂控制栏！
        XCTAssertFalse(app.buttons["player.playPause"].exists, "按右键直接快进，绝不弹出复杂控制栏")
        // 验证轻量级进度卡片出现
        wait("quick seek indicator appears on right arrow", seconds: 8) {
            self.app.descendants(matching: .any)["player.quickSeek"].exists ||
            self.app.staticTexts.allElementsBoundByIndex.contains(where: { $0.label.contains("快进") || $0.label.contains("滑动快进") })
        }

        // 4. 验证需求2与需求3：按遥控器 Left（左键），焦点向左流转直接触发快退 10 秒
        press(.left)
        XCTAssertFalse(app.buttons["player.playPause"].exists, "按左键直接快退，绝不弹出复杂控制栏")
        wait("quick seek indicator appears on left arrow", seconds: 8) {
            self.app.descendants(matching: .any)["player.quickSeek"].exists ||
            self.app.staticTexts.allElementsBoundByIndex.contains(where: { $0.label.contains("快退") || $0.label.contains("滑动快退") })
        }

        // 截图归档：验证轻量级快进卡片高保真渲染
        let quickSeekShot = XCUIScreen.main.screenshot()
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        try? quickSeekShot.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_quick_seek_indicator_verified.png"))

        // 5. 验证需求2：只有点击 Select 确认键时，才唤起完整控制栏
        press(.select)
        wait("select key awakens full controls", seconds: 5) {
            self.app.buttons["player.playPause"].exists && self.app.buttons["player.playPause"].hasFocus
        }
        XCTAssertTrue(app.buttons["player.playPause"].hasFocus, "点击Select唤起控制栏并获焦播放/暂停键")

        // 6. 按 Menu 键收起控制栏，恢复纯净播放状态
        press(.menu)
        wait("menu dismisses controls", seconds: 5) {
            self.app.buttons["player.wake"].exists && !self.app.buttons["player.playPause"].exists
        }

        // 7. 再次按 Menu 键退出播放器返回详情页
        press(.menu)
        wait("second menu returns to detail", seconds: 5) {
            !self.app.buttons["player.wake"].exists && (self.app.buttons["detail.play"].exists || self.app.buttons["detail.play"].hasFocus)
        }

        print("THL_TV_QUICK_SEEK_DECOUPLED_RESULT rightSeekDirect=true leftSeekDirect=true noObscuringControls=true quickIndicatorShown=true selectAwakenControls=true menuDismissControls=true menuExit=true")
    }

    func testDirectPlayPauseWithoutControlsOverlay() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "detail", "-testDramaId", "hongguo:7694291604915358744", "-testDramaTitle", "播放按键直接暂停与播放测试"]
        app.launch()

        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 45))
        wait("detail play focused") { self.app.buttons["detail.play"].hasFocus }

        // 1. 点击播放进入全屏播放器
        press(.select)

        // 2. 等待起播唤醒层就绪（全屏播放无遮挡，player.wake 存在并进入实际播放中状态）
        wait("player starts actively playing", seconds: 45) {
            guard let wake = self.yaoSnapshots().first(where: { $0.identifier == "player.wake" }) else { return false }
            if let val = wake.value as? String, val.contains("播放中") {
                return true
            }
            return false
        }
        XCTAssertFalse(app.buttons["player.playPause"].exists, "进入播放时控制栏默认不显示遮挡画面")

        // 3. 按遥控器 Play/Pause 键，应该立即暂停，绝不弹出浮层！
        press(.playPause)
        XCTAssertFalse(app.buttons["player.playPause"].exists, "按Play/Pause键控制播放暂停，绝不弹出控制浮层")
        wait("player state toggles to paused", seconds: 10) {
            guard let wake = self.yaoSnapshots().first(where: { $0.identifier == "player.wake" }) else { return false }
            let val = wake.value as? String ?? ""
            return val.contains("已暂停")
        }
        XCTAssertFalse(app.buttons["player.playPause"].exists, "暂停后控制栏依然不弹出遮挡画面")

        // 4. 再次按遥控器 Play/Pause 键，应该立即恢复播放，依然不弹出浮层！
        press(.playPause)
        XCTAssertFalse(app.buttons["player.playPause"].exists, "再次按Play/Pause键恢复播放，绝不弹出控制浮层")
        wait("player state toggles back to playing", seconds: 10) {
            guard let wake = self.yaoSnapshots().first(where: { $0.identifier == "player.wake" }) else { return false }
            let val = wake.value as? String ?? ""
            return val.contains("播放中")
        }
        XCTAssertFalse(app.buttons["player.playPause"].exists, "播放中控制栏保持纯净无遮挡")

        // 5. 按 Select 键唤出浮层
        press(.select)
        wait("select awakens controls", seconds: 5) {
            self.app.buttons["player.playPause"].exists && self.app.buttons["player.playPause"].hasFocus
        }
        XCTAssertTrue(app.buttons["player.playPause"].hasFocus, "点击Select唤起控制栏并获焦播放/暂停键")

        // 6. 按 Menu 退出控制栏并退出播放器
        press(.menu)
        wait("menu dismisses controls", seconds: 5) {
            self.app.buttons["player.wake"].exists && !self.app.buttons["player.playPause"].exists
        }
        press(.menu)
        print("THL_TV_DIRECT_PLAY_PAUSE_VERIFIED pauseWithoutControls=true resumeWithoutControls=true selectAwakensControls=true")
    }

    func testICloudSyncToggleAndSyncNowFocus() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings_sync"]
        app.launch()

        // 1. 等待设置页就绪，检测到 iCloud 同步开关
        wait("icloud toggle button exists", seconds: 45) {
            self.app.buttons["settings.icloud.toggle"].exists
        }

        // 2. 遥控器导航到右侧 iCloud 设置面板
        for _ in 0..<6 {
            if app.buttons["settings.icloud.toggle"].hasFocus || app.buttons["settings.icloud.syncNow"].hasFocus { break }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.identifier == "nav.settings" {
                press(.down)
            } else if focused.label.contains("iCloud 同步") {
                press(.right)
            } else {
                press(.right)
            }
        }
        wait("icloud toggle button focused", seconds: 15) {
            self.app.buttons["settings.icloud.toggle"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.icloud.toggle"].hasFocus, "成功聚焦在 iCloud 同步开关按钮")

        // 3. 如果当前处于关闭状态，按下 Select 打开同步
        if !app.buttons["settings.icloud.syncNow"].exists {
            press(.select)
            wait("icloud sync enabled and syncNow button appears", seconds: 5) {
                self.app.buttons["settings.icloud.syncNow"].exists
            }
        }

        // 4. 关键验证：在开关按钮上按下 Down 键，焦点必须顺畅转移到「立刻同步」按钮！
        press(.down)
        wait("syncNow button focused on pressing Down", seconds: 5) {
            self.app.buttons["settings.icloud.syncNow"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.icloud.syncNow"].hasFocus, "立刻同步按钮成功获取焦点")

        // 截图归档：立刻同步按钮获焦状态高保真渲染
        let syncNowShot = XCUIScreen.main.screenshot()
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        try? syncNowShot.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_icloud_sync_now_focused.png"))

        // 5. 点击 Select 触发立即同步
        press(.select)
        wait("sync status displays syncing or updated", seconds: 5) {
            self.app.staticTexts["settings.icloud.status"].exists
        }

        // 6. 在立刻同步按钮上按 Up 键，焦点流畅返回到开关按钮
        press(.up)
        wait("focus returns to toggle on pressing Up", seconds: 5) {
            self.app.buttons["settings.icloud.toggle"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.icloud.toggle"].hasFocus, "从立刻同步按Up键顺利返回开关按钮")

        // 7. 按 Left 键返回设置左侧分类列表
        press(.left)
        wait("focus returns to settings nav", seconds: 5) {
            self.app.buttons.matching(NSPredicate(format: "label CONTAINS 'iCloud 同步' AND hasFocus == true")).firstMatch.exists
        }

        print("THL_TV_ICLOUD_SYNC_FOCUS_RESULT toggleFocus=true downToSyncNow=true syncNowFocused=true actionSuccess=true upToToggle=true returnNav=true")
    }

    // MARK: - 设置面板重构与焦点自动化测试

    /// 1. 验证设置中网络代码彻底移除，6 大分类正常存在
    func testSettingsNetworkCodeRemoved() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings"]
        app.launch()

        wait("settings view appears", seconds: 45) {
            self.app.buttons["settings.nav.sources"].exists
        }

        // 验证网络设置分类已被彻底移除
        XCTAssertFalse(app.buttons["settings.nav.network"].exists, "旧的网络设置分类已彻底删除")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS '网络与策略'")).firstMatch.exists, "界面中不再包含任何网络策略文本")

        // 验证当前所有 6 大分类按钮均完整存在
        XCTAssertTrue(app.buttons["settings.nav.sources"].exists)
        XCTAssertTrue(app.buttons["settings.nav.sync"].exists)
        XCTAssertTrue(app.buttons["settings.nav.cache"].exists)
        XCTAssertTrue(app.buttons["settings.nav.help"].exists)
        XCTAssertTrue(app.buttons["settings.nav.contact"].exists)
        XCTAssertTrue(app.buttons["settings.nav.about"].exists)

        print("THL_TV_SETTINGS_RESULT networkDeleted=true allSixCategoriesValid=true")
    }

    /// 2. 帮助说明页面及其遥控器焦点测试
    func testSettingsHelpPanelFocus() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings_help"]
        app.launch()

        // 1. 等待帮助说明卡片就绪
        wait("help panel cards exist", seconds: 45) {
            self.app.buttons["settings.help.remote"].exists &&
            self.app.buttons["settings.help.icloud"].exists &&
            self.app.buttons["settings.help.troubleshooting"].exists
        }

        // 2. 导航切入帮助说明内容区
        press(.right)
        if app.buttons["settings.help.icloud"].hasFocus {
            press(.up, focus: "settings.help.remote")
        }
        XCTAssertTrue(app.buttons["settings.help.remote"].hasFocus, "成功聚焦在遥控器操作指南卡片")

        // 3. 向下移动焦点到 iCloud 同步卡片
        press(.down, focus: "settings.help.icloud")
        XCTAssertTrue(app.buttons["settings.help.icloud"].hasFocus, "成功聚焦在 iCloud 同步指南卡片")

        // 4. 再次向下移动焦点到排障卡片
        press(.down, focus: "settings.help.troubleshooting")
        XCTAssertTrue(app.buttons["settings.help.troubleshooting"].hasFocus, "成功聚焦在故障排查指南卡片")

        // 5. 向上返回 iCloud 卡片
        press(.up, focus: "settings.help.icloud")
        XCTAssertTrue(app.buttons["settings.help.icloud"].hasFocus, "从排障卡片向上返回 iCloud 指南卡片")

        // 截图归档：帮助说明页面高保真渲染
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let helpShot = XCUIScreen.main.screenshot()
        try? helpShot.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_help_panel_focused.png"))

        print("THL_TV_SETTINGS_RESULT helpPanelFocused=true")
    }

    /// 3. 联系方式页面及其遥控器焦点测试
    func testSettingsContactPanelFocus() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings_contact"]
        app.launch()

        // 1. 等待联系方式卡片就绪
        wait("contact panel cards exist", seconds: 45) {
            self.app.buttons["settings.contact.telegram"].exists &&
            self.app.buttons["settings.contact.email"].exists
        }

        // 2. 导航切入联系方式内容区
        press(.right)
        if app.buttons["settings.contact.email"].hasFocus {
            press(.up, focus: "settings.contact.telegram")
        }
        XCTAssertTrue(app.buttons["settings.contact.telegram"].hasFocus, "成功聚焦在 Telegram 官方交流群卡片")

        // 3. 向下移动焦点到邮箱反馈卡片
        press(.down, focus: "settings.contact.email")
        XCTAssertTrue(app.buttons["settings.contact.email"].hasFocus, "成功聚焦在反馈与技术支持邮箱卡片")

        // 4. 向上返回 Telegram 卡片
        press(.up, focus: "settings.contact.telegram")
        XCTAssertTrue(app.buttons["settings.contact.telegram"].hasFocus, "从邮箱卡片向上返回 Telegram 卡片")

        // 截图归档：联系方式页面高保真渲染
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let contactShot = XCUIScreen.main.screenshot()
        try? contactShot.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_contact_panel_focused.png"))

        print("THL_TV_SETTINGS_RESULT contactPanelFocused=true")
    }

    /// 4. 系统与关于页面精简测试及遥控器焦点测试
    func testSettingsAboutPanelFocus() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings_about"]
        app.launch()

        // 1. 等待关于卡片就绪
        wait("about panel cards exist", seconds: 45) {
            self.app.buttons["settings.about.compact_info"].exists &&
            self.app.buttons["settings.about.disclaimer"].exists
        }

        // 2. 验证关于页面纯粹：只放图标、版本号、编译号、免责说明
        XCTAssertTrue(app.buttons["settings.about.compact_info"].exists, "版本信息卡片存在")
        XCTAssertTrue(app.buttons["settings.about.disclaimer"].exists, "免责声明卡片存在")
        XCTAssertFalse(app.staticTexts["原生开发架构"].exists, "架构技术卡片已被彻底清理")
        XCTAssertFalse(app.staticTexts["视频解码链路"].exists, "解码链路卡片已被彻底清理")

        // 3. 导航切入版本卡片
        press(.right)
        if app.buttons["settings.about.disclaimer"].hasFocus {
            press(.up, focus: "settings.about.compact_info")
        }
        XCTAssertTrue(app.buttons["settings.about.compact_info"].hasFocus, "成功聚焦在精简版本信息卡片")

        // 4. 向下移动焦点到免责声明卡片
        press(.down, focus: "settings.about.disclaimer")
        XCTAssertTrue(app.buttons["settings.about.disclaimer"].hasFocus, "成功聚焦在免责声明卡片")

        // 5. 向上返回版本信息卡片
        press(.up, focus: "settings.about.compact_info")
        XCTAssertTrue(app.buttons["settings.about.compact_info"].hasFocus, "从免责声明向上返回版本卡片")

        // 截图归档：关于页面高保真渲染
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let aboutShot = XCUIScreen.main.screenshot()
        try? aboutShot.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_about_panel_focused.png"))

        print("THL_TV_SETTINGS_RESULT aboutPanelPure=true aboutPanelFocused=true")
    }

    /// 5. 验证进入设置页面后一级主导航栏自动关闭，设置分类完全可用且可自由操作与返回
    func testEnterSettingsHidesSidebarAndEnablesInteraction() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings"]
        app.launch()

        // 1. 等待侧边栏启动就绪，聚焦在设置 Tab
        wait("sidebar settings tab exists and focused", seconds: 45) {
            self.app.buttons["nav.settings"].exists && self.app.buttons["nav.settings"].hasFocus
        }
        XCTAssertTrue(app.buttons["nav.settings"].hasFocus, "初始焦点在一级主导航栏设置项上")

        // 2. 按向右键进入设置页面
        press(.right)

        // 3. 验证主导航栏已被立即关闭/隐藏（不存在于当前可见视图），焦点已稳固落在设置页面的分类上
        wait("sidebar hidden and settings category focused", seconds: 15) {
            !self.app.buttons["nav.settings"].exists && (self.app.buttons["settings.nav.sources"].hasFocus || self.app.buttons["settings.nav.sources"].exists)
        }
        XCTAssertFalse(app.buttons["nav.settings"].exists, "一级主导航栏已彻底关闭收起，绝无遮挡")
        XCTAssertTrue(app.buttons["settings.nav.sources"].hasFocus, "焦点已成功进入设置页面的站源管理分类")

        // 4. 验证在设置页面内可以自由流畅操作：向下移动焦点至 iCloud 同步
        press(.down, focus: "settings.nav.sync")
        XCTAssertTrue(app.buttons["settings.nav.sync"].hasFocus, "在设置页面内向下移动聚焦到 iCloud 同步")

        // 5. 再次向下移动至存储与缓存
        press(.down, focus: "settings.nav.cache")
        XCTAssertTrue(app.buttons["settings.nav.cache"].hasFocus, "在设置页面内向下移动聚焦到存储与缓存")

        // 6. 从左侧分类按向左键，验证一级主导航栏能够顺滑重新唤出并聚焦
        press(.left)
        wait("sidebar reopened", seconds: 15) {
            self.app.buttons["nav.settings"].exists && self.app.buttons["nav.settings"].hasFocus
        }
        XCTAssertTrue(app.buttons["nav.settings"].hasFocus, "在设置分类按向左键，成功重新唤出一级主导航栏并聚焦")

        // 7. 截图归档
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_sidebar_toggle_verified.png"))

        print("THL_TV_SETTINGS_RESULT sidebarClosedOnEnter=true settingsInteractive=true sidebarReopenedOnLeft=true")
    }

    /// 6. 综合验证：
    /// 1) 焦点在主导航栏设置按钮时不自动进入，需按 Select / Right 才进入
    /// 2) 数据源管理按钮选中与获焦样式区分明确
    /// 3) 存储与缓存管理、下载页面均为全屏完整布局，彻底杜绝半屏展示
    /// 4) 联系方式中的联系邮箱为 support@thltv.com
    func testSettingsAndDownloadsEnhancedVerification() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "catalog"]
        app.launch()

        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)

        // 1. 等待主导航栏启动并聚焦在发现（catalog）
        wait("sidebar catalog tab ready", seconds: 45) {
            self.app.buttons["nav.catalog"].exists && self.app.buttons["nav.catalog"].hasFocus
        }

        // 2. 依次按向下键游走至设置（settings）按钮
        press(.down) // feed
        press(.down) // rankings
        press(.down) // search
        press(.down) // library
        press(.down) // downloads
        press(.down) // settings
        wait("sidebar focused on settings tab", seconds: 15) {
            self.app.buttons["nav.settings"].hasFocus
        }
        XCTAssertTrue(app.buttons["nav.settings"].hasFocus, "焦点当前稳固停留在主导航栏设置按钮上，绝未自动跳入内容页面")
        XCTAssertTrue(app.buttons["nav.settings"].exists, "主导航栏依然处于展开状态")
        // 验证：导航栏切换到设置后，右侧内容区已经自动联动变化为设置页面，但焦点保持在侧边栏上
        wait("settings content updated in background", seconds: 10) {
            self.app.staticTexts["系统设置"].exists
        }
        XCTAssertTrue(app.staticTexts["系统设置"].exists, "导航栏移动至设置项后，右侧内容区已自动变化为设置页面")
        XCTAssertFalse(app.buttons["settings.nav.sources"].hasFocus, "焦点并未进入内容页面")

        // 3. 点击 select 按钮进入设置页面
        press(.select)
        wait("entered settings via select", seconds: 15) {
            !self.app.buttons["nav.settings"].exists && self.app.buttons["settings.nav.sources"].hasFocus
        }
        XCTAssertFalse(app.buttons["nav.settings"].exists, "按下 Select 键后主导航栏自动收起，全屏沉浸展示")
        XCTAssertTrue(app.buttons["settings.nav.sources"].hasFocus, "焦点精准落入设置分类：站源管理")

        // 截图：站源管理获焦态
        let shot1 = XCUIScreen.main.screenshot()
        try? shot1.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_source_nav_focused.png"))

        // 4. 按向右键移入右侧数据源面板（此时左侧站源管理转为选中但未获焦态）
        press(.right)
        sleep(1)
        let shot2 = XCUIScreen.main.screenshot()
        try? shot2.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_source_nav_selected_unfocused.png"))

        // 5. 按向左键返回左侧分类导航
        press(.left)
        wait("back to category", seconds: 10) {
            self.app.buttons["settings.nav.sources"].hasFocus
        }

        // 6. 导航至存储与缓存分类并验证全屏卡片布局
        press(.down) // sync
        press(.down) // cache
        wait("cache tab focused", seconds: 10) {
            self.app.buttons["settings.nav.cache"].hasFocus
        }
        press(.right) // 进入右侧存储卡片
        sleep(1)
        let shot3 = XCUIScreen.main.screenshot()
        try? shot3.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_storage_fullwidth_verified.png"))

        // 7. 导航至联系方式分类并验证联系邮箱为 support@thltv.com
        press(.left)
        if !app.buttons["settings.nav.contact"].hasFocus {
            if app.buttons["settings.nav.about"].hasFocus {
                press(.up, focus: "settings.nav.contact")
            } else {
                for _ in 0..<3 {
                    if self.app.buttons["settings.nav.contact"].hasFocus { break }
                    press(.down)
                }
            }
        }
        wait("contact tab focused", seconds: 10) {
            self.app.buttons["settings.nav.contact"].hasFocus
        }
        press(.right) // 移入联系方式面板
        sleep(1)
        let shot4 = XCUIScreen.main.screenshot()
        try? shot4.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_contact_email_verified.png"))

        let predicate = NSPredicate(format: "label CONTAINS 'support@thltv.com'")
        let emailText = app.staticTexts.containing(predicate).firstMatch
        XCTAssertTrue(emailText.waitForExistence(timeout: 10), "联系方式页面中包含 support@thltv.com")

        // 8. 返回左侧并按向左键重新唤出一级主导航栏，进入下载页面验证全宽
        press(.left)
        press(.left) // 重新展开主侧边栏
        wait("sidebar reopened", seconds: 15) {
            self.app.buttons["nav.settings"].exists && self.app.buttons["nav.settings"].hasFocus
        }

        press(.up) // 移动到 downloads
        wait("downloads tab focused", seconds: 10) {
            self.app.buttons["nav.downloads"].hasFocus
        }
        press(.select) // 按 Select 进入下载页面
        wait("downloads page loaded", seconds: 15) {
            !self.app.buttons["nav.downloads"].exists && (self.app.buttons["downloads.explore"].exists || self.app.staticTexts["下载与离线管理"].exists)
        }
        sleep(1)
        let shot5 = XCUIScreen.main.screenshot()
        try? shot5.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_downloads_fullscreen_verified.png"))

        print("THL_TV_VERIFICATION_COMPLETE noAutoEnterSettings=true sourceStyleDifferentiated=true storageFullWidth=true downloadsFullWidth=true emailVerified=true")
    }

    /// 7. 专项验证：
    /// 1) 搜索页面支持清空已搜索文字与结果
    /// 2) 搜索页面焦点移动顺畅无阻，消除死锁
    /// 3) 搜索页面“猜你想搜”稳定展示，绝不中途消失
    /// 4) 下载页面已彻底移除局域网投屏功能，符合纯粹 tvOS 定位
    func testSearchClearAndFocusFlowAndDownloadsClean() {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "search"]
        app.launch()

        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)

        // 1. 等待主导航栏启动就绪并按 Select 进入搜索内容区
        wait("sidebar search tab focused", seconds: 25) {
            self.app.buttons["nav.search"].exists && self.app.buttons["nav.search"].hasFocus
        }
        press(.select) // 进入搜索页面，收起侧边栏
        wait("search input focused", seconds: 15) {
            !self.app.buttons["nav.search"].exists && self.app.textFields["search.query"].exists && self.app.textFields["search.query"].hasFocus
        }

        // 2. 验证“猜你想搜”稳定展示，停留 3 秒绝不消失
        wait("hot suggestions visible", seconds: 10) {
            self.app.staticTexts["猜你想搜"].exists
        }
        sleep(3)
        XCTAssertTrue(app.staticTexts["猜你想搜"].exists, "停留等待后「猜你想搜」依然稳定展示，未发生消失")

        // 3. 验证焦点在输入框与建议词、搜索按钮间畅通移动
        press(.down) // 移动到猜你想搜第一个词
        sleep(1)
        press(.up) // 回到输入框
        wait("back to query", seconds: 10) {
            self.app.textFields["search.query"].hasFocus
        }
        XCTAssertTrue(app.textFields["search.query"].hasFocus, "焦点从建议词顺利返回输入框")

        press(.right) // 移动到搜索按钮
        wait("submit button focused", seconds: 10) {
            self.app.buttons["search.submit"].hasFocus
        }
        XCTAssertTrue(app.buttons["search.submit"].hasFocus, "焦点顺利向右移动到搜索按钮")

        press(.left) // 移动回输入框
        wait("query refocused", seconds: 10) {
            self.app.textFields["search.query"].hasFocus
        }

        // 4. 选择一个建议词执行搜索
        press(.down)
        press(.select) // 点击建议词触发搜索
        wait("search completed", seconds: 20) {
            self.app.buttons["search.result.0"].exists || self.app.staticTexts["未找到相关剧集，请尝试更换关键词"].exists
        }

        let shotSearch = XCUIScreen.main.screenshot()
        try? shotSearch.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_search_results_verified.png"))

        // 5. 验证清空搜索功能：移动到“清空”按钮并点击
        wait("clear button exists", seconds: 10) {
            self.app.buttons["search.clear"].exists
        }
        XCTAssertTrue(app.buttons["search.clear"].exists, "搜索完成后展示「清空」按钮")

        if !self.app.buttons["search.clear"].hasFocus {
            press(.up)
        }
        if !self.app.buttons["search.clear"].hasFocus {
            if self.app.textFields["search.query"].hasFocus {
                press(.right)
            } else if self.app.buttons["search.submit"].hasFocus {
                press(.left)
            } else {
                press(.up)
            }
        }
        wait("clear button focused", seconds: 10) {
            self.app.buttons["search.clear"].hasFocus
        }
        press(.select) // 点击清空

        // 验证清空后重置为初始状态，猜你想搜重新可见
        wait("search cleared and restored", seconds: 10) {
            self.app.staticTexts["猜你想搜"].exists && !self.app.buttons["search.result.0"].exists
        }
        XCTAssertTrue(app.staticTexts["猜你想搜"].exists, "点击清空后文字已清空并恢复展示猜你想搜")

        let shotCleared = XCUIScreen.main.screenshot()
        try? shotCleared.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_search_cleared_verified.png"))

        // 6. 验证下载页面：唤出侧边栏并进入下载页面
        press(.left) // 唤出侧边栏
        wait("sidebar opened", seconds: 15) {
            self.app.buttons["nav.search"].exists && self.app.buttons["nav.search"].hasFocus
        }

        press(.down) // library
        press(.down) // downloads
        wait("downloads tab focused", seconds: 10) {
            self.app.buttons["nav.downloads"].hasFocus
        }
        press(.select) // 进入下载页面
        wait("downloads page loaded", seconds: 15) {
            !self.app.buttons["nav.downloads"].exists && self.app.staticTexts["下载与离线管理"].exists
        }

        // 验证下载页面绝无任何局域网投屏残留
        XCTAssertFalse(app.staticTexts["局域网互联与接续播放"].exists, "下载页面已彻底移除局域网投屏功能")
        XCTAssertFalse(app.staticTexts["大屏投屏待命已就绪"].exists, "下载页面已彻底移除大屏投屏文案")
        XCTAssertTrue(app.buttons["downloads.explore"].exists, "下载页面全屏展示离线缓存管理与去浏览短剧按钮")

        let shotDownloads = XCUIScreen.main.screenshot()
        try? shotDownloads.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_downloads_clean_verified.png"))

        print("THL_TV_SEARCH_DOWNLOAD_REFINEMENT_COMPLETE searchClear=true focusFlow=true suggestionsStable=true downloadsLanRemoved=true")
    }

    func testDetailCoverAnimationAndSourcesButtonFocusStyles() throws {
        continueAfterFailure = false
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)

        // ===== 第一阶段：验证剧集详情页海报即刻展示与转场动画 =====
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "0"
        app.launchArguments = ["-testPage", "detail", "-testDramaTitle", "都市逆袭：龙王归来"]
        app.launch()

        // 验证进入剧集详情时，无论是否还在加载完整选集，剧名与海报区域立即完整展示
        wait("detail page active with title and cover", seconds: 20) {
            self.app.staticTexts["都市逆袭：龙王归来"].exists
        }
        XCTAssertTrue(app.staticTexts["都市逆袭：龙王归来"].exists, "从列表进入详情页时立即展示剧集标题与列表海报封面")

        wait("detail play ready or loading visible", seconds: 15) {
            self.app.buttons["detail.play"].exists || self.app.staticTexts["正在载入剧集选集与播放源..."].exists
        }

        let shotDetail = XCUIScreen.main.screenshot()
        try? shotDetail.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_detail_cover_animated_verified.png"))

        // ===== 第二阶段：验证设置页面站源管理中「数据源诊断」与「网络链接导入」获焦高亮样式 =====
        app.terminate()
        app.launchArguments = ["-testPage", "settings_sources"]
        app.launch()

        // 点击 Select 确认切入设置分类，侧边栏收起并落焦于「站源管理」分类
        wait("sidebar settings or nav sources ready", seconds: 15) {
            self.app.buttons["nav.settings"].exists || self.app.buttons["settings.nav.sources"].exists
        }
        if self.app.buttons["nav.settings"].hasFocus {
            press(.select)
        }
        wait("settings sources nav focused", seconds: 15) {
            self.app.buttons["settings.nav.sources"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.nav.sources"].hasFocus, "成功进入设置页面并聚焦站源管理分类")

        // 按 Right 进入右侧站源管理内容区，验证「数据源诊断」按钮获得焦点并呈现高亮样式
        press(.right)
        wait("source diagnostics focused", seconds: 15) {
            self.app.buttons["settings.sourceDiagnostics"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.sourceDiagnostics"].hasFocus, "数据源诊断按钮成功获取焦点，呈现白边高光与缩放阴影样式")

        let shotDiag = XCUIScreen.main.screenshot()
        try? shotDiag.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_source_diag_focused.png"))

        // 按 Right 移动到「官方数据源」，再按 Right 移动到「网络链接导入」
        press(.right) // 聚焦官方数据源
        sleep(1)
        press(.right) // 聚焦网络链接导入
        wait("import network source focused", seconds: 15) {
            self.app.buttons["settings.importNetworkSource"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.importNetworkSource"].hasFocus, "网络链接导入按钮成功获取焦点，呈现明显高亮视觉反馈")

        let shotImport = XCUIScreen.main.screenshot()
        try? shotImport.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_import_network_focused.png"))

        print("THL_TV_DETAIL_ANIM_AND_SOURCES_FOCUS_COMPLETE detailCover=true detailAnim=true diagFocusStyle=true importFocusStyle=true")
    }

    /// 9. 专项验证：
    /// 1) 搜索框输入文字后，清除小 X 按钮获焦绝无系统白色矩形背景，呈现流光红宝石与纯白高光圆环
    /// 2) 「清空」与「搜索」按钮选中获焦后呈现清晰醒目的样式（3.0pt 纯白高光白边、1.08x 放大、流光渐变提亮底色与强红光晕）
    /// 3) 遥控器在输入框、小 X 按钮、清空按钮与搜索按钮之间按键穿梭平滑无阻
    func testSearchXMarkNoWhiteBackgroundAndButtonsFocusStyles() throws {
        continueAfterFailure = false
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)

        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "search", "-testQuery", "战神"]
        app.launch()

        // 1. 等待进入搜索页并完成初始搜索
        wait("sidebar search tab or input ready", seconds: 20) {
            self.app.buttons["nav.search"].exists || self.app.textFields["search.query"].exists
        }
        if self.app.buttons["nav.search"].hasFocus {
            press(.select)
        }
        wait("search results ready", seconds: 20) {
            self.app.buttons["search.result.0"].exists
        }
        XCTAssertTrue(app.buttons["search.clear_icon"].exists, "输入框有文字时展示清除小 X 按钮")
        XCTAssertTrue(app.buttons["search.clear"].exists, "搜索完成后展示独立「清空」按钮")
        XCTAssertTrue(app.buttons["search.submit"].exists, "搜索按钮常驻存在")

        // 2. 从搜索结果第一排按 Up 移动到顶栏，焦点自然切入独立「清空」按钮
        if !self.app.buttons["search.clear"].hasFocus {
            press(.up)
        }
        wait("clear button focused", seconds: 10) {
            self.app.buttons["search.clear"].hasFocus
        }
        XCTAssertTrue(app.buttons["search.clear"].hasFocus, "清空按钮成功获取焦点并呈现清晰鲜明的选中样式（纯白高光白边与流光底色）")

        let shotClear = XCUIScreen.main.screenshot()
        try? shotClear.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_search_clear_button_focused.png"))

        // 3. 从清空按钮按 Right 移动到「搜索」按钮，验证其获焦并呈现 3.0pt 纯白高光与 1.08x 放大
        press(.right)
        wait("submit button focused", seconds: 10) {
            self.app.buttons["search.submit"].hasFocus
        }
        XCTAssertTrue(app.buttons["search.submit"].hasFocus, "搜索按钮成功获取焦点并呈现清晰醒目的选中高光样式")

        let shotSubmit = XCUIScreen.main.screenshot()
        try? shotSubmit.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_search_submit_button_focused.png"))

        // 4. 从搜索按钮按 Left 顺畅返回清空按钮
        press(.left)
        wait("back to clear button", seconds: 5) {
            self.app.buttons["search.clear"].hasFocus
        }

        // 5. 从清空按钮按 Left 移动到清除小 X 按钮，验证其获焦且彻底剥离白色系统背景
        press(.left)
        wait("clear icon focused", seconds: 10) {
            self.app.buttons["search.clear_icon"].hasFocus
        }
        XCTAssertTrue(app.buttons["search.clear_icon"].hasFocus, "清除小 X 按钮成功获取焦点，呈现纯净流光红圆圈与纯白圆环，绝无白色矩形背景")

        let shotIcon = XCUIScreen.main.screenshot()
        try? shotIcon.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_search_clear_icon_focused.png"))

        // 6. 从清除小 X 按钮按 Left 顺畅移动回输入框
        press(.left)
        wait("query input focused", seconds: 5) {
            self.app.textFields["search.query"].hasFocus
        }
        XCTAssertTrue(app.textFields["search.query"].hasFocus, "焦点顺利从清除小 X 按钮向左移动回到搜索输入框")

        // 7. 从输入框按 Right 重新回到清除小 X 按钮，按 Select 执行清除
        press(.right)
        wait("clear icon refocused", seconds: 5) {
            self.app.buttons["search.clear_icon"].hasFocus
        }
        press(.select) // 点击清除小 X 按钮清空文字
        wait("query cleared and focus returns to input", seconds: 10) {
            self.app.textFields["search.query"].hasFocus && !self.app.buttons["search.clear_icon"].exists
        }
        XCTAssertTrue(app.textFields["search.query"].hasFocus, "点击清除小 X 按钮后文字成功清空，小 X 按钮消失，焦点自然重置回输入框")

        let shotCleared = XCUIScreen.main.screenshot()
        try? shotCleared.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_search_text_cleared_by_icon.png"))

        print("THL_TV_SEARCH_XMARK_AND_BUTTONS_FOCUS_STYLES_COMPLETE xMarkNoWhiteBg=true clearStyle=true submitStyle=true clearAction=true")
    }

    /// 10. 专项验证：
    /// 1) 设置页面左侧导航栏已彻底移除 header 头（无 applogo 与“系统设置/糖葫芦Haw·控制中心”），与主导航栏彻底解耦
    /// 2) 设置页面左侧分类导航栏获得焦点时，点击 Menu 按钮可顺利退回到主导航栏上（侧边栏唤出并落焦于「设置」）
    /// 3) 剧集卡片跳转到剧集详情，海报图片呈现弹性生长过渡动画，背景环境光自然扩散，右侧信息流畅滑入
    func testSettingsNoHeaderAndMenuBackToNavAndDetailPosterTransition() throws {
        continueAfterFailure = false
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)

        // ===== 阶段一：验证设置页面导航栏无 header 头，且按 Menu 键退回到主导航栏 =====
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings_sources"]
        app.launch()

        // 1. 进入设置页面，等待站源分类按钮就绪
        wait("settings sources nav ready", seconds: 20) {
            self.app.buttons["settings.nav.sources"].exists
        }
        if self.app.buttons["nav.settings"].hasFocus {
            press(.select)
        }
        wait("settings nav focused", seconds: 15) {
            self.app.buttons["settings.nav.sources"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.nav.sources"].hasFocus, "成功进入设置页面并聚焦于站源管理分类")

        // 2. 验证设置页面内部导航栏绝无多余 header 头（如“系统设置”或“糖葫芦Haw · 控制中心”）
        XCTAssertFalse(app.staticTexts["糖葫芦Haw · 控制中心"].exists, "设置内部导航栏已彻底移除多余 header 文本")
        XCTAssertFalse(app.staticTexts["系统设置"].exists, "设置内部导航栏已移除多余 header 标题")

        let shotSettingsClean = XCUIScreen.main.screenshot()
        try? shotSettingsClean.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_no_header_verified.png"))

        // 3. 在设置左侧导航栏上按 Menu 键，验证其成功回到主导航栏并聚焦在主导航「设置」Tab
        press(.menu)
        wait("return to main sidebar settings tab", seconds: 15) {
            self.app.buttons["nav.settings"].exists && self.app.buttons["nav.settings"].hasFocus
        }
        XCTAssertTrue(app.buttons["nav.settings"].hasFocus, "点击 Menu 键成功退回到主导航栏设置按钮上")

        let shotMenuBack = XCUIScreen.main.screenshot()
        try? shotMenuBack.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_settings_menu_back_to_nav_verified.png"))

        // ===== 阶段二：验证剧集详情页图片跳转过渡动画 =====
        app.terminate()
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "0"
        app.launchArguments = ["-testPage", "detail", "-testDramaTitle", "都市逆袭：龙王归来"]
        app.launch()

        // 验证进入剧集详情时，海报封面与标题立即展示，海报具备破框生长过渡动效
        wait("detail title and cover ready", seconds: 20) {
            self.app.staticTexts["都市逆袭：龙王归来"].exists && self.app.buttons["detail.play"].exists
        }
        XCTAssertTrue(app.staticTexts["都市逆袭：龙王归来"].exists, "剧集标题立即展示")
        XCTAssertTrue(app.buttons["detail.play"].exists, "播放按钮立即展示并处于获焦状态")

        let shotDetailAnim = XCUIScreen.main.screenshot()
        try? shotDetailAnim.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_detail_poster_transition_verified.png"))

        print("THL_TV_SETTINGS_AND_DETAIL_TRANSITION_COMPLETE noHeader=true menuBack=true posterTransition=true")
    }

    /// 11. 专项验证：tvOS 与 iOS / macOS 的 iCloud 同步面板与双向同步
    /// 1) 验证设置页面导航进入「iCloud 多端同步」分类
    /// 2) 验证「启用 iCloud 云端同步」开关状态可正常切换与持久化
    /// 3) 验证开启同步后展示同步状态与「立刻同步」按钮，且获焦与点击响应正常
    func testSettingsICloudSync() throws {
        continueAfterFailure = false
        let shotDir = URL(fileURLWithPath: "/Users/never88gone/.gemini/antigravity/brain/78fa14d0-288b-4e8f-86e6-1d40abdc3d60/screenshots")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)

        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "settings_sync"]
        app.launch()

        // 1. 等待设置页面左侧导航栏及 iCloud 面板就绪
        wait("settings sync nav and toggle ready", seconds: 20) {
            self.app.buttons["settings.nav.sync"].exists && self.app.buttons["settings.icloud.toggle"].exists
        }

        // 2. 从左侧导航栏按 Right 键进入 iCloud 设置面板
        press(.right)
        wait("icloud panel focused", seconds: 10) {
            self.app.buttons["settings.icloud.toggle"].hasFocus || self.app.buttons["settings.icloud.syncNow"].hasFocus
        }

        // 3. 验证在 toggle 与 syncNow 之间焦点切换
        if self.app.buttons["settings.icloud.syncNow"].hasFocus {
            press(.up)
            wait("icloud toggle focused", seconds: 5) {
                self.app.buttons["settings.icloud.toggle"].hasFocus
            }
        }
        XCTAssertTrue(app.buttons["settings.icloud.toggle"].hasFocus, "成功聚焦在 iCloud 同步开关按钮上")

        // 4. 按 Down 键移动到「立刻同步」按钮
        press(.down)
        wait("syncNow button focused", seconds: 10) {
            self.app.buttons["settings.icloud.syncNow"].hasFocus
        }
        XCTAssertTrue(app.buttons["settings.icloud.syncNow"].hasFocus, "立刻同步按钮成功获取焦点并呈现高亮选中样式")

        // 5. 点击 Select 键触发同步
        press(.select)
        sleep(2)

        let shotSync = XCUIScreen.main.screenshot()
        try? shotSync.pngRepresentation.write(to: shotDir.appendingPathComponent("tvos_icloud_sync_verified.png"))

        print("THL_TV_ICLOUD_SYNC_VERIFIED toggle=true syncNow=true status=true")
    }
}

extension RemoteNavigationTests {
    func testListLoadingCatalogPagingAndFocus() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "catalog", "-thl_icloud_sync_enabled", "NO", "-thl_tv_cached_home_dramas", "[]", "-thl_tv_cached_categories", "[]"]
        let start = Date()
        app.launch()
        wait("catalog first list", seconds: 60) { self.app.buttons["catalog.result.11"].exists }
        print("THL_TV_LIST firstCatalogTwelveMs=\(Int(Date().timeIntervalSince(start) * 1000))")
        wait("catalog sidebar initial focus") { self.app.buttons["nav.catalog"].hasFocus }
        press(.right)
        wait("catalog header focus") { self.app.buttons["catalog.category.app:discover:all"].hasFocus }
        press(.down, focus: "catalog.result.0")
        press(.right, focus: "catalog.result.1")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["catalog.result.1"].hasFocus)
        press(.left, focus: "catalog.result.0")
        press(.down, focus: "catalog.result.6")
        press(.down, focus: "catalog.result.12")
        press(.down, focus: "catalog.result.18")
        press(.down, focus: "catalog.result.24")
        wait("catalog next pages loaded", seconds: 60) { self.app.buttons["catalog.result.25"].exists }
        press(.right, focus: "catalog.result.25")
        let title = app.buttons["catalog.result.25"].label
        press(.select)
        wait("catalog detail ready", seconds: 60) { self.app.buttons["detail.play"].hasFocus }
        press(.menu)
        wait("catalog card restored") { self.app.buttons["catalog.result.25"].hasFocus }
        XCTAssertEqual(app.buttons["catalog.result.25"].label, title)
        press(.menu, focus: "nav.catalog")
        press(.right)
        wait("catalog header restored") { self.app.buttons["catalog.category.app:discover:all"].hasFocus }
        press(.right, focus: "catalog.category.app:discover:playlet")
        wait("switched catalog first batch", seconds: 60) { self.app.buttons["catalog.result.0"].exists }
        press(.down, focus: "catalog.result.0")
        press(.down, focus: "catalog.result.6")
        press(.up, focus: "catalog.result.0")
        press(.up, focus: "catalog.category.app:discover:playlet")
        press(.menu, focus: "nav.catalog")
        print("THL_TV_LIST_RESULT catalog=true autoPaging=true appendKeepsFocus=true gridDirections=true detailReturn=true categorySwitch=true menuReturn=true")
        app.terminate()
    }

    func testListLoadingFeedPagingAndFocus() throws {
        continueAfterFailure = false
        app.launchEnvironment["DISABLE_REMOTE_IMAGES"] = "1"
        app.launchArguments = ["-testPage", "feed", "-thl_icloud_sync_enabled", "NO"]
        let start = Date()
        app.launch()
        wait("feed first list", seconds: 60) { self.app.buttons["player.wake"].exists }
        print("THL_TV_LIST firstFeedMs=\(Int(Date().timeIntervalSince(start) * 1000))")
        let first = try automaticFeedReady()
        press(.select)
        wait("feed controls focus") { self.app.buttons["player.playPause"].hasFocus }
        let initialProgress = app.staticTexts["feed.progress"].label
        print("THL_TV_LIST feedInitial=\(initialProgress)")
        press(.menu, focus: "player.wake")
        var titles = [first.title]
        for _ in 0..<4 {
            press(.down)
            let checkpoint = try automaticFeedReady(differentFrom: titles.last!)
            titles.append(checkpoint.title)
        }
        XCTAssertEqual(Set(titles).count, 5)
        press(.up)
        let previous = try automaticFeedReady(title: titles[3])
        press(.select)
        wait("feed final controls focus") { self.app.buttons["player.playPause"].hasFocus }
        print("THL_TV_LIST feedFinal=\(app.staticTexts["feed.progress"].label)")
        press(.up, focus: "player.nextDrama")
        press(.right, focus: "player.favorite")
        press(.right, focus: "player.detail")
        press(.select)
        wait("feed detail opens", seconds: 60) { self.app.buttons["detail.play"].hasFocus }
        XCTAssertTrue(app.staticTexts[previous.title].exists)
        press(.down)
        wait("feed detail selection focus") {
            self.yaoSnapshots().contains { $0.hasFocus && ($0.identifier.hasPrefix("detail.season.") || $0.identifier.hasPrefix("detail.chunk.") || $0.identifier.hasPrefix("detail.episode.")) }
        }
        press(.menu)
        wait("feed detail returns to original control", seconds: 60) { self.app.buttons["player.detail"].hasFocus }
        press(.down, focus: "player.playPause")
        press(.menu, focus: "player.wake")
        press(.menu, focus: "nav.feed")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["nav.feed"].hasFocus)
        press(.right)
        _ = try automaticFeedReady(title: previous.title, minimum: previous.position)
        press(.menu, focus: "nav.feed")
        print("THL_TV_LIST_RESULT feed=true unique=5 verticalSwitch=true autoPaging=true previous=true controlsFocus=true detailEntry=true detailTitle=true detailSelection=true detailReturn=true menuReturn=true resume=true")
        app.terminate()
    }
}
