import { AppColors } from '../../../common/AppColors';

@Component
export struct HomeSearchBarView {
  @Prop searchQuery: string = '';
  @Prop recentSearches: string[] = [];
  onSearchChange: (val: string) => void = () => {};
  onSearchSubmit: (val: string) => void = () => {};
  onClearQuery: () => void = () => {};
  onClearRecent: () => void = () => {};

  build() {
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
          .backgroundColor(AppColors.transparent)
          .onChange((val: string) => {
            this.onSearchChange(val);
          })
          .onSubmit(() => {
            this.onSearchSubmit(this.searchQuery);
          })

        if (this.searchQuery.length > 0) {
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_close'))
              .width(16)
              .height(16)
              .fillColor(AppColors.textSecondary)
          }
          .backgroundColor(AppColors.transparent)
          .width(32)
          .height(32)
          .onClick(() => {
            this.onClearQuery();
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
          this.onSearchSubmit(this.searchQuery);
        })
      }
      .width('100%')
      .height(44)
      .backgroundColor(AppColors.bgCard)
      .borderRadius(22)
      .border({ width: 0.8, color: AppColors.whiteAlpha12 })

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
                .border({ width: 0.6, color: AppColors.whiteAlpha08 })
                .onClick(() => {
                  this.onSearchSubmit(word);
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
          .backgroundColor(AppColors.transparent)
          .width(32)
          .height(32)
          .onClick(() => {
            this.onClearRecent();
          })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
  }
}
