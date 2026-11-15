import { AppColors } from '../../../common/AppColors';
import { AppDimensions } from '../../../common/AppDimensions';
import { DramaItem } from '../../../models/Drama';

@Component
export struct HomeDramaCardView {
  @Prop drama: DramaItem = { id: '', title: '', coverUrl: '', remarks: '' };
  onDramaClick: (drama: DramaItem) => void = () => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(this.drama.coverUrl)
          .width('100%')
          .height(180)
          .borderRadius(AppDimensions.radiusMd)
          .objectFit(ImageFit.Cover)
          .backgroundColor(AppColors.bgCardHover)

        if (this.drama.remarks) {
          Text(this.drama.remarks)
            .fontSize(10)
            .fontColor(AppColors.white)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(AppColors.maskDark65)
            .borderRadius({ topLeft: 4, bottomRight: AppDimensions.radiusMd })
        }
      }
      .width('100%')
      .height(180)

      Text(this.drama.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6, bottom: 2 })
        .width('100%')

      if (this.drama.intro) {
        Text(this.drama.intro)
          .fontSize(11)
          .fontColor(AppColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .onClick(() => {
      this.onDramaClick(this.drama);
    })
  }
}
