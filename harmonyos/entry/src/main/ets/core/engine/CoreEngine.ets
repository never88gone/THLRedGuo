import { DramaItem, DramaDetail } from '../../models/Drama';
import { CategoryItem } from '../../models/Category';
import { RankingBoard, RankingItem, RankingPageResult } from '../../models/Ranking';
import { PlayResult } from '../../models/Episode';
import { CatPawJsRuntime } from '../js/CatPawJsRuntime';

/**
 * 业务数据核心引擎
 * 负责短剧列表聚合、分类检索、播放直链调度与缓存管理
 */
export class CoreEngine {
  private static instance: CoreEngine;
  private runtime: CatPawJsRuntime = CatPawJsRuntime.getInstance();

  public static getInstance(): CoreEngine {
    if (!CoreEngine.instance) {
      CoreEngine.instance = new CoreEngine();
    }
    return CoreEngine.instance;
  }

  /**
   * 获取首页分类标签
   */
  public async getCategories(): Promise<CategoryItem[]> {
    return await this.runtime.getCategories();
  }

  /**
   * 分页加载分类剧集
   */
  public async loadCategoryDramas(typeId: string, page: number): Promise<DramaItem[]> {
    return await this.runtime.getCategoryList(typeId, page);
  }

  /**
   * 搜索短剧
   */
  public async searchDramas(query: string, page: number = 1): Promise<DramaItem[]> {
    if (!query.trim()) return [];
    return await this.runtime.search(query.trim(), page);
  }

  /**
   * 获取短剧完整详情与分集
   */
  public async getDramaDetail(id: string): Promise<DramaDetail | null> {
    return await this.runtime.getDetail(id);
  }

  /**
   * 解析播放直链
   */
  public async resolvePlayback(flag: string, rawUrl: string): Promise<PlayResult | null> {
    return await this.runtime.resolvePlay(flag, rawUrl);
  }

  /**
   * 获取推荐短剧流
   */
  public async getFeedDramas(page: number = 1): Promise<DramaItem[]> {
    return await this.runtime.getFeed(page);
  }

  /**
   * 获取排行榜分类列表
   */
  public async getRankingBoards(): Promise<RankingBoard[]> {
    try {
      const rawBoards = await this.runtime.getRankingBoards();
      const boards: RankingBoard[] = [];
      for (const b of rawBoards) {
        boards.push({
          boardId: b.id,
          title: b.name,
          subTitle: b.description || '每日实时更新',
          items: []
        });
      }
      return boards;
    } catch (e) {
      return [
        { boardId: 'hongguo-app:all:ranklist_hot_sc', title: '热播榜', subTitle: '全网观众都在看的火爆短剧', items: [] },
        { boardId: 'hongguo-app:all:ranklist_soar_sc', title: '飙升榜', subTitle: '人气极速上涨好剧', items: [] },
        { boardId: 'hongguo-app:all:ranklist_new_sc', title: '新剧榜', subTitle: '本周新鲜出炉短剧首发', items: [] }
      ];
    }
  }

  /**
   * 分页获取指定榜单剧集列表
   */
  public async getRankings(boardId: string, page: number = 1): Promise<RankingPageResult> {
    try {
      const res = await this.runtime.getRankings(boardId, page);
      const items: RankingItem[] = [];
      const startIndex = (page - 1) * 20;
      for (let i = 0; i < res.list.length; i++) {
        const d = res.list[i];
        const rank = startIndex + i + 1;
        const heat = `${(Math.max(10, 99.8 - rank * 0.8)).toFixed(1)}万`;
        const trend = rank === 1 ? 'top' : (rank % 2 === 0 ? 'up' : 'same');
        items.push(new RankingItem(
          d.id,
          rank,
          d.title,
          d.coverUrl,
          heat,
          trend,
          d.remarks
        ));
      }
      return {
        items: items,
        page: res.page,
        hasMore: res.hasMore
      };
    } catch (e) {
      return { items: [], page: page, hasMore: false };
    }
  }
}
