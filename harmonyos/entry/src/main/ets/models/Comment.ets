/**
 * 评论与回复数据模型
 * 对齐 Flutter CommentItem / CommentPage / CommentReplyItem / CommentReplyPage
 */

export interface CommentItem {
  id: string;
  text: string;
  userName: string;
  userAvatar: string;
  userId: string;
  createTime: number;
  diggCount: number;
  replyCount: number;
}

export interface CommentPage {
  total: number;
  hasMore: boolean;
  cursor: string;
  list: CommentItem[];
}

export interface CommentReplyItem {
  id: string;
  text: string;
  userName: string;
  userAvatar: string;
  userId: string;
  replyToUserName: string;
  createTime: number;
  diggCount: number;
}

export interface CommentReplyPage {
  total: number;
  hasMore: boolean;
  cursor: string;
  list: CommentReplyItem[];
}
