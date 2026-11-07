import XCTest
@testable import THLRedLook

final class ReleaseNotesTests: XCTestCase {
    func testMarkdownParsing() {
        let sampleMarkdown = """
        # 更新日志

        ## 1.0.0 (2026-11-07)
        - 新增系统级画中画功能
        - 支持画中画连续自动播放

        ## 1.0.0 (2026-11-04)
        * 新增短剧视频本地离线下载
        • 适配 App Store 商店提交规范
        """

        let loader = ReleaseNotesLoader()
        let items = loader.parse(content: sampleMarkdown)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].date, "2026-11-07")
        XCTAssertEqual(items[0].version, "1.0.0")
        XCTAssertTrue(items[0].isLatest)
        XCTAssertEqual(items[0].items.count, 2)
        XCTAssertEqual(items[0].items[0], "新增系统级画中画功能")
        XCTAssertEqual(items[0].items[1], "支持画中画连续自动播放")

        XCTAssertEqual(items[1].date, "2026-11-04")
        XCTAssertFalse(items[1].isLatest)
        XCTAssertEqual(items[1].items.count, 2)
        XCTAssertEqual(items[1].items[0], "新增短剧视频本地离线下载")
        XCTAssertEqual(items[1].items[1], "适配 App Store 商店提交规范")
    }

    func testSortDescendingByDate() {
        // 提供无序的日期输入，验证是否强制按时间倒序排列
        let unorderedMarkdown = """
        ## 1.0.0 (2026-10-24)
        - 初始版本

        ## 1.0.0 (2026-11-07)
        - 最新画中画版本

        ## 1.0.0 (2026-11-04)
        - 离线下载版本
        """

        let loader = ReleaseNotesLoader()
        let items = loader.parse(content: unorderedMarkdown)

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].date, "2026-11-07")
        XCTAssertTrue(items[0].isLatest)
        XCTAssertEqual(items[1].date, "2026-11-04")
        XCTAssertFalse(items[1].isLatest)
        XCTAssertEqual(items[2].date, "2026-10-24")
        XCTAssertFalse(items[2].isLatest)
    }

    func testBulletPointsCleanup() {
        let markdown = """
        ## 1.0.0 (2026-11-07)
        -   前置空格连字符
        * 星号开头的条目
        • 实体圆点条目
        普通无前缀文字行
        """

        let loader = ReleaseNotesLoader()
        let items = loader.parse(content: markdown)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].items.count, 3)
        XCTAssertEqual(items[0].items[0], "前置空格连字符")
        XCTAssertEqual(items[0].items[1], "星号开头的条目")
        XCTAssertEqual(items[0].items[2], "实体圆点条目")
    }

    func testExtractLatestNotesFormat() {
        let sampleMarkdown = """
        ## 1.0.0 (2026-11-07)
        - 功能点 A
        - 功能点 B
        """

        let loader = ReleaseNotesLoader()
        let items = loader.parse(content: sampleMarkdown)
        guard let latest = items.first else {
            XCTFail("解析失败")
            return
        }

        let header = "\(latest.version) (\(latest.date))"
        let formatted = "【\(header) 更新内容】\n" + latest.items.map { "• \($0)" }.joined(separator: "\n")

        XCTAssertTrue(formatted.contains("【1.0.0 (2026-11-07) 更新内容】"))
        XCTAssertTrue(formatted.contains("• 功能点 A"))
        XCTAssertTrue(formatted.contains("• 功能点 B"))
    }

    func testRealReleaseMdFileLoad() {
        let loader = ReleaseNotesLoader.shared
        let items = loader.loadReleaseNotes()

        XCTAssertFalse(items.isEmpty, "必须能够读取到更新日志")
        let first = items[0]
        XCTAssertTrue(first.isLatest)
        XCTAssertTrue(first.items.contains(where: { $0.contains("画中画") }), "最新版本必须包含画中画相关内容")
    }
}
