import { DramaItem, DramaDetail } from '../../models/Drama';
import { CategoryItem } from '../../models/Category';
import { RankingBoard, RankingItem } from '../../models/Ranking';
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
   * 获取排行榜数据
   */
  public async getRankingBoards(): Promise<RankingBoard[]> {
    const cats = await this.getCategories();
    const typeId = cats.length > 0 ? cats[0].typeId : 'hot';
    const dramas = await this.loadCategoryDramas(typeId, 1);

    const hotItems: RankingItem[] = [];
    const hotList = dramas.slice(0, 15);
    for (let i = 0; i < hotList.length; i++) {
      const d = hotList[i];
      hotItems.push(new RankingItem(
        d.id,
        i + 1,
        d.title,
        d.coverUrl,
        `${(99.8 - i * 2.1).toFixed(1)}万`,
        i === 0 ? 'top' : (i % 2 === 0 ? 'up' : 'same'),
        d.remarks
      ));
    }

    const soarItems: RankingItem[] = [];
    const soarList = dramas.slice(2, 16);
    for (let i = 0; i < soarList.length; i++) {
      const d = soarList[i];
      soarItems.push(new RankingItem(
        d.id,
        i + 1,
        d.title,
        d.coverUrl,
        `${(89.5 - i * 1.8).toFixed(1)}万`,
        'up',
        d.remarks
      ));
    }

    const newItems: RankingItem[] = [];
    const newList = dramas.slice(4, 18);
    for (let i = 0; i < newList.length; i++) {
      const d = newList[i];
      newItems.push(new RankingItem(
        d.id,
        i + 1,
        d.title,
        d.coverUrl,
        `${(78.2 - i * 1.5).toFixed(1)}万`,
        'new',
        d.remarks
      ));
    }

    return [
      {
        boardId: 'hot',
        title: '热播榜',
        subTitle: '全网观众都在看的火爆短剧',
        items: hotItems
      },
      {
        boardId: 'soar',
        title: '飙升榜',
        subTitle: '人气极速上涨好剧',
        items: soarItems
      },
      {
        boardId: 'new',
        title: '新剧榜',
        subTitle: '本周新鲜出炉短剧首发',
        items: newItems
      }
    ];
  }
}
