import { DownloadTask, DownloadStatus } from '../../models/Download';

export type DownloadListener = (tasks: DownloadTask[]) => void;

/**
 * 离线视频下载管理器
 */
export class DownloadManager {
  private static instance: DownloadManager;
  private tasks: Map<string, DownloadTask> = new Map();
  private listeners: Set<DownloadListener> = new Set();

  public static getInstance(): DownloadManager {
    if (!DownloadManager.instance) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  public addListener(listener: DownloadListener): void {
    this.listeners.add(listener);
    listener(Array.from(this.tasks.values()));
  }

  public removeListener(listener: DownloadListener): void {
    this.listeners.delete(listener);
  }

  public getTasks(): DownloadTask[] {
    return Array.from(this.tasks.values());
  }

  /**
   * 提交下载任务
   */
  public enqueue(
    dramaId: string,
    dramaTitle: string,
    dramaCover: string,
    episodeIndex: number,
    episodeTitle: string,
    mediaUrl: string
  ): void {
    const taskId = `${dramaId}_${episodeIndex}`;
    if (this.tasks.has(taskId)) return;

    const task: DownloadTask = {
      id: taskId,
      dramaId,
      dramaTitle,
      dramaCover,
      episodeIndex,
      episodeTitle,
      mediaUrl,
      status: DownloadStatus.DOWNLOADING,
      progress: 0,
      totalBytes: 0,
      receivedBytes: 0,
      speed: '0 KB/s'
    };

    this.tasks.set(taskId, task);
    this.notify();
  }

  public pause(taskId: string): void {
    const task = this.tasks.get(taskId);
    if (task && task.status === DownloadStatus.DOWNLOADING) {
      task.status = DownloadStatus.PAUSED;
      this.notify();
    }
  }

  public resume(taskId: string): void {
    const task = this.tasks.get(taskId);
    if (task && task.status === DownloadStatus.PAUSED) {
      task.status = DownloadStatus.DOWNLOADING;
      this.notify();
    }
  }

  public delete(taskId: string): void {
    this.tasks.delete(taskId);
    this.notify();
  }

  private notify(): void {
    const list = Array.from(this.tasks.values());
    this.listeners.forEach(l => l(list));
  }
}
