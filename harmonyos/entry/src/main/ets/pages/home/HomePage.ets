import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';
import { AppColors } from '../../common/AppColors';
import { DramaItem } from '../../models/Drama';
import { CategoryItem } from '../../models/Category';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';
import { HomeAppBarView } from './components/HomeAppBarView';
import { HomeSearchBarView } from './components/HomeSearchBarView';
import { HomeDramaCardView } from './components/HomeDramaCardView';

const TAG = 'HomePage';
const DOMAIN = 0x0000;

@Entry
@Component
export struct HomePage {
  @State categories: CategoryItem[] = [];
  @State selectedCategoryIndex: number = 0;
  @State dramas: DramaItem[] = [];
  @State isLoading: boolean = false;

  // 分页相关状态
  @State page: number = 1;
  @State isLoadingMore: boolean = false;
  @State hasMore: boolean = true;

  // 搜索相关状态
  @State isSearchVisible: boolean = false;
  @State searchQuery: string = '';
  @State isSearching: boolean = false;
  @State searchActiveKeyword: string = '';
  @State recentSearches: string[] = [];

  aboutToAppear(): void {
    this.initData();
  }

  async initData(): Promise<void> {
    this.recentSearches = await LocalStore.getInstance().getRecentSearches();
    try {
      this.categories = await CoreEngine.getInstance().getCategories();
    } catch (_) {}

    if (this.categories.length === 0) {
      this.categories = [
        { typeId: 'all', typeName: '全部', isSelected: true },
        { typeId: 'real-drama', typeName: '真人剧', isSelected: false },
        { typeId: 'comic-drama', typeName: '动漫剧', isSelected: false },
        { typeId: 'ai-drama', typeName: 'AI短剧', isSelected: false }
      ];
    }
    this.loadDramas(1, false);
  }

