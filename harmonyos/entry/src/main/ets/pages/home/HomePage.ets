import router from '@ohos.router';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaItem } from '../../models/Drama';
import { CategoryItem } from '../../models/Category';
import { CoreEngine } from '../../core/engine/CoreEngine';

@Entry
@Component
export struct HomePage {
  @State categories: CategoryItem[] = [
    { typeId: 'all', typeName: '全部', isSelected: true },
    { typeId: 'real-drama', typeName: '真人剧', isSelected: false },
    { typeId: 'comic-drama', typeName: '动漫剧', isSelected: false },
    { typeId: 'ai-drama', typeName: 'AI短剧', isSelected: false }
  ];
  @State selectedCategoryIndex: number = 0;
  @State dramas: DramaItem[] = [];
  @State isLoading: boolean = false;

  aboutToAppear(): void {
    this.loadDramas();
  }

  async loadDramas(): Promise<void> {
    this.isLoading = true;
    const cat = this.categories[this.selectedCategoryIndex];
    this.dramas = await CoreEngine.getInstance().loadCategoryDramas(cat.typeId, 1);
    this.isLoading = false;
  }

  build() {
    Column() {
      // 顶部导航栏与搜索框入口
      Row() {
        Text('糖葫芦Haw')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.hongguoRed)

        Blank()

        Row() {
          Text('🔍 搜索精彩短剧...')
            .fontSize(13)
            .fontColor(AppColors.textMuted)
        }
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(AppColors.bgCard)
        .borderRadius(AppDimensions.radiusLg)
        .onClick(() => {
          router.pushUrl({ url: 'pages/search/SearchPage' });
        })
      }
      .width('100%')
      .padding({ left: AppDimensions.paddingLg, right: AppDimensions.paddingLg, top: 12, bottom: 8 })

      // 分类滚动胶囊栏
      List({ space: 8 }) {
        ForEach(this.categories, (item: CategoryItem, index: number) => {
          ListItem() {
            Text(item.typeName)
              .fontSize(14)
              .fontWeight(this.selectedCategoryIndex === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.selectedCategoryIndex === index ? AppColors.textPrimary : AppColors.textSecondary)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .backgroundColor(this.selectedCategoryIndex === index ? AppColors.hongguoRed : AppColors.bgCard)
              .borderRadius(AppDimensions.radiusLg)
              .onClick(() => {
                this.selectedCategoryIndex = index;
                this.loadDramas();
              })
          }
        })
      }
      .listDirection(Axis.Horizontal)
      .height(44)
      .width('100%')
      .padding({ left: AppDimensions.paddingLg, right: AppDimensions.paddingLg })

      // 短剧双列卡片流
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(AppColors.hongguoRed)
          Text('正在加载短剧列表...')
            .fontSize(13)
            .fontColor(AppColors.textMuted)
            .margin({ top: 12 })
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
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(12)
        .padding(AppDimensions.paddingLg)
        .layoutWeight(1)
        .width('100%')
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
            .fontColor(AppColors.textPrimary)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#CC000000')
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
          .fontColor(AppColors.textMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .onClick(() => {
      router.pushUrl({
        url: 'pages/detail/DramaDetailPage',
        params: { dramaId: drama.id, dramaTitle: drama.title }
      });
    })
  }
}
