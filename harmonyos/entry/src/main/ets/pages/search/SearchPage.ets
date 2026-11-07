import router from '@ohos.router';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaItem } from '../../models/Drama';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';

@Entry
@Component
export struct SearchPage {
  @State searchText: string = '';
  @State searchResults: DramaItem[] = [];
  @State recentSearches: string[] = [];
  @State isLoading: boolean = false;
  @State hasSearched: boolean = false;

  private hotKeywords: string[] = [
    '战神归来', '豪门千金', '重生逆袭', '顶级神医',
    '龙王赘婿', '闪婚娇妻', '奶爸无敌', '权倾天下'
  ];

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['keyword']) {
      this.searchText = params['keyword'] as string;
      this.doSearch(this.searchText);
    }
    this.loadRecentSearches();
  }

  async loadRecentSearches(): Promise<void> {
    this.recentSearches = await LocalStore.getInstance().getRecentSearches();
  }

  async doSearch(keyword: string): Promise<void> {
    const query = keyword.trim();
    if (!query) return;

    this.searchText = query;
    this.isLoading = true;
    this.hasSearched = true;

    await LocalStore.getInstance().saveRecentSearch(query);
    this.recentSearches = await LocalStore.getInstance().getRecentSearches();

    this.searchResults = await CoreEngine.getInstance().searchDramas(query);
    this.isLoading = false;
  }

  async clearRecent(): Promise<void> {
    await LocalStore.getInstance().clearRecentSearches();
    this.recentSearches = [];
  }

  openDramaDetail(drama: DramaItem): void {
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: drama.id,
        dramaTitle: drama.title
      }
    });
  }

  build() {
    Column() {
      // 顶部搜索输入栏
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_arrow_back'))
            .width(22)
            .height(22)
            .fillColor(AppColors.textPrimary)
        }
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => {
          router.back();
        })

        Row() {
          TextInput({ text: this.searchText, placeholder: '搜索短剧名称或主角...' })
            .placeholderColor(AppColors.textMuted)
            .fontSize(14)
            .fontColor(AppColors.textPrimary)
            .backgroundColor(AppColors.bgCard)
            .height(38)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.searchText = value;
              if (!value) {
                this.hasSearched = false;
                this.searchResults = [];
              }
            })
            .onSubmit(() => {
              this.doSearch(this.searchText);
            })

          if (this.searchText.length > 0) {
            Button('✕')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .backgroundColor(Color.Transparent)
              .width(28)
              .height(28)
              .onClick(() => {
                this.searchText = '';
                this.hasSearched = false;
                this.searchResults = [];
              })
          }
        }
        .layoutWeight(1)
        .padding({ left: 10, right: 6 })
        .backgroundColor(AppColors.bgCard)
        .borderRadius(AppDimensions.radiusLg)

        Button('搜索')
          .fontSize(14)
          .fontColor(AppColors.textPrimary)
          .backgroundColor(AppColors.hongguoRed)
          .height(36)
          .borderRadius(18)
          .onClick(() => {
            this.doSearch(this.searchText);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      // 内容区
      if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(AppColors.hongguoRed)
          Text('正在检索短剧库...')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.hasSearched) {
        // 搜索结果展示
        if (this.searchResults.length === 0) {
          Column({ space: 10 }) {
            Text('🔍')
              .fontSize(40)
            Text('未找到相关短剧')
              .fontSize(14)
              .fontColor(AppColors.textSecondary)
            Text('请尝试换个关键词进行检索')
              .fontSize(12)
              .fontColor(AppColors.textMuted)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.searchResults, (drama: DramaItem) => {
              GridItem() {
                Column({ space: 6 }) {
                  Stack({ alignContent: Alignment.BottomEnd }) {
                    Image(drama.coverUrl)
                      .width('100%')
                      .height(160)
                      .borderRadius(AppDimensions.radiusMd)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(AppColors.bgCard)

                    if (drama.remarks) {
                      Text(drama.remarks)
                        .fontSize(10)
                        .fontColor(AppColors.textPrimary)
                        .backgroundColor('rgba(0, 0, 0, 0.65)')
                        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                        .borderRadius(4)
                        .margin(6)
                    }
                  }

                  Text(drama.title)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  this.openDramaDetail(drama);
                })
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(10)
          .rowsGap(14)
          .padding(AppDimensions.paddingMd)
          .layoutWeight(1)
        }
      } else {
        // 未搜索时显示：历史搜索 + 热门推荐
        Scroll() {
          Column({ space: 20 }) {
            // 最近搜索
            if (this.recentSearches.length > 0) {
              Column({ space: 10 }) {
                Row() {
                  Text('最近搜索')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.textPrimary)

                  Blank()

                  Button('清空')
                    .fontSize(12)
                    .fontColor(AppColors.textMuted)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.clearRecent();
                    })
                }
                .width('100%')

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.recentSearches, (keyword: string) => {
                    Text(keyword)
                      .fontSize(12)
                      .fontColor(AppColors.textSecondary)
                      .backgroundColor(AppColors.bgCard)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(14)
                      .margin({ right: 8, bottom: 8 })
                      .onClick(() => {
                        this.doSearch(keyword);
                      })
                  })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 热门推荐短剧热搜
            Column({ space: 10 }) {
              Text('大家都在搜')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.textPrimary)

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.hotKeywords, (keyword: string, index: number) => {
                  Row({ space: 4 }) {
                    Text(`${index + 1}`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(index < 3 ? AppColors.hongguoRed : AppColors.textMuted)

                    Text(keyword)
                      .fontSize(12)
                      .fontColor(AppColors.textPrimary)
                  }
                  .backgroundColor(AppColors.bgCard)
                  .padding({ left: 10, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.doSearch(keyword);
                  })
                })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .padding(AppDimensions.paddingMd)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
