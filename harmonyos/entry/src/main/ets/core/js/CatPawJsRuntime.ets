import Context from '@ohos.app.ability.common';
import util from '@ohos.util';
import hilog from '@ohos.hilog';
import { DramaItem, DramaDetail, EpisodeInfo, SeasonInfo } from '../../models/Drama';
import { PlayResult } from '../../models/Episode';
import { CategoryItem } from '../../models/Category';
import { Constants } from '../../common/Constants';
import { normalizeCoverUrl } from '../../common/CoverUtils';
import {
  bridgeInit,
  bridgeHome,
  bridgeCategory,
  bridgeSearch,
  bridgeDetail,
  bridgePlay,
  bridgeFeed,
  bridgeRankingBoards,
  bridgeRankings,
  bridgeSuggestions
} from './HongGuoBridge';

const TAG = 'CatPawJsRuntime';
const DOMAIN = 0x0000;

interface RawVodItem {
  vod_id?: string | number;
  id?: string | number;
  vod_name?: string;
  title?: string;
  vod_pic?: string;
  cover?: string;
  coverUrl?: string;
  vod_remarks?: string;
  remarks?: string;
  vod_content?: string;
  intro?: string;
  episode_cnt?: number;
  vod_play_url?: string;
  vod_play_from?: string;
}

interface RawCategoryResponse {
  list?: RawVodItem[];
  page?: number;
  pagecount?: number;
  total?: number;
}

interface RawHomeResponse {
  class?: Array<Record<string, string>>;
  classes?: Array<Record<string, string>>;
}

interface RawPlayResponse {
  url?: string;
  header?: Record<string, string>;
  parse?: number;
  decryptionKey?: string;
  mediaBytes?: number;
}

/**
 * 鸿蒙端 CatPawOpen JS 运行时沙箱桥接器
 * 负责从 rawfile 中加载官方 hongguo.js 并执行站源函数调度
 */
export class CatPawJsRuntime {
  private static instance: CatPawJsRuntime;
  private scriptContent: string = '';
  private isInitialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private appAbilityContext: Context.UIAbilityContext | null = null;

  public static getInstance(): CatPawJsRuntime {
    if (!CatPawJsRuntime.instance) {
      CatPawJsRuntime.instance = new CatPawJsRuntime();
    }
    return CatPawJsRuntime.instance;
  }

  public async init(context?: Context.UIAbilityContext): Promise<void> {
    if (this.isInitialized) return;
    try {
      hilog.info(DOMAIN, TAG, 'Initializing HongGuo spider bridge...');
      const ok = bridgeInit();
      if (ok) {
        this.isInitialized = true;
        hilog.info(DOMAIN, TAG, 'HongGuo spider initialized successfully!');
      } else {
        hilog.error(DOMAIN, TAG, 'Failed to initialize hongguo.js in bridge');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'CatPawJsRuntime init error: %{public}s', JSON.stringify(err));
    }
  }

  private async ensureReady(): Promise<void> {
    if (!this.isInitialized) {
      await this.init();
    }
  }

