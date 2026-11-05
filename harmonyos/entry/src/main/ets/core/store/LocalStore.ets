import preferences from '@ohos.data.preferences';
import Context from '@ohos.app.ability.common';
import { DramaItem } from '../../models/Drama';
import { Constants } from '../../common/Constants';

export interface WatchHistoryItem {
  dramaId: string;
  dramaTitle: string;
  coverUrl: string;
  episodeIndex: number;
  positionMs: number;
  durationMs: number;
  updatedAt: number;
}

export class LocalStore {
  private static instance: LocalStore;
  private prefStore: preferences.Preferences | null = null;
  private context: Context.UIAbilityContext | null = null;

  public static getInstance(): LocalStore {
    if (!LocalStore.instance) {
      LocalStore.instance = new LocalStore();
    }
    return LocalStore.instance;
  }

  public getContext(): Context.UIAbilityContext | null {
    return this.context;
  }

  public async init(ctx: Context.UIAbilityContext): Promise<void> {
    this.context = ctx;
    try {
      this.prefStore = await preferences.getPreferences(ctx, Constants.PREF_STORE_NAME);
    } catch (err) {
      console.error('LocalStore init error: ' + JSON.stringify(err));
    }
  }

  // ================= 播放历史 =================
  public async getHistory(): Promise<WatchHistoryItem[]> {
    if (!this.prefStore) return [];
    try {
      const jsonStr = await this.prefStore.get(Constants.KEY_WATCH_HISTORY, '[]') as string;
      return JSON.parse(jsonStr) as WatchHistoryItem[];
    } catch {
      return [];
    }
  }

  public async saveHistory(item: WatchHistoryItem): Promise<void> {
    if (!this.prefStore) return;
    try {
      let list = await this.getHistory();
      list = list.filter(h => h.dramaId !== item.dramaId);
      list.unshift(item);
      // 限制最多保留 100 条
      if (list.length > 100) {
        list = list.slice(0, 100);
      }
      await this.prefStore.put(Constants.KEY_WATCH_HISTORY, JSON.stringify(list));
      await this.prefStore.flush();
    } catch (err) {
      console.error('saveHistory error: ' + JSON.stringify(err));
    }
  }

  public async removeHistory(dramaId: string): Promise<void> {
    if (!this.prefStore) return;
    try {
      let list = await this.getHistory();
      list = list.filter(h => h.dramaId !== dramaId);
      await this.prefStore.put(Constants.KEY_WATCH_HISTORY, JSON.stringify(list));
      await this.prefStore.flush();
    } catch (err) {
      console.error('removeHistory error: ' + JSON.stringify(err));
    }
  }

  // ================= 追剧收藏 =================
  public async getFavorites(): Promise<DramaItem[]> {
    if (!this.prefStore) return [];
    try {
      const jsonStr = await this.prefStore.get(Constants.KEY_FAVORITES, '[]') as string;
      return JSON.parse(jsonStr) as DramaItem[];
    } catch {
      return [];
    }
  }

  public async isFavorite(dramaId: string): Promise<boolean> {
    const list = await this.getFavorites();
    return list.some(d => d.id === dramaId);
  }

  public async toggleFavorite(item: DramaItem): Promise<boolean> {
    if (!this.prefStore) return false;
    let list = await this.getFavorites();
    const exists = list.some(d => d.id === item.id);
    if (exists) {
      list = list.filter(d => d.id !== item.id);
    } else {
      list.unshift(item);
    }
    await this.prefStore.put(Constants.KEY_FAVORITES, JSON.stringify(list));
    await this.prefStore.flush();
    return !exists;
  }

  // ================= 搜索历史 =================
  public async getRecentSearches(): Promise<string[]> {
    if (!this.prefStore) return [];
    try {
      const jsonStr = await this.prefStore.get(Constants.KEY_SEARCH_HISTORY, '[]') as string;
      return JSON.parse(jsonStr) as string[];
    } catch {
      return [];
    }
  }

  public async saveRecentSearch(keyword: string): Promise<void> {
    if (!this.prefStore || !keyword.trim()) return;
    try {
      let list = await this.getRecentSearches();
      list = list.filter(k => k !== keyword.trim());
      list.unshift(keyword.trim());
      if (list.length > 20) {
        list = list.slice(0, 20);
      }
      await this.prefStore.put(Constants.KEY_SEARCH_HISTORY, JSON.stringify(list));
      await this.prefStore.flush();
    } catch (err) {
      console.error('saveRecentSearch error: ' + JSON.stringify(err));
    }
  }

  public async clearRecentSearches(): Promise<void> {
    if (!this.prefStore) return;
    try {
      await this.prefStore.put(Constants.KEY_SEARCH_HISTORY, '[]');
      await this.prefStore.flush();
    } catch (err) {
      console.error('clearRecentSearches error: ' + JSON.stringify(err));
    }
  }

  public async clearAllHistory(): Promise<void> {
    if (!this.prefStore) return;
    try {
      await this.prefStore.put(Constants.KEY_WATCH_HISTORY, '[]');
      await this.prefStore.put(Constants.KEY_SEARCH_HISTORY, '[]');
      await this.prefStore.flush();
    } catch (err) {
      console.error('clearAllHistory error: ' + JSON.stringify(err));
    }
  }
}