  async loadDramas(page: number = 1, isMore: boolean = false): Promise<void> {
    if (isMore) {
      if (this.isLoadingMore || !this.hasMore || this.isLoading) return;
      this.isLoadingMore = true;
    } else {
      this.isLoading = true;
      this.page = 1;
      this.hasMore = true;
      this.searchActiveKeyword = '';
    }

    try {
      const cat = this.categories[this.selectedCategoryIndex];
      const tid = cat ? cat.typeId : 'hot';
      hilog.info(DOMAIN, TAG, 'loadDramas: tid=%{public}s, page=%{public}d, isMore=%{public}s', tid, page, String(isMore));
      const results = await CoreEngine.getInstance().loadCategoryDramas(tid, page);

      if (isMore) {
        if (results && results.length > 0) {
          const existingIds = new Set(this.dramas.map(d => d.id));
          const newItems = results.filter(d => !existingIds.has(d.id));
          if (newItems.length > 0) {
            this.dramas.push(...newItems);
            this.page = page;
            this.hasMore = true;
          } else {
            this.hasMore = false;
          }
          hilog.info(DOMAIN, TAG, 'loadDramas more: added %{public}d items, total: %{public}d, hasMore: %{public}s', newItems.length, this.dramas.length, String(this.hasMore));
        } else {
          this.hasMore = false;
        }
      } else {
        this.dramas = results || [];
        this.page = 1;
        this.hasMore = (results && results.length > 0);
        hilog.info(DOMAIN, TAG, 'loadDramas first: %{public}d items, hasMore: %{public}s', this.dramas.length, String(this.hasMore));
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadDramas error: %{public}s', JSON.stringify(e));
      if (!isMore) {
        this.dramas = [];
      }
      this.hasMore = false;
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  async loadMore(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.hasMore) return;
    hilog.info(DOMAIN, TAG, 'loadMore requested: current page=%{public}d, search=%{public}s', this.page, this.searchActiveKeyword);
    if (this.searchActiveKeyword) {
      await this.performSearch(this.searchActiveKeyword, this.page + 1, true);
    } else {
      await this.loadDramas(this.page + 1, true);
    }
  }

  async performSearch(query: string, page: number = 1, isMore: boolean = false): Promise<void> {
    const trimmed = query.trim();
    if (!trimmed) {
      this.searchActiveKeyword = '';
      this.loadDramas(1, false);
      return;
    }

    if (isMore) {
      if (this.isLoadingMore || !this.hasMore || this.isLoading) return;
      this.isLoadingMore = true;
    } else {
      this.isLoading = true;
      this.page = 1;
      this.hasMore = true;
      this.searchActiveKeyword = trimmed;
      await LocalStore.getInstance().saveRecentSearch(trimmed);
      this.recentSearches = await LocalStore.getInstance().getRecentSearches();
    }

    try {
      hilog.info(DOMAIN, TAG, 'performSearch: query=%{public}s, page=%{public}d, isMore=%{public}s', trimmed, page, String(isMore));
      const results = await CoreEngine.getInstance().searchDramas(trimmed, page);
      if (isMore) {
        if (results && results.length > 0) {
          const existingIds = new Set(this.dramas.map(d => d.id));
          const newItems = results.filter(d => !existingIds.has(d.id));
          if (newItems.length > 0) {
            this.dramas.push(...newItems);
            this.page = page;
            this.hasMore = true;
          } else {
            this.hasMore = false;
          }
          hilog.info(DOMAIN, TAG, 'performSearch more: added %{public}d items, total: %{public}d, hasMore: %{public}s', newItems.length, this.dramas.length, String(this.hasMore));
        } else {
          this.hasMore = false;
        }
      } else {
        this.dramas = results || [];
        this.page = 1;
        this.hasMore = (results && results.length > 0);
        hilog.info(DOMAIN, TAG, 'performSearch first: %{public}d items, hasMore: %{public}s', this.dramas.length, String(this.hasMore));
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search error: %{public}s', JSON.stringify(e));
      if (!isMore) {
        this.dramas = [];
      }
      this.hasMore = false;
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  async clearRecentSearches(): Promise<void> {
    await LocalStore.getInstance().clearRecentSearches();
    this.recentSearches = [];
    promptAction.showToast({ message: '已清空最近搜索' });
  }

  openDramaDetail(drama: DramaItem): void {
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: drama.id,
        dramaTitle: drama.title,
        coverUrl: drama.coverUrl
      }
    });
  }

  build() {
    Column() {
      // 1. 顶部 Header
      HomeAppBarView({
        isSearchVisible: this.isSearchVisible,
        onToggleSearch: () => {
          this.isSearchVisible = !this.isSearchVisible;
          if (!this.isSearchVisible && this.searchActiveKeyword) {
            this.searchQuery = '';
            this.searchActiveKeyword = '';
            this.page = 1;
            this.hasMore = true;
            this.loadDramas(1, false);
          }
        }
      })

      // 2. 折叠式搜索视图
      if (this.isSearchVisible) {
        HomeSearchBarView({
          searchQuery: this.searchQuery,
          recentSearches: this.recentSearches,
          onSearchChange: (val: string) => {
            this.searchQuery = val;
          },
          onSearchSubmit: (val: string) => {
            this.performSearch(val);
          },
          onClearQuery: () => {
            this.searchQuery = '';
          },
          onClearRecent: () => {
            this.clearRecentSearches();
          }
        })
      }

      // 3. 分类滚动胶囊栏或当前搜索结果提示
      if (this.searchActiveKeyword) {
        Row() {
          Text(`搜索结果：“${this.searchActiveKeyword}”`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)

          Blank()

          Button('清除搜索')
            .fontSize(12)
            .fontColor(AppColors.hongguoRed)
            .backgroundColor(AppColors.transparent)
            .onClick(() => {
              this.searchQuery = '';
              this.searchActiveKeyword = '';
              this.dramas = [];
              this.page = 1;
              this.hasMore = true;
              this.loadDramas(1, false);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 6 })
      } else {
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.categories, (item: CategoryItem, index: number) => {
              Button(item.typeName)
                .fontSize(13)
                .fontWeight(this.selectedCategoryIndex === index ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.selectedCategoryIndex === index ? AppColors.white : AppColors.textSecondary)
                .backgroundColor(this.selectedCategoryIndex === index ? AppColors.hongguoRed : AppColors.bgCard)
                .height(32)
                .padding({ left: 14, right: 14 })
                .borderRadius(16)
                .onClick(() => {
                  this.selectedCategoryIndex = index;
                  this.dramas = [];
                  this.page = 1;
                  this.hasMore = true;
                  this.loadDramas(1, false);
                })
            })
          }
          .justifyContent(FlexAlign.Start)
          .padding({ left: 16, right: 16, top: 4, bottom: 8 })
        }
        .align(Alignment.Start)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      // 4. 短剧双列卡片流
      if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(AppColors.hongguoRed)
          Text('正在加载短剧列表...')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.dramas.length === 0) {
        Column({ space: 10 }) {
          Text('🔍')
            .fontSize(40)
          Text('暂无相关短剧')
            .fontSize(14)
            .fontColor(AppColors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.dramas, (item: DramaItem) => {
            GridItem() {
              HomeDramaCardView({
                drama: item,
                onDramaClick: (d: DramaItem) => {
                  this.openDramaDetail(d);
                }
              })
            }
          })

          // 底部分页加载状态指示器 (跨双列展示)
          if (this.isLoadingMore) {
            GridItem() {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color(AppColors.hongguoRed)
                Text('正在加载更多短剧...')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 14, bottom: 20 })
            }
            .columnStart(0)
            .columnEnd(1)
          } else if (!this.hasMore && this.dramas.length > 0) {
            GridItem() {
              Row() {
                Text('已经到底啦')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 14, bottom: 20 })
            }
            .columnStart(0)
            .columnEnd(1)
          }
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(12)
        .padding({ left: 16, right: 16, top: 6, bottom: 16 })
        .layoutWeight(1)
        .width('100%')
        .onReachEnd(() => {
          hilog.info(DOMAIN, TAG, 'Grid onReachEnd triggered! hasMore=%{public}s, isLoadingMore=%{public}s', String(this.hasMore), String(this.isLoadingMore));
          this.loadMore();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
