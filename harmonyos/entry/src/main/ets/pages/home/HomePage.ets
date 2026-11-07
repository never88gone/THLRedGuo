import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaItem } from '../../models/Drama';
import { CategoryItem } from '../../models/Category';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';

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
      // 1. 顶部 Header (对齐 Flutter HomeAppBarView)
      Row() {
        // 左侧：数据源切换胶囊 (官方红果 + 下拉箭头)
        Row({ space: 6 }) {
          Image($r('app.media.ic_movie_filter'))
            .width(18)
            .height(18)

          Text('官方红果')
            .fontSize(16)
            .fontWeight(FontWeight.Bolder)
            .fontColor(AppColors.textPrimary)

          Image($r('app.media.ic_expand_more'))
            .width(18)
            .height(18)
            .fillColor(AppColors.textSecondary)
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(AppColors.darkSurfaceHighest70)
        .borderRadius(12)
        .onClick(() => {
          promptAction.showToast({ message: '当前数据源：官方红果（独立直连）' });
        })

        Blank()

        // 右侧操作按钮：榜单与搜索
        Row({ space: 8 }) {
          // 榜单按钮
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_rankings'))
              .width(20)
              .height(20)
              .fillColor(AppColors.textPrimary)
          }
          .backgroundColor(Color.Transparent)
          .width(36)
          .height(36)
          .onClick(() => {
            router.pushUrl({ url: 'pages/rankings/RankingsPage' });
          })

          // 搜索按钮 (折叠/展开搜索栏)
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_search'))
              .width(20)
              .height(20)
              .fillColor(this.isSearchVisible ? AppColors.hongguoRed : AppColors.textPrimary)
          }
          .backgroundColor(this.isSearchVisible ? 'rgba(255, 36, 66, 0.15)' : Color.Transparent)
          .width(36)
          .height(36)
          .onClick(() => {
            this.isSearchVisible = !this.isSearchVisible;
            if (!this.isSearchVisible && this.searchActiveKeyword) {
              this.searchQuery = '';
              this.searchActiveKeyword = '';
              this.page = 1;
              this.hasMore = true;
              this.loadDramas(1, false);
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 10 })
      .backgroundColor(AppColors.bgDark)

      // 2. 折叠式搜索视图 (对齐 Flutter HomeSearchBarView & SearchInput)
      if (this.isSearchVisible) {
        Column({ space: 8 }) {
          // 搜索输入框
          Row({ space: 8 }) {
            Image($r('app.media.ic_search'))
              .width(18)
              .height(18)
              .fillColor(AppColors.textSecondary)
              .margin({ left: 12 })

            TextInput({ placeholder: '搜索短剧名称、主角或题材...', text: this.searchQuery })
              .layoutWeight(1)
              .fontSize(14)
              .fontColor(AppColors.textPrimary)
              .placeholderColor(AppColors.textSecondary)
              .backgroundColor(Color.Transparent)
              .onChange((val: string) => {
                this.searchQuery = val;
              })
              .onSubmit(() => {
                this.performSearch(this.searchQuery);
              })

            if (this.searchQuery.length > 0) {
              Button({ type: ButtonType.Circle }) {
                Image($r('app.media.ic_close'))
                  .width(16)
                  .height(16)
                  .fillColor(AppColors.textSecondary)
              }
              .backgroundColor(Color.Transparent)
              .width(32)
              .height(32)
              .onClick(() => {
                this.searchQuery = '';
              })
            }

            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.ic_arrow_forward'))
                .width(18)
                .height(18)
                .fillColor(AppColors.textPrimary)
            }
            .backgroundColor(AppColors.hongguoRed)
            .width(32)
            .height(32)
            .margin({ right: 6 })
            .onClick(() => {
              this.performSearch(this.searchQuery);
            })
          }
          .width('100%')
          .height(44)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(22)
          .border({ width: 0.8, color: 'rgba(255, 255, 255, 0.12)' })

          // 最近搜索词 ActionChips
          if (this.searchQuery.trim().length === 0 && this.recentSearches.length > 0) {
            Row() {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.recentSearches, (word: string) => {
                    Row({ space: 4 }) {
                      Image($r('app.media.ic_history'))
                        .width(13)
                        .height(13)
                        .fillColor(AppColors.textSecondary)
                      Text(word)
                        .fontSize(12)
                        .fontColor(AppColors.textPrimary)
                    }
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(AppColors.bgCard)
                    .borderRadius(14)
                    .border({ width: 0.6, color: 'rgba(255, 255, 255, 0.08)' })
                    .onClick(() => {
                      this.searchQuery = word;
                      this.performSearch(word);
                    })
                  })
                }
                .padding({ left: 4, right: 8 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .layoutWeight(1)

              // 清空搜索历史图标
              Button({ type: ButtonType.Circle }) {
                Image($r('app.media.ic_delete'))
                  .width(16)
                  .height(16)
                  .fillColor(AppColors.textSecondary)
              }
              .backgroundColor(Color.Transparent)
              .width(32)
              .height(32)
              .onClick(() => {
                this.clearRecentSearches();
              })
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
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
            .backgroundColor(Color.Transparent)
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
                .fontColor(this.selectedCategoryIndex === index ? Color.White : AppColors.textSecondary)
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
              this.DramaCard(item)
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

  @Builder
  DramaCard(drama: DramaItem) {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(drama.coverUrl)
          .width('100%')
          .height(180)
          .borderRadius(AppDimensions.radiusMd)
          .objectFit(ImageFit.Cover)
          .backgroundColor(AppColors.bgCardHover)

        if (drama.remarks) {
          Text(drama.remarks)
            .fontSize(10)
            .fontColor(Color.White)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('rgba(0, 0, 0, 0.65)')
            .borderRadius({ topLeft: 4, bottomRight: AppDimensions.radiusMd })
        }
      }
      .width('100%')
      .height(180)

      Text(drama.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6, bottom: 2 })
        .width('100%')

      if (drama.intro) {
        Text(drama.intro)
          .fontSize(11)
          .fontColor(AppColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .onClick(() => {
      this.openDramaDetail(drama);
    })
  }
}
