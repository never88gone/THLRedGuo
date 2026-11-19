import { AppColors } from '../../../common/AppColors';
import { AppDimensions } from '../../../common/AppDimensions';
import { DramaDetail, EpisodeInfo } from '../../../models/Drama';
import { CommentItem, CommentReplyItem } from '../../../models/Comment';

function formatCommentTime(ts: number): string {
  if (!ts) return '';
  const sec = ts > 1000000000000 ? Math.floor(ts / 1000) : ts;
  const now = Math.floor(Date.now() / 1000);
  const diff = Math.max(0, now - sec);
  if (diff < 60) return '刚刚';
  if (diff < 3600) return `${Math.floor(diff / 60)}分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}小时前`;
  if (diff < 2592000) return `${Math.floor(diff / 86400)}天前`;
  const d = new Date(sec * 1000);
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${m < 10 ? '0' + m : m}-${day < 10 ? '0' + day : day}`;
}

@Component
export struct PlayerMobilePanelView {
  @Prop currentTab: number = 0; // 0: 选集, 1: 简介, 2: 评论
  @Prop isFavorite: boolean = false;
  @Prop currentEpisodeIndex: number = 1;
  @Prop detail: DramaDetail | null = null;
  @Prop coverUrl: string = '';
  @Prop dramaTitle: string = '';

  // 评论相关属性 (对齐 Flutter CommentSheetView & commit e171586)
  @Prop comments: CommentItem[] = [];
  @Prop totalComments: number = 0;
  @Prop isLoadingComments: boolean = false;
  @Prop hasMoreComments: boolean = false;
  @Prop selectedComment: CommentItem | null = null;
  @Prop replies: CommentReplyItem[] = [];
  @Prop isLoadingReplies: boolean = false;

  @State expandedCommentIds: Record<string, boolean> = {};

  onTabChange: (tab: number) => void = () => {};
  onToggleFavorite: () => void = () => {};
  onSelectEpisode: (epIndex: number) => void = () => {};
  onLoadMoreComments: () => void = () => {};
  onSelectComment: (comment: CommentItem) => void = () => {};
  onBackToComments: () => void = () => {};

  private toggleExpand(commentId: string): void {
    const next: Record<string, boolean> = {};
    for (const key of Object.keys(this.expandedCommentIds)) {
      next[key] = this.expandedCommentIds[key];
    }
    next[commentId] = !next[commentId];
    this.expandedCommentIds = next;
  }

  @Builder
  CommentRow(item: CommentItem) {
    Row({ space: 10 }) {
      // 用户头像
      if (item.userAvatar) {
        Image(item.userAvatar)
          .width(34)
          .height(34)
          .borderRadius(17)
          .objectFit(ImageFit.Cover)
          .backgroundColor(AppColors.bgElevated)
      } else {
        Column() {
          Text((item.userName || '剧')[0])
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.white)
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(AppColors.hongguoRedDark)
        .justifyContent(FlexAlign.Center)
      }

      // 评论主内容
      Column({ space: 4 }) {
        Row() {
          Text(item.userName)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textSecondary)
            .layoutWeight(1)

          // 点赞数
          Row({ space: 3 }) {
            Text('👍')
              .fontSize(11)
            Text(item.diggCount > 0 ? `${item.diggCount}` : '点赞')
              .fontSize(10.5)
              .fontColor(AppColors.textSecondary)
          }
        }
        .width('100%')

        // 评论正文 (对齐 commit a84c246: 超过3行折叠保护)
        Text(item.text)
          .fontSize(13)
          .fontColor(AppColors.textPrimary)
          .lineHeight(19)
          .maxLines(this.expandedCommentIds[item.id] ? 50 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            if (item.text.length > 60) {
              this.toggleExpand(item.id);
            }
          })

        // 底部元信息: 时间 + 查看回复入口
        Row() {
          Text(formatCommentTime(item.createTime))
            .fontSize(11)
            .fontColor(AppColors.textMuted)

          Blank()

          if (item.replyCount > 0) {
            Button({ type: ButtonType.Capsule }) {
              Row({ space: 2 }) {
                Text(`${item.replyCount} 条回复`)
                  .fontSize(10.5)
                  .fontColor(AppColors.hongguoOrange)
                Text('›')
                  .fontSize(12)
                  .fontColor(AppColors.hongguoOrange)
              }
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            }
            .backgroundColor(AppColors.redAlpha12)
            .height(22)
            .onClick(() => {
              this.onSelectComment(item);
            })
          }
        }
        .width('100%')
        .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  ReplyRow(reply: CommentReplyItem) {
    Row({ space: 10 }) {
      if (reply.userAvatar) {
        Image(reply.userAvatar)
          .width(28)
          .height(28)
          .borderRadius(14)
          .objectFit(ImageFit.Cover)
          .backgroundColor(AppColors.bgElevated)
      } else {
        Column() {
          Text((reply.userName || '剧')[0])
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.white)
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(AppColors.bgElevated)
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: 3 }) {
        Row() {
          Text(reply.userName)
            .fontSize(11.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textSecondary)

          if (reply.replyToUserName) {
            Text(' 回复 ')
              .fontSize(11)
              .fontColor(AppColors.textMuted)
            Text(`@${reply.replyToUserName}`)
              .fontSize(11.5)
              .fontColor(AppColors.hongguoGold)
          }

          Blank()

          if (reply.diggCount > 0) {
            Text(`👍 ${reply.diggCount}`)
              .fontSize(10)
              .fontColor(AppColors.textMuted)
          }
        }
        .width('100%')

        Text(reply.text)
          .fontSize(12.5)
          .fontColor(AppColors.textPrimary)
          .lineHeight(18)

        Text(formatCommentTime(reply.createTime))
          .fontSize(10)
          .fontColor(AppColors.textMuted)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Column() {
      // Tab 切换导航条：选集 / 简介 / 评论 / 右侧追剧按钮
      Row() {
        // Tab 0: 选集
        Column() {
          Text(`选集${this.detail?.episodeCount ? ` (${this.detail.episodeCount})` : ''}`)
            .fontSize(13.5)
            .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? AppColors.white : AppColors.textSecondary)
          if (this.currentTab === 0) {
            Column()
              .width(22)
              .height(3)
              .backgroundColor(AppColors.hongguoRed)
              .borderRadius(1.5)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .onClick(() => {
          this.onTabChange(0);
        })

        // Tab 1: 简介
        Column() {
          Text('简介')
            .fontSize(13.5)
            .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 1 ? AppColors.white : AppColors.textSecondary)
          if (this.currentTab === 1) {
            Column()
              .width(22)
              .height(3)
              .backgroundColor(AppColors.hongguoRed)
              .borderRadius(1.5)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .onClick(() => {
          this.onTabChange(1);
        })

        // Tab 2: 评论 (对齐 Flutter 逆向评论功能)
        Column() {
          Text(`评论${this.totalComments > 0 ? ` (${this.totalComments})` : ''}`)
            .fontSize(13.5)
            .fontWeight(this.currentTab === 2 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 2 ? AppColors.white : AppColors.textSecondary)
          if (this.currentTab === 2) {
            Column()
              .width(22)
              .height(3)
              .backgroundColor(AppColors.hongguoRed)
              .borderRadius(1.5)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .onClick(() => {
          this.onTabChange(2);
        })

        // 追剧状态按钮 (即时反馈)
        Button(this.isFavorite ? '❤️ 已追剧' : '🤍 追剧')
          .fontSize(11.5)
          .fontColor(this.isFavorite ? AppColors.hongguoRed : AppColors.textPrimary)
          .backgroundColor(this.isFavorite ? AppColors.redAlpha15 : AppColors.bgElevated)
          .height(28)
          .borderRadius(14)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.onToggleFavorite();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 6 })
      .backgroundColor(AppColors.bgDark)

      // 内容区
      if (this.currentTab === 0) {
        // 选集列表网格 (5列网格，当前播放集高亮为红果红)
        if (this.detail && this.detail.episodes.length > 0) {
          Grid() {
            ForEach(this.detail.episodes, (ep: EpisodeInfo) => {
              GridItem() {
                Button(`${ep.index}`)
                  .fontSize(13)
                  .fontWeight(this.currentEpisodeIndex === ep.index ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.currentEpisodeIndex === ep.index ? AppColors.white : AppColors.textPrimary)
                  .backgroundColor(this.currentEpisodeIndex === ep.index ? AppColors.hongguoRed : AppColors.bgCard)
                  .width('100%')
                  .height(44)
                  .borderRadius(AppDimensions.radiusSm)
                  .onClick(() => {
                    this.onSelectEpisode(ep.index);
                  })
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
          .layoutWeight(1)
        } else {
          Column() {
            Text('正在获取短剧分集列表...')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      } else if (this.currentTab === 1) {
        // 简介内容 (海报缩略图、多维元信息、剧情简介全文)
        Scroll() {
          Column({ space: 14 }) {
            Row({ space: 12 }) {
              Image(this.coverUrl)
                .width(72)
                .height(96)
                .borderRadius(AppDimensions.radiusSm)
                .objectFit(ImageFit.Cover)
                .backgroundColor(AppColors.bgCard)

              Column({ space: 6 }) {
                Text(this.dramaTitle)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)
                Text(this.detail?.remarks || '连载中')
                  .fontSize(12)
                  .fontColor(AppColors.hongguoGold)
                Text(`共 ${this.detail?.episodeCount || 0} 集`)
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }

            Text('剧情简介')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text(this.detail?.intro || '暂无详细简介。')
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .lineHeight(20)
          }
          .padding(16)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        // Tab 2: 评论与回复视图
        Column() {
          if (this.selectedComment !== null) {
            // A. 二级回复抽屉式子视图
            Row({ space: 8 }) {
              Button({ type: ButtonType.Circle }) {
                Text('←')
                  .fontSize(15)
                  .fontColor(AppColors.white)
              }
              .width(28)
              .height(28)
              .backgroundColor(AppColors.whiteAlpha10)
              .onClick(() => {
                this.onBackToComments();
              })

              Text(`回复详情 (${this.replies.length})`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.textPrimary)

              Blank()
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            // 置顶主评论
            Column() {
              this.CommentRow(this.selectedComment)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 6 })
            .border({ width: { bottom: 0.8 }, color: AppColors.whiteAlpha08 })

            // 二级回复列表
            if (this.isLoadingReplies && this.replies.length === 0) {
              Column({ space: 8 }) {
                Text('正在拉取回复...')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else if (this.replies.length === 0) {
              Column({ space: 6 }) {
                Text('暂无更多回复')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              List({ space: 6 }) {
                ForEach(this.replies, (rep: CommentReplyItem) => {
                  ListItem() {
                    this.ReplyRow(rep)
                  }
                })
              }
              .layoutWeight(1)
              .width('100%')
              .padding({ left: 24, right: 16, top: 6, bottom: 16 })
            }
          } else {
            // B. 一级短剧评论主列表
            if (this.isLoadingComments && this.comments.length === 0) {
              Column({ space: 8 }) {
                Text('正在拉取热评...')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else if (this.comments.length === 0) {
              Column({ space: 10 }) {
                Text('💬')
                  .fontSize(36)
                Text('暂无评论，快来抢首评吧~')
                  .fontSize(13)
                  .fontColor(AppColors.textSecondary)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              List({ space: 8 }) {
                ForEach(this.comments, (item: CommentItem) => {
                  ListItem() {
                    this.CommentRow(item)
                  }
                })

                if (this.hasMoreComments) {
                  ListItem() {
                    Row() {
                      Button(this.isLoadingComments ? '正在加载...' : '加载更多评论')
                        .fontSize(11.5)
                        .fontColor(AppColors.textSecondary)
                        .backgroundColor(AppColors.transparent)
                        .onClick(() => {
                          this.onLoadMoreComments();
                        })
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Center)
                    .padding(8)
                  }
                }
              }
              .layoutWeight(1)
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 16 })
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
