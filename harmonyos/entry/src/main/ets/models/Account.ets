/**
 * 账号与登录相关数据模型
 */
export interface UserProfile {
  userId: string;
  nickname: string;
  avatarUrl: string;
  isLoggedIn: boolean;
  phoneMasked?: string;
  vipStatus?: string;
}

export interface QRLoginState {
  token: string;
  qrCodeUrl: string;
  status: 'pending' | 'scanned' | 'confirmed' | 'expired';
}

export interface AccountSession {
  token: string;
  deviceId: string;
  installId: string;
  expireTime: number;
}

export interface QrDataPayload {
  token?: string;
  qrcode_index_url?: string;
  qrcode?: string;
  status?: string;
  expire_time?: number;
}

export interface QrApiResponse {
  data?: QrDataPayload;
  message?: string;
}

/**
 * 点赞视频条目 (对齐 Flutter HongguoLikedVideo)
 */
export interface LikedVideoItem {
  id: string;
  title: string;
  seriesId: string;
  cover: string;
  description: string;
  episode?: number;
  episodes: number;
  kind: string; // 'series' | 'episode'
  likedAt?: number;
}

export interface LikedVideoPage {
  items: LikedVideoItem[];
  hasMore: boolean;
  nextOffset?: number;
  unsupportedCount: number;
}

/**
 * 关注主播条目 (对齐 Flutter Anchor)
 */
export interface AnchorItem {
  id: string;
  name: string;
  avatar: string;
  bio: string;
  fansCount?: number;
  worksCount?: number;
  isFollowed?: boolean;
  officialFollowing?: boolean;
  canFollow?: boolean;
  relativeType?: number;
}

export interface FollowingCreatorsPage {
  creators: AnchorItem[];
  hasMore: boolean;
  nextOffset?: number;
  followingDouyinNextOffset?: number;
}

/**
 * 云端追剧与观看历史条目 (对齐 Flutter WatchEntry)
 */
export interface CloudWatchEntry {
  dramaId: string;
  dramaTitle: string;
  coverUrl: string;
  episodeIndex: number;
  episodes: number;
  updatedAt: number;
}
