import Foundation
import Combine
import UIKit

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var selectedTab: LibraryTab = .history
    @Published public var selectedFollowFilter: FollowState = .watching
    @Published public var searchQuery: String = ""

    public enum LibraryTab: String, CaseIterable, Identifiable {
        case history = "history"
        case follows = "follows"

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .history: return "最近观看"
            case .follows: return "我的追剧"
            }
        }
    }

    private let store: LocalStore
    private var cancellables = Set<AnyCancellable>()

    public init(store: LocalStore = .shared) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : store.currentSourceId
        return src.isEmpty ? "hongguo" : src
    }

    public var historyList: [WatchEntry] {
        let target = currentSource.lowercased()
        let sourceMatched = store.history.filter { $0.drama.source.lowercased() == target }
        guard !searchQuery.isEmpty else { return sourceMatched }
        return sourceMatched.filter { $0.drama.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var followedList: [Drama] {
        let target = currentSource.lowercased()
        let sourceMatched = store.followedDramas.filter { $0.source.lowercased() == target }
        let filtered: [Drama]
        if selectedFollowFilter == .none {
            filtered = sourceMatched
        } else {
            filtered = sourceMatched.filter { store.followState(for: $0.id) == selectedFollowFilter }
        }
        guard !searchQuery.isEmpty else { return filtered }
        return filtered.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public func clearHistory() {
        store.clearHistory(for: currentSource)
    }

    public func removeHistory(dramaId: String) {
        store.removeHistory(dramaId: dramaId)
    }
}

@MainActor
public final class DownloadsViewModel: ObservableObject {
    private let downloadService: DownloadService
    private var cancellables = Set<AnyCancellable>()

    public init(downloadService: DownloadService = .shared) {
        self.downloadService = downloadService
        downloadService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : LocalStore.shared.currentSourceId
        return src
    }

    public var jobs: [DownloadJob] {
        guard !currentSource.isEmpty else { return [] }
        let target = currentSource.lowercased()
        return downloadService.jobs.filter { $0.drama.source.lowercased() == target }
    }

    public func pauseJob(_ id: String) {
        downloadService.pauseJob(id: id)
    }

    public func resumeJob(_ id: String) {
        downloadService.startJob(id: id)
    }

    public func deleteJob(_ id: String) {
        downloadService.deleteJob(id: id)
    }

    public func resumeAll() {
        downloadService.resumeAll()
    }

    public func clearAll() {
        let currentJobs = jobs
        for job in currentJobs {
            downloadService.deleteJob(id: job.id)
        }
    }
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var unlockPassword = ""
    @Published public var unlockError: String?
    @Published public var proxyMode: String = "direct"
    @Published public var proxyUrl: String = ""
    @Published public var concurrency: Int = 3
    @Published public var intervalMs: Int = 250
    @Published public var keepScreenOn: Bool = true
    @Published public var currentSourceId: String = ""

    private let store: LocalStore
    private var cancellables = Set<AnyCancellable>()

    public init(store: LocalStore = .shared) {
        self.store = store
        self.currentSourceId = store.currentSourceId
        self.proxyMode = store.resourceSettings.proxyMode
        self.proxyUrl = store.resourceSettings.proxyUrl
        self.concurrency = store.resourceSettings.catalogConcurrency
        self.intervalMs = store.resourceSettings.catalogIntervalMs
        self.keepScreenOn = store.resourceSettings.keepScreenOn

        store.$currentSourceId
            .sink { [weak self] newId in
                self?.currentSourceId = newId
            }
            .store(in: &cancellables)

        store.$unlockedSources
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: SourceSite {
        SourceSite.byId(currentSourceId)
    }

    public var availableSources: [SourceSite] {
        SourceSite.visibleValues(unlocked: store.unlockedSources)
    }

    public func selectSource(_ id: String) {
        store.setSource(id)
        currentSourceId = id
    }

    public var isUnlocked: Bool {
        store.unlockedSources
    }

    public func attemptUnlock() -> Bool {
        unlockError = nil
        let success = store.unlockSources(password: unlockPassword)
        if !success {
            unlockError = "密码不正确，请重新输入"
        } else {
            unlockPassword = ""
        }
        return success
    }

    public func lockSources() {
        store.lockSources()
    }

    public func saveSettings() {
        var s = store.resourceSettings
        s.proxyMode = proxyMode
        s.proxyUrl = proxyUrl
        s.catalogConcurrency = concurrency
        s.catalogIntervalMs = intervalMs
        s.keepScreenOn = keepScreenOn
        store.resourceSettings = s
        
        // 立即应用 Wakelock 状态
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = s.keepScreenOn
        }
    }
}

@MainActor
public final class JSSourceService: ObservableObject {
    public static let shared = JSSourceService()

    @Published public private(set) var sources: [[String: Any]] = []
    @Published public private(set) var activeSourceId: String = ""

    private let repository = NativeRepository.shared

    private init() {}

    public func initialize() async {
        _ = try? await repository.jsSourceScan()
        await refresh()
    }

    public func refresh() async {
        if let list = try? await repository.jsSourceList() {
            self.sources = list
        }
        if self.sources.isEmpty {
            self.activeSourceId = ""
            LocalStore.shared.setSource("")
            return
        }
        if let active = try? await repository.jsSourceGetActive(), !active.isEmpty {
            if self.sources.contains(where: { ($0["id"] as? String) == active }) {
                self.activeSourceId = active
                LocalStore.shared.setSource(active)
            } else if let firstId = self.sources.first?["id"] as? String {
                self.activeSourceId = firstId
                LocalStore.shared.setSource(firstId)
            } else {
                self.activeSourceId = ""
                LocalStore.shared.setSource("")
            }
        } else if let firstId = self.sources.first?["id"] as? String {
            self.activeSourceId = firstId
            LocalStore.shared.setSource(firstId)
        } else {
            self.activeSourceId = ""
            LocalStore.shared.setSource("")
        }
    }

    public func setActiveSource(_ id: String) async {
        let ok = (try? await repository.jsSourceSetActive(sourceId: id)) ?? false
        if ok {
            self.activeSourceId = id
            LocalStore.shared.setSource(id)
            await refresh()
        }
    }

    public func importFromURL(_ urlString: String) async throws -> Bool {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "JSSource", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的 URL 链接"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw NSError(domain: "JSSource", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法下载脚本文件：网络错误"])
        }
        
        guard let script = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JSSource", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法解析脚本文件：非 UTF8 编码"])
        }
        
        let fileName = url.lastPathComponent.isEmpty ? "imported_plugin.js" : url.lastPathComponent
        let ok = try await repository.jsSourceSaveAndLoad(script: script, fileName: fileName)
        
        if ok {
            await refresh()
            // 如果只有这一个插件，自动激活它
            if sources.count == 1, let firstId = sources.first?["id"] as? String {
                await setActiveSource(firstId)
            }
        }
        return ok
    }

    public func removeSource(_ id: String) async {
        _ = try? await repository.jsSourceRemove(sourceId: id)
        await refresh()
    }
}
public let BuiltInHongguoJSContent = """
/**
 * 红果免费短剧 数据源扩展 (hongguo.js)
 * 适配标准 JS 数据源协议规范 v1.0.1
 */

const meta = {
  id: "hongguo",
  name: "红果免费短剧",
  version: "1.0.1",
  description: "官方首发短剧源，包含海量都市爽文、战神回归、现代甜宠、古装穿越等优质短剧",
  author: "真果鉴团队",
  type: "video",
  icon: "",
  features: ["search", "suggestions", "categories"]
};

const BASE_URL = "https://hongguoduanju.com";
const USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

function getCategories() {
  return [
    { id: "real-drama", name: "真人剧" },
    { id: "comic-drama", name: "漫剧" },
    { id: "ai-drama", name: "AI剧" },
    { id: "comic", name: "动漫" }
  ];
}

function cleanText(text) {
  if (!text) return "";
  return text.replace(/<[^>]+>/g, "").trim();
}

function parseJsonFromHtml(body) {
  const match = body.match(/<script[^>]*id="__NEXT_DATA__"[^>]*>([\\s\\S]*?)<\\/script>/) ||
                body.match(/<script[^>]*>window\\.__INITIAL_STATE__\\s*=\\s*(\\{[\\s\\S]*?\\});<\\/script>/) ||
                body.match(/window\\.__ROUTER_DATA__\\s*=\\s*(\\{[\\s\\S]*?\\});/);
  if (match && match[1]) {
    try {
      return JSON.parse(match[1]);
    } catch (e) {
      console.warn("JSON parse error:", e);
    }
  }
  return null;
}

function getCatalog(category, page, pageSize) {
  page = page || 1;
  const route = category || "real-drama";
  const url = BASE_URL + "/category/" + route + "?page=" + page;

  const resp = fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      "Referer": BASE_URL + "/"
    }
  });

  if (resp.status !== 200) {
    return { items: [], total: 0, hasMore: false };
  }

  const items = [];
  const body = resp.body;

  // 1. 尝试从内联数据提取
  const routerData = parseJsonFromHtml(body);
  if (routerData) {
    let list = [];
    if (routerData.props && routerData.props.pageProps && routerData.props.pageProps.recommendList) {
      list = routerData.props.pageProps.recommendList;
    } else if (routerData.loaderData) {
      const keys = Object.keys(routerData.loaderData);
      for (let i = 0; i < keys.length; i++) {
        const item = routerData.loaderData[keys[i]];
        if (item && item.recommendList) {
          list = item.recommendList;
          break;
        }
      }
    }

    if (Array.isArray(list) && list.length > 0) {
      for (let i = 0; i < list.length; i++) {
        const dr = list[i];
        const id = dr.series_id || dr.book_id || dr.id;
        if (!id) continue;
        items.push({
          id: String(id),
          title: cleanText(dr.title || dr.series_title || dr.book_name),
          cover: dr.cover || dr.thumb_url || dr.cover_url || "",
          desc: cleanText(dr.intro || dr.abstract || dr.desc),
          episodes: Number(dr.episode_cnt || dr.total_episode || 0),
          category: route,
          tags: dr.tags || []
        });
      }
      return { items: items, total: items.length, hasMore: items.length >= 20 };
    }
  }

  // 2. 备用从 HTML 节点提取
  const doc = html.parse(body);
  const cards = doc.find(".drama-card, .book-item, a[href*='/detail/']");
  for (let i = 0; i < cards.length; i++) {
    const el = cards.eq(i);
    const href = el.attr("href") || "";
    const idMatch = href.match(/\\/detail\\/(\\d+)/);
    if (!idMatch) continue;
    const id = idMatch[1];
    const title = cleanText(el.find(".title, h3, .name").text());
    const cover = el.find("img").attr("src") || el.find("img").attr("data-src") || "";
    const desc = cleanText(el.find(".desc, .intro, p").text());

    items.push({
      id: id,
      title: title,
      cover: cover,
      desc: desc,
      category: route,
      tags: []
    });
  }

  return {
    items: items,
    total: items.length,
    hasMore: items.length >= 10
  };
}

function getSuggestions(query) {
  if (!query) return [];
  const url = BASE_URL + "/incent_resource/suggestion?app_id=8662&query=" + encodeURIComponent(query) + "&count=15";
  const resp = fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      "Referer": BASE_URL + "/"
    }
  });

  if (resp.status !== 200) return [];
  try {
    const json = JSON.parse(resp.body);
    const list = json.suggest_list || (json.data && json.data.suggest_list) || [];
    const suggestions = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].name) {
        suggestions.push(list[i].name);
      }
    }
    return suggestions;
  } catch (e) {
    return [];
  }
}

function search(query, page) {
  if (!query) return [];
  const url = BASE_URL + "/incent_resource/suggestion?app_id=8662&query=" + encodeURIComponent(query) + "&count=30";
  const resp = fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      "Referer": BASE_URL + "/"
    }
  });

  if (resp.status !== 200) return [];
  try {
    const json = JSON.parse(resp.body);
    const list = json.suggest_list || (json.data && json.data.suggest_list) || [];
    const dramas = [];
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      const videoData = item.video_data || {};
      const id = videoData.series_id_str || videoData.series_id;
      if (id) {
        dramas.push({
          id: String(id),
          title: cleanText(item.name || videoData.title || item.keyword),
          cover: videoData.cover_url || videoData.cover || "",
          desc: cleanText(videoData.intro || videoData.abstract || ""),
          episodes: Number(videoData.episode_cnt || 0),
          category: "短剧",
          tags: []
        });
      }
    }
    return dramas;
  } catch (e) {
    return [];
  }
}

function getDetail(id) {
  const url = BASE_URL + "/detail/" + id;
  const resp = fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      "Referer": BASE_URL + "/"
    }
  });

  if (resp.status !== 200) return null;
  const body = resp.body;
  const routerData = parseJsonFromHtml(body);

  if (routerData) {
    let detailData = null;
    if (routerData.props && routerData.props.pageProps && routerData.props.pageProps.videoDetail) {
      detailData = routerData.props.pageProps.videoDetail;
    } else if (routerData.loaderData) {
      const keys = Object.keys(routerData.loaderData);
      for (let i = 0; i < keys.length; i++) {
        const item = routerData.loaderData[keys[i]];
        if (item && (item.videoDetail || item.series_info)) {
          detailData = item.videoDetail || item.series_info;
          break;
        }
      }
    }

    if (detailData) {
      const title = detailData.title || detailData.series_title || "";
      const cover = detailData.cover || detailData.cover_url || "";
      const desc = detailData.intro || detailData.abstract || "";
      const rawEps = detailData.episode_list || detailData.episodes || [];
      const episodes = [];

      for (let i = 0; i < rawEps.length; i++) {
        const ep = rawEps[i];
        episodes.push({
          id: String(ep.episode_id || ep.id || (i + 1)),
          title: ep.title || ("第 " + (i + 1) + " 集"),
          index: i + 1,
          url: ep.video_id || ep.item_id || ""
        });
      }

      return {
        id: id,
        title: title,
        cover: cover,
        desc: desc,
        episodes: episodes
      };
    }
  }

  // 备用 HTML 解析
  const doc = html.parse(body);
  const title = cleanText(doc.find("h1, .detail-title").text());
  const cover = doc.find(".detail-cover img").attr("src") || "";
  const desc = cleanText(doc.find(".detail-intro, .desc").text());

  return {
    id: id,
    title: title,
    cover: cover,
    desc: desc,
    episodes: []
  };
}

function getPlayUrl(episodeId, extra) {
  // 红果播放地址由底层原生模块支持无水印签名与多清晰度提取
  return null;
}

var source = {
  meta: meta,
  getCategories: getCategories,
  getCatalog: getCatalog,
  search: search,
  getSuggestions: getSuggestions,
  getDetail: getDetail,
  getPlayUrl: getPlayUrl
};


"""
