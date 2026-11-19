import Context from '@ohos.app.ability.common';
import util from '@ohos.util';
import hilog from '@ohos.hilog';
import { DramaItem, DramaDetail, EpisodeInfo, SeasonInfo } from '../../models/Drama';
import { PlayResult } from '../../models/Episode';
import { CategoryItem } from '../../models/Category';
import { CommentItem, CommentPage, CommentReplyItem, CommentReplyPage } from '../../models/Comment';
import { LikedVideoItem, LikedVideoPage, AnchorItem, FollowingCreatorsPage, CloudWatchEntry } from '../../models/Account';
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
  bridgeSuggestions,
  bridgeComments,
  bridgeCommentReplies,
  bridgeCreatorWorks,
  bridgeLikedVideos,
  bridgeFollowingCreators,
  bridgeCloudLibrary,
  bridgeCreatorProfile,
  bridgeCreatorFollow
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

export interface RawRankingBoard {
  id: string;
  name: string;
  description: string;
}

export interface RawRankingResult {
  list: DramaItem[];
  page: number;
  hasMore: boolean;
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

  /**
   * 获取排行榜列表 (调用 spider.rankingBoards)
   */
  public async getRankingBoards(): Promise<RawRankingBoard[]> {
    await this.ensureReady();
    try {
      const res = (await bridgeRankingBoards()) as RawRankingBoard[];
      if (Array.isArray(res) && res.length > 0) {
        return res;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getRankingBoards error: %{public}s', JSON.stringify(e));
    }
    const fallback: RawRankingBoard[] = [
      { id: 'hongguo-app:all:ranklist_hot_sc', name: '热播榜', description: '全网观众都在看的火爆短剧' },
      { id: 'hongguo-app:all:ranklist_soar_sc', name: '飙升榜', description: '人气极速上涨好剧' },
      { id: 'hongguo-app:all:ranklist_new_sc', name: '新剧榜', description: '本周新鲜出炉短剧首发' }
    ];
    return fallback;
  }

  /**
   * 分页获取榜单剧集 (调用 spider.rankings)
   */
  public async getRankings(boardId: string, page: number = 1): Promise<RawRankingResult> {
    await this.ensureReady();
    try {
      const res = (await bridgeRankings(boardId, page)) as RawCategoryResponse;
      const rawList = res && res.list ? res.list : [];
      const dramaList = this.mapRawList(rawList);
      const curPage = typeof res.page === 'number' ? res.page : page;
      const pagecount = typeof res.pagecount === 'number' ? res.pagecount : 1;
      const result: RawRankingResult = {
        list: dramaList,
        page: curPage,
        hasMore: curPage < pagecount && dramaList.length > 0
      };
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getRankings error: %{public}s', JSON.stringify(e));
      const fallback: RawRankingResult = { list: [], page: page, hasMore: false };
      return fallback;
    }
  }

  /**
   * 获取短剧评论列表 (对齐 Flutter fetchCommentList)
   */
  public async fetchComments(bookId: string, cursor: string = '', count: number = 20): Promise<CommentPage> {
    try {
      await this.init();
      const res = await bridgeComments(bookId, cursor, count);
      if (res && typeof res === 'object') {
        const rawList: Record<string, Object>[] = Array.isArray(res.list) ? res.list : [];
        const list: CommentItem[] = [];
        for (let i = 0; i < rawList.length; i++) {
          const item = rawList[i];
          list.push({
            id: String(item['id'] || ''),
            text: String(item['text'] || ''),
            userName: String(item['userName'] || '红果用户'),
            userAvatar: String(item['userAvatar'] || ''),
            userId: String(item['userId'] || ''),
            createTime: Number(item['createTime'] || 0),
            diggCount: Number(item['diggCount'] || 0),
            replyCount: Number(item['replyCount'] || 0)
          });
        }
        return {
          total: Number(res.total || 0),
          hasMore: Boolean(res.hasMore),
          cursor: String(res.cursor || ''),
          list: list
        };
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchComments error: %{public}s', JSON.stringify(e));
    }
    return { total: 0, hasMore: false, cursor: '', list: [] };
  }

  /**
   * 获取评论回复列表 (对齐 Flutter fetchCommentReplyList)
   */
  public async fetchCommentReplies(commentId: string, bookId: string, cursor: string = '', count: number = 20): Promise<CommentReplyPage> {
    try {
      await this.init();
      const res = await bridgeCommentReplies(commentId, bookId, cursor, count);
      if (res && typeof res === 'object') {
        const rawList: Record<string, Object>[] = Array.isArray(res.list) ? res.list : [];
        const list: CommentReplyItem[] = [];
        for (let i = 0; i < rawList.length; i++) {
          const item = rawList[i];
          list.push({
            id: String(item['id'] || ''),
            text: String(item['text'] || ''),
            userName: String(item['userName'] || '红果用户'),
            userAvatar: String(item['userAvatar'] || ''),
            userId: String(item['userId'] || ''),
            replyToUserName: String(item['replyToUserName'] || ''),
            createTime: Number(item['createTime'] || 0),
            diggCount: Number(item['diggCount'] || 0)
          });
        }
        return {
          total: Number(res.total || 0),
          hasMore: Boolean(res.hasMore),
          cursor: String(res.cursor || ''),
          list: list
        };
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchCommentReplies error: %{public}s', JSON.stringify(e));
    }
    return { total: 0, hasMore: false, cursor: '', list: [] };
  }

  /**
   * 获取红果创作者/主播短剧作品 (对齐 Flutter creatorWorks)
   */
  public async fetchCreatorWorks(userId: string, cursor: string = '', count: number = 20): Promise<DramaItem[]> {
    try {
      await this.init();
      const res = await bridgeCreatorWorks(userId, cursor, count);
      if (res && Array.isArray(res.items)) {
        return this.mapRawList(res.items);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchCreatorWorks error: %{public}s', JSON.stringify(e));
    }
    return [];
  }

  /**
   * 获取已点赞视频列表 (对齐 Flutter likedVideos)
   */
  public async fetchLikedVideos(offset: number = 0, count: number = 20): Promise<LikedVideoPage> {
    try {
      await this.init();
      const res = await bridgeLikedVideos(offset, count);
      if (res && typeof res === 'object') {
        const rawItems: Record<string, Object>[] = Array.isArray(res.items) ? res.items : [];
        const items: LikedVideoItem[] = [];
        for (let i = 0; i < rawItems.length; i++) {
          const item = rawItems[i];
          const rawCover = String(item['cover'] || '');
          items.push({
            id: String(item['id'] || ''),
            title: String(item['title'] || ''),
            seriesId: String(item['seriesId'] || ''),
            cover: normalizeCoverUrl(rawCover),
            description: String(item['description'] || ''),
            episode: typeof item['episode'] === 'number' ? Number(item['episode']) : undefined,
            episodes: Number(item['episodes'] || 0),
            kind: String(item['kind'] || 'episode'),
            likedAt: Number(item['likedAt'] || 0)
          });
        }
        return {
          items: items,
          hasMore: Boolean(res.hasMore),
          nextOffset: typeof res.nextOffset === 'number' ? Number(res.nextOffset) : undefined,
          unsupportedCount: Number(res.unsupportedCount || 0)
        };
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchLikedVideos error: %{public}s', JSON.stringify(e));
    }
    return { items: [], hasMore: false, unsupportedCount: 0 };
  }

  /**
   * 获取关注的主播列表 (对齐 Flutter followingCreators)
   */
  public async fetchFollowingCreators(userId: string, offset: number = 0, count: number = 20): Promise<FollowingCreatorsPage> {
    try {
      await this.init();
      const res = await bridgeFollowingCreators(userId, offset, count);
      if (res && typeof res === 'object') {
        const rawCreators: Record<string, Object>[] = Array.isArray(res.creators) ? res.creators : [];
        const creators: AnchorItem[] = [];
        for (let i = 0; i < rawCreators.length; i++) {
          const c = rawCreators[i];
          const rawAvatar = String(c['avatar'] || '');
          creators.push({
            id: String(c['id'] || ''),
            name: String(c['name'] || '红果创作者'),
            avatar: normalizeCoverUrl(rawAvatar),
            bio: String(c['description'] || ''),
            worksCount: typeof c['worksCount'] === 'number' ? Number(c['worksCount']) : undefined,
            isFollowed: Boolean(c['following']),
            officialFollowing: typeof c['following'] === 'boolean' ? Boolean(c['following']) : undefined,
            canFollow: Boolean(c['canFollow']),
            relativeType: Number(c['relativeType'] || 2)
          });
        }
        return {
          creators: creators,
          hasMore: Boolean(res.hasMore),
          nextOffset: typeof res.nextOffset === 'number' ? Number(res.nextOffset) : undefined,
          followingDouyinNextOffset: typeof res.followingDouyinNextOffset === 'number' ? Number(res.followingDouyinNextOffset) : undefined
        };
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchFollowingCreators error: %{public}s', JSON.stringify(e));
    }
    return { creators: [], hasMore: false };
  }

  /**
   * 获取云端追剧或历史记录 (对齐 Flutter service.library)
   */
  public async fetchCloudLibrary(history: boolean, userId: string): Promise<CloudWatchEntry[]> {
    try {
      await this.init();
      const res = await bridgeCloudLibrary(history, userId);
      if (res && Array.isArray(res.items)) {
        const list: CloudWatchEntry[] = [];
        for (let i = 0; i < res.items.length; i++) {
          const item = res.items[i];
          const id = String(item.id || item.series_id || item.book_id || '');
          if (!id) continue;
          const rawCover = String(item.cover || '');
          list.push({
            dramaId: id,
            dramaTitle: String(item.title || '短剧'),
            coverUrl: normalizeCoverUrl(rawCover),
            episodeIndex: Math.max(1, Number(item.episode || 1)),
            episodes: Number(item.episodes || 0),
            updatedAt: Number(item.updatedAt || 0)
          });
        }
        return list;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchCloudLibrary error: %{public}s', JSON.stringify(e));
    }
    return [];
  }

  /**
   * 获取主播主页详情 (对齐 Flutter creatorProfile)
   */
  public async fetchCreatorProfile(userId: string): Promise<AnchorItem | null> {
    try {
      await this.init();
      const res = await bridgeCreatorProfile(userId);
      if (res && res.creator) {
        const c = res.creator;
        return {
          id: String(c.id || ''),
          name: String(c.name || '红果创作者'),
          avatar: normalizeCoverUrl(String(c.avatar || '')),
          bio: String(c.description || ''),
          worksCount: typeof c.worksCount === 'number' ? Number(c.worksCount) : undefined,
          isFollowed: Boolean(c.following),
          officialFollowing: typeof c.following === 'boolean' ? Boolean(c.following) : undefined,
          canFollow: Boolean(c.canFollow),
          relativeType: Number(c.relativeType || 2)
        };
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchCreatorProfile error: %{public}s', JSON.stringify(e));
    }
    return null;
  }

  /**
   * 关注/取消关注主播 (对齐 Flutter setProfileFollowing)
   */
  public async setCreatorFollowing(userId: string, relativeType: number, follow: boolean): Promise<boolean> {
    try {
      await this.init();
      const res = await bridgeCreatorFollow(userId, relativeType, follow);
      return res && res.valid === true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setCreatorFollowing error: %{public}s', JSON.stringify(e));
      return false;
    }
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
