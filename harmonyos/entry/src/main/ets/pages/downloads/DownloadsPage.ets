import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DownloadTask, DownloadStatus } from '../../models/Download';
import { DownloadManager } from '../../core/download/DownloadManager';

@Entry
@Component
export struct DownloadsPage {
  @State tasks: DownloadTask[] = [];
  @State selectedTab: number = 0; // 0: 全部任务, 1: 已完成, 2: 下载中

  private downloadListener = (newTasks: DownloadTask[]) => {
    this.tasks = [...newTasks];
  };

  aboutToAppear(): void {
    DownloadManager.getInstance().addListener(this.downloadListener);
  }

  aboutToDisappear(): void {
    DownloadManager.getInstance().removeListener(this.downloadListener);
  }

  getFilteredTasks(): DownloadTask[] {
    if (this.selectedTab === 1) {
      return this.tasks.filter(t => t.status === DownloadStatus.COMPLETED);
    }
    if (this.selectedTab === 2) {
      return this.tasks.filter(t => t.status === DownloadStatus.DOWNLOADING || t.status === DownloadStatus.PAUSED);
    }
    return this.tasks;
  }

  toggleTask(task: DownloadTask): void {
    if (task.status === DownloadStatus.DOWNLOADING) {
      DownloadManager.getInstance().pause(task.id);
    } else if (task.status === DownloadStatus.PAUSED) {
      DownloadManager.getInstance().resume(task.id);
    }
  }

  deleteTask(task: DownloadTask): void {
    DownloadManager.getInstance().delete(task.id);
    promptAction.showToast({ message: '已删除下载任务' });
  }

  // 快捷添加模拟下载任务用于快速体验与验证
  createDemoTask(): void {
    DownloadManager.getInstance().enqueue(
      'demo_drama_1',
      '战神归来：无双战神',
      'https://p3-novel.byteimg.com/origin/novel-static/demo.jpg',
      1,
      '第 1 集',
      'https://example.com/demo.mp4'
    );
    promptAction.showToast({ message: '已创建离线缓存任务' });
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
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

        Blank()

        Text('离线缓存')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Blank()

        Button('+ 模拟添加')
          .fontSize(12)
          .fontColor(AppColors.hongguoGold)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.createDemoTask();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 8 })

      // 存储空间状态条
      Row() {
        Text('机身存储可用: 42.6 GB')
          .fontSize(11)
          .fontColor(AppColors.textSecondary)

        Blank()

        Text(`缓存占用: ${this.tasks.length * 48} MB`)
          .fontSize(11)
          .fontColor(AppColors.textMuted)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 12 })

      // Tab 分类标签
      Row() {
        Button(`全部 (${this.tasks.length})`)
          .layoutWeight(1)
          .fontSize(13)
          .fontWeight(this.selectedTab === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedTab === 0 ? AppColors.hongguoRed : AppColors.textSecondary)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.selectedTab = 0;
          })

        Button('下载中')
          .layoutWeight(1)
          .fontSize(13)
          .fontWeight(this.selectedTab === 2 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedTab === 2 ? AppColors.hongguoRed : AppColors.textSecondary)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.selectedTab = 2;
          })

        Button('已完成')
          .layoutWeight(1)
          .fontSize(13)
          .fontWeight(this.selectedTab === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedTab === 1 ? AppColors.hongguoRed : AppColors.textSecondary)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.selectedTab = 1;
          })
      }
      .width('100%')
      .border({ width: { bottom: 1 }, color: AppColors.divider })
      .padding({ bottom: 4 })

      // 任务列表
      if (this.getFilteredTasks().length === 0) {
        Column({ space: 10 }) {
          Text('📥')
            .fontSize(44)
          Text('暂无下载任务')
            .fontSize(14)
            .fontColor(AppColors.textSecondary)
          Text('可在短剧详情页中批量选择剧集下载到本地')
            .fontSize(12)
            .fontColor(AppColors.textMuted)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.getFilteredTasks(), (task: DownloadTask) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(task.dramaCover)
                  .width(60)
                  .height(80)
                  .borderRadius(AppDimensions.radiusSm)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(AppColors.bgCard)

                Column({ space: 6 }) {
                  Text(task.dramaTitle)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(task.episodeTitle)
                    .fontSize(12)
                    .fontColor(AppColors.textSecondary)

                  // 进度条
                  Progress({ value: task.progress, total: 100, type: ProgressType.Linear })
                    .color(AppColors.hongguoRed)
                    .backgroundColor('rgba(255, 255, 255, 0.15)')
                    .width('100%')
                    .height(4)

                  Row() {
                    Text(task.status === DownloadStatus.DOWNLOADING ? `下载中 ${task.speed}` :
                         task.status === DownloadStatus.PAUSED ? '已暂停' :
                         task.status === DownloadStatus.COMPLETED ? '已完成' : '失败')
                      .fontSize(10)
                      .fontColor(AppColors.textMuted)

                    Blank()

                    Text(`${task.progress}%`)
                      .fontSize(10)
                      .fontColor(AppColors.textSecondary)
                  }
                  .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                // 操作按钮
                Column({ space: 8 }) {
                  if (task.status !== DownloadStatus.COMPLETED) {
                    Button(task.status === DownloadStatus.DOWNLOADING ? '暂停' : '继续')
                      .fontSize(11)
                      .fontColor(AppColors.textPrimary)
                      .backgroundColor(AppColors.bgCard)
                      .height(26)
                      .borderRadius(13)
                      .onClick(() => {
                        this.toggleTask(task);
                      })
                  }

                  Button('删除')
                    .fontSize(11)
                    .fontColor(AppColors.textMuted)
                    .backgroundColor(Color.Transparent)
                    .height(26)
                    .onClick(() => {
                      this.deleteTask(task);
                    })
                }
              }
              .width('100%')
              .padding(AppDimensions.paddingMd)
              .backgroundColor(AppColors.bgCard)
              .borderRadius(AppDimensions.radiusMd)
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .padding(AppDimensions.paddingMd)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
