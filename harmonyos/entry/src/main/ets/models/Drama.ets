/**
 * 短剧核心数据模型
 */
export interface DramaItem {
  id: string;              // 对应 vod_id
  title: string;           // 对应 vod_name
  coverUrl: string;        // 对应 vod_pic
  remarks: string;         // 对应 vod_remarks (如 "全80集")
  episodeCount?: number;   // 总集数
  intro?: string;          // 对应 vod_content
  tags?: string[];         // 分类标签
  source?: string;         // 数据源 ID
  author?: string;         // 创作者/主演
  heat?: string;           // 热度值
}

export interface SeasonInfo {
  seasonId: string;
  seasonName: string;
  seasonIndex: number;
  isSelected: boolean;
}

export interface DramaDetail extends DramaItem {
  seasons: SeasonInfo[];
  episodes: EpisodeInfo[];
  currentSeasonId?: string;
  isFavorited?: boolean;
  lastWatchEpisode?: number;
  lastWatchPosition?: number;
}

export interface EpisodeInfo {
  index: number;           // 集数索引 (1, 2, 3...)
  title: string;           // 如 "第1集"
  rawUrl: string;          // 播放目标 raw 地址
  flag?: string;           // 播放源标识 (如 "hongguo")
  isFree?: boolean;        // 是否免费集
  isCurrent?: boolean;     // 是否当前正在播放
}
