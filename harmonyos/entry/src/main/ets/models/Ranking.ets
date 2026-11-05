/**
 * 榜单数据条目
 */
export class RankingItem {
  dramaId: string = '';
  rank: number = 0;
  title: string = '';
  coverUrl: string = '';
  heat: string = '';
  trend: string = '';
  remarks: string = '';

  constructor(dramaId: string, rank: number, title: string, coverUrl: string, heat: string, trend: string, remarks: string) {
    this.dramaId = dramaId;
    this.rank = rank;
    this.title = title;
    this.coverUrl = coverUrl;
    this.heat = heat;
    this.trend = trend;
    this.remarks = remarks;
  }
}

/**
 * 榜单数据模型
 */
export interface RankingBoard {
  boardId: string;
  title: string;
  subTitle?: string;
  items: RankingItem[];
}
