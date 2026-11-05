/**
 * 离线下载任务数据模型
 */
export enum DownloadStatus {
  IDLE = 0,
  DOWNLOADING = 1,
  PAUSED = 2,
  COMPLETED = 3,
  FAILED = 4
}

export interface DownloadTask {
  id: string;              // 任务唯一标识 (dramaId_episodeIndex)
  dramaId: string;
  dramaTitle: string;
  dramaCover: string;
  episodeIndex: number;
  episodeTitle: string;
  mediaUrl: string;
  localFilePath?: string;
  status: DownloadStatus;
  progress: number;        // 0 - 100
  totalBytes: number;
  receivedBytes: number;
  speed: string;
  errorMessage?: string;
}