  /**
   * 获取首页分类列表 (调用 spider.home())
   */
  public async getCategories(): Promise<CategoryItem[]> {
    await this.ensureReady();
    try {
      const homeRes = (await bridgeHome(false)) as RawHomeResponse;
      const rawClasses = homeRes.class || homeRes.classes || [];
      if (Array.isArray(rawClasses) && rawClasses.length > 0) {
        const list: CategoryItem[] = [];
        list.push({ typeId: 'all', typeName: '全部', isSelected: true });
        for (let i = 0; i < rawClasses.length; i++) {
          const c = rawClasses[i];
          const tid = String(c['type_id'] || c['id'] || '');
          const tname = String(c['type_name'] || c['name'] || '');
          if (tid && tname && tid !== 'all') {
            list.push({ typeId: tid, typeName: tname, isSelected: false });
          }
        }
        return list;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getCategories fallback error: %{public}s', JSON.stringify(e));
    }

    return [
      { typeId: 'all', typeName: '全部', isSelected: true },
      { typeId: 'real-drama', typeName: '真人剧', isSelected: false },
      { typeId: 'comic-drama', typeName: '动漫剧', isSelected: false },
      { typeId: 'ai-drama', typeName: 'AI短剧', isSelected: false }
    ];
  }

  /**
   * 分页获取指定分类目录列表 (调用 spider.category(tid, page))
   */
  public async getCategoryList(tid: string, page: number): Promise<DramaItem[]> {
    await this.ensureReady();
    try {
      const res = (await bridgeCategory(tid, page, false, {})) as RawCategoryResponse;
      const rawList = res && res.list ? res.list : [];
      return this.mapRawList(rawList);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getCategoryList error: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /**
   * 搜索短剧 (调用 spider.search(keyword, quick, page))
   */
  public async search(keyword: string, page: number = 1): Promise<DramaItem[]> {
    await this.ensureReady();
    try {
      const res = (await bridgeSearch(keyword, false, page)) as RawCategoryResponse;
      const rawList = res && res.list ? res.list : [];
      return this.mapRawList(rawList);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search error: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /**
   * 获取推荐流列表 (调用 spider.feed)
   */
  public async getFeed(page: number = 1, session: string = ''): Promise<DramaItem[]> {
    await this.ensureReady();
    try {
      const res = (await bridgeFeed(page, session)) as RawCategoryResponse;
      const rawList = res && res.list ? res.list : [];
      if (rawList.length > 0) {
        return this.mapRawList(rawList);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'feed fallback error: %{public}s', JSON.stringify(e));
    }
    // 降级回取真人剧分类
    return await this.getCategoryList('real-drama', page);
  }

  /**
   * 获取剧集详情及选集列表 (调用 spider.detail(id))
   */
  public async getDetail(dramaId: string): Promise<DramaDetail | null> {
    await this.ensureReady();
    try {
      const res = (await bridgeDetail(dramaId)) as Record<string, Object>;
      if (!res) return null;

      let vod: RawVodItem = res as RawVodItem;
      if (res['vod'] && typeof res['vod'] === 'object') {
        vod = res['vod'] as RawVodItem;
      } else if (Array.isArray(res['list']) && (res['list'] as RawVodItem[]).length > 0) {
        vod = (res['list'] as RawVodItem[])[0];
      }

      const id = String(vod.vod_id || vod.id || dramaId);
      const title = String(vod.vod_name || vod.title || '');
      const coverUrl = normalizeCoverUrl(String(vod.vod_pic || vod.cover || vod.coverUrl || ''));
      const remarks = String(vod.vod_remarks || vod.remarks || '');
      const intro = String(vod.vod_content || vod.intro || '');
      const episodes: EpisodeInfo[] = [];

      const playUrlRaw = String(vod.vod_play_url || '');
      if (playUrlRaw.trim()) {
        let line = playUrlRaw.trim();
        if (line.indexOf('$$$') >= 0) {
          line = line.split('$$$')[0];
        }
        const parts = line.split('#');
        for (let i = 0; i < parts.length; i++) {
          const item = parts[i].trim();
          if (!item) continue;
          let epTitle = `第${i + 1}集`;
          let rawUrl = item;
          if (item.indexOf('$') >= 0) {
            const sp = item.split('$');
            epTitle = sp[0].trim() || epTitle;
            rawUrl = sp.slice(1).join('$').trim() || rawUrl;
          }
          episodes.push({
            index: i + 1,
            title: epTitle,
            rawUrl: rawUrl,
            flag: 'hongguo',
            isFree: true
          });
        }
      }

      // 兜底若无明确 vod_play_url 但有集数
      if (episodes.length === 0) {
        const epCnt = typeof vod.episode_cnt === 'number' && vod.episode_cnt > 0 ? vod.episode_cnt : 1;
        for (let i = 1; i <= epCnt; i++) {
          episodes.push({
            index: i,
            title: `第${i}集`,
            rawUrl: String(i),
            flag: 'hongguo',
            isFree: true
          });
        }
      }

      const seasons: SeasonInfo[] = [
        {
          seasonId: '1',
          seasonName: '全季',
          seasonIndex: 1,
          isSelected: true
        }
      ];

      return {
        id: id,
        title: title,
        coverUrl: coverUrl,
        remarks: remarks || `全${episodes.length}集`,
        episodeCount: episodes.length,
        intro: intro,
        source: 'hongguo',
        seasons: seasons,
        episodes: episodes,
        currentSeasonId: '1'
      };
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getDetail error: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  /**
   * 解析单集视频播放流地址 (调用 spider.play(flag, rawUrl))
   */
  public async resolvePlay(flag: string, rawUrl: string): Promise<PlayResult | null> {
    await this.ensureReady();
    try {
      hilog.info(DOMAIN, TAG, 'Resolving playback: flag=%{public}s, rawUrl=%{public}s', flag, rawUrl);
      const res = (await bridgePlay(flag || 'hongguo', rawUrl, [])) as RawPlayResponse;
      if (res && res.url) {
        hilog.info(DOMAIN, TAG, 'Playback resolved successfully, stream url: %{public}s, key=%{public}s', res.url.slice(0, 80), res.decryptionKey ?? 'none');
        return {
          url: res.url,
          headers: res.header || {},
          duration: 0,
          isEncrypted: !!res.decryptionKey,
          decryptionKey: res.decryptionKey || '',
          mediaBytes: res.mediaBytes || 0
        };
      }
      hilog.warn(DOMAIN, TAG, 'Playback resolution returned empty url');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'resolvePlay error: %{public}s', JSON.stringify(e));
    }
    return null;
  }

  private mapRawList(rawList: RawVodItem[]): DramaItem[] {
    const list: DramaItem[] = [];
    for (let i = 0; i < rawList.length; i++) {
      const item = rawList[i];
      const id = String(item.vod_id || item.id || '');
      const title = String(item.vod_name || item.title || '');
      if (!id || !title) continue;

      const rawPic = String(item.vod_pic || item.cover || item.coverUrl || '');
      const coverUrl = normalizeCoverUrl(rawPic);
      const remarks = String(item.vod_remarks || item.remarks || '');
      const intro = String(item.vod_content || item.intro || '');
      const episodeCount = typeof item.episode_cnt === 'number' ? item.episode_cnt : 0;

      list.push({
        id: id,
        title: title,
        coverUrl: coverUrl,
        remarks: remarks || (episodeCount > 0 ? `全${episodeCount}集` : ''),
        intro: intro,
        episodeCount: episodeCount,
        source: 'hongguo'
      });
    }
    return list;
  }
}
