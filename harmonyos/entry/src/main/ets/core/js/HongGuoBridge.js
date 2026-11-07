import './env.js';
import spider from './sources/hongguo.js';
import hilog from '@ohos.hilog';

const TAG = 'HongGuoBridge';
const DOMAIN = 0x0000;

let isReady = false;

export function bridgeInit() {
  if (isReady) return true;
  try {
    if (spider) {
      // 允许使用 hongguo.js 内置的 Gorgon/Ladon/Argus 算法进行直连签名
      globalThis.__hongguoLocalSign = function() {
        return null;
      };

      if (typeof spider.init === 'function') {
        spider.init();
      }
      isReady = true;
      hilog.info(DOMAIN, TAG, 'HongGuo spider statically loaded and initialized successfully!');
      return true;
    }
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'bridgeInit error: %{public}s', JSON.stringify(err));
  }
  return false;
}

export function isBridgeReady() {
  if (!isReady && spider) {
    bridgeInit();
  }
  return isReady;
}

export async function bridgeHome(filter) {
  if (!isBridgeReady()) return { class: [], filters: {} };
  try {
    return await spider.home(!!filter);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgeHome error: %{public}s', JSON.stringify(e));
    return { class: [], filters: {} };
  }
}

export async function bridgeCategory(tid, page, filter, extend) {
  if (!isBridgeReady()) return { list: [], page: page || 1, pagecount: 1 };
  try {
    return await spider.category(tid, page, !!filter, extend || {});
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgeCategory error: %{public}s', JSON.stringify(e));
    return { list: [], page: page || 1, pagecount: 1 };
  }
}

export async function bridgeSearch(word, quick, page) {
  if (!isBridgeReady()) return { list: [], page: page || 1, pagecount: 1 };
  try {
    if (typeof spider.search === 'function') {
      return await spider.search(word, !!quick, page || 1);
    }
    return { list: [], page: page || 1, pagecount: 1 };
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgeSearch error: %{public}s', JSON.stringify(e));
    return { list: [], page: page || 1, pagecount: 1 };
  }
}

export async function bridgeDetail(id) {
  if (!isBridgeReady()) return null;
  try {
    return await spider.detail(String(id));
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgeDetail error: %{public}s', JSON.stringify(e));
    return null;
  }
}

export async function bridgePlay(flag, id, flags) {
  if (!isBridgeReady()) return { url: '', parse: 0, header: {} };
  try {
    const res = await spider.play(flag, id, flags || []);
    if (!res || !res.url) {
      hilog.warn(DOMAIN, TAG, 'bridgePlay returned no url, res: %{public}s', JSON.stringify(res));
    }
    return res;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgePlay error: %{public}s', JSON.stringify(e));
    return { url: '', parse: 0, header: {} };
  }
}

export async function bridgeFeed(page, session) {
  if (!isBridgeReady()) return { list: [], hasMore: false };
  try {
    if (typeof spider.feed === 'function') {
      return await spider.feed(page || 1, session || '');
    }
    return { list: [], hasMore: false };
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgeFeed error: %{public}s', JSON.stringify(e));
    return { list: [], hasMore: false };
  }
}

export async function bridgeRankingBoards() {
  if (!isBridgeReady()) return [];
  try {
    if (typeof spider.rankingBoards === 'function') {
      const res = await spider.rankingBoards();
      return (res && res.items) || [];
    }
    return [];
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgeRankingBoards error: %{public}s', JSON.stringify(e));
    return [];
  }
}

export async function bridgeRankings(board, page) {
  if (!isBridgeReady()) return { list: [], page: page || 1 };
  try {
    if (typeof spider.rankings === 'function') {
      return await spider.rankings(board, page || 1);
    }
    return { list: [], page: page || 1 };
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'bridgeRankings error: %{public}s', JSON.stringify(e));
    return { list: [], page: page || 1 };
  }
}

export async function bridgeSuggestions(query) {
  if (!isBridgeReady()) return [];
  try {
    if (typeof spider.suggestions === 'function') {
      const res = await spider.suggestions(query);
      return (res && res.items) || [];
    }
    return [];
  } catch (e) {
    return [];
  }
}
