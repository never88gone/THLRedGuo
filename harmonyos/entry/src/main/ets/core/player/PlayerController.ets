import media from '@ohos.multimedia.media';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import { PlayResult, PlaybackState } from '../../models/Episode';
import { CencDecryptor } from './CencDecryptor';
import { LocalStore } from '../store/LocalStore';

const TAG = 'PlayerController';
const DOMAIN = 0x0000;

export type PlaybackCallback = (state: PlaybackState) => void;

/**
 * 原生视频播放器封装
 * 基于 HarmonyOS NEXT 官方 AVPlayer 媒体框架
 * 支持 CENC AES-128-CTR 硬件加速解密播放与本地极速起播
 */
export class PlayerController {
  private avPlayer: media.AVPlayer | null = null;
  private surfaceId: string = '';
  private currentFile: fs.File | null = null;
  private currentState: PlaybackState = {
    dramaId: '',
    dramaTitle: '',
    episodeIndex: 1,
    currentPosition: 0,
    duration: 0,
    isPlaying: false,
    isBuffering: false,
    speed: 1.0,
    autoAdvance: true
  };
  private callback: PlaybackCallback | null = null;
  private onCompletedCallback: (() => void) | null = null;

  public setListener(cb: PlaybackCallback): void {
    this.callback = cb;
  }

  public setOnCompleted(cb: () => void): void {
    this.onCompletedCallback = cb;
  }

  public setSurfaceId(id: string): void {
    this.surfaceId = id;
    if (this.avPlayer && id) {
      this.avPlayer.surfaceId = id;
    }
  }

  /**
   * 初始化播放器
   */
  public async initPlayer(): Promise<void> {
    if (this.avPlayer) return;
    try {
      this.avPlayer = await media.createAVPlayer();
      this.bindEvents();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to create AVPlayer: %{public}s', JSON.stringify(err));
    }
  }

  private bindEvents(): void {
    if (!this.avPlayer) return;

    this.avPlayer.on('stateChange', async (state: string) => {
      hilog.info(DOMAIN, TAG, 'AVPlayer stateChange: %{public}s', state);
      switch (state) {
        case 'initialized':
          if (this.surfaceId) {
            this.avPlayer!.surfaceId = this.surfaceId;
          }
          try {
            this.avPlayer!.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
          } catch (_) {}
          await this.avPlayer!.prepare();
          break;
        case 'prepared':
          this.currentState.duration = this.avPlayer!.duration;
          hilog.info(DOMAIN, TAG, 'AVPlayer prepared, duration: %{public}d ms, calling play()', this.currentState.duration);
          await this.avPlayer!.play();
          this.currentState.isPlaying = true;
          this.currentState.isBuffering = false;
          this.notify();
          break;
        case 'playing':
          hilog.info(DOMAIN, TAG, 'AVPlayer is PLAYING');
          this.currentState.isPlaying = true;
          this.currentState.isBuffering = false;
          this.notify();
          break;
        case 'paused':
          hilog.info(DOMAIN, TAG, 'AVPlayer is PAUSED');
          this.currentState.isPlaying = false;
          this.notify();
          break;
        case 'completed':
          hilog.info(DOMAIN, TAG, 'AVPlayer COMPLETED');
          this.currentState.isPlaying = false;
          this.currentState.isBuffering = false;
          this.notify();
          if (this.currentState.autoAdvance) {
            this.onPlaybackCompleted();
          }
          break;
        case 'error':
          hilog.error(DOMAIN, TAG, 'AVPlayer ERROR state');
          this.currentState.isPlaying = false;
          this.currentState.isBuffering = false;
          this.notify();
          break;
      }
    });

    this.avPlayer.on('timeUpdate', (time: number) => {
      this.currentState.currentPosition = time;
      this.notify();
    });

    this.avPlayer.on('videoSizeChange', (width: number, height: number) => {
      hilog.info(DOMAIN, TAG, 'videoSizeChange: width=%{public}d, height=%{public}d', width, height);
      if (width > 0 && height > 0) {
        this.currentState.videoWidth = width;
        this.currentState.videoHeight = height;
        this.currentState.aspectRatio = width / height;
        this.notify();
      }
    });

    this.avPlayer.on('error', (err) => {
      hilog.error(DOMAIN, TAG, 'AVPlayer error event: %{public}s', JSON.stringify(err));
    });
  }

  /**
   * 加载视频并起播
   */
  public async loadMedia(dramaId: string, dramaTitle: string, epIndex: number, playResult: PlayResult): Promise<void> {
    if (!this.avPlayer) {
      await this.initPlayer();
    }
    this.currentState.dramaId = dramaId;
    this.currentState.dramaTitle = dramaTitle;
    this.currentState.episodeIndex = epIndex;
    this.currentState.currentPosition = 0;
    this.currentState.isPlaying = false;
    this.currentState.isBuffering = true;
    this.notify();

    if (!this.avPlayer) return;

    try {
      if (this.avPlayer.state && this.avPlayer.state !== 'idle') {
        await this.avPlayer.reset();
      }

      if (this.currentFile) {
        try { fs.closeSync(this.currentFile); } catch (_) {}
        this.currentFile = null;
      }

      const ctx = LocalStore.getInstance().getContext();
      if (playResult.decryptionKey && ctx) {
        hilog.info(DOMAIN, TAG, 'Video requires decryption, preparing local file...');
        const localPath = await CencDecryptor.prepareLocalMedia(
          ctx,
          dramaId,
          epIndex,
          playResult.url,
          playResult.headers,
          playResult.decryptionKey
        );
        hilog.info(DOMAIN, TAG, 'Local media ready: %{public}s', localPath);
        const file = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
        this.currentFile = file;
        const stat = fs.statSync(localPath);
        this.avPlayer.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
      } else {
        hilog.info(DOMAIN, TAG, 'Playing plain url: %{public}s', playResult.url.slice(0, 80));
        this.avPlayer.url = playResult.url;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadMedia error: %{public}s', JSON.stringify(e));
      this.currentState.isBuffering = false;
      this.notify();
    }
  }

  public async play(): Promise<void> {
    if (this.avPlayer && !this.currentState.isPlaying) {
      await this.avPlayer.play();
    }
  }

  public async pause(): Promise<void> {
    if (this.avPlayer && this.currentState.isPlaying) {
      await this.avPlayer.pause();
    }
  }

  public async seek(positionMs: number): Promise<void> {
    if (this.avPlayer) {
      await this.avPlayer.seek(positionMs);
    }
  }

  public async setSpeed(speed: number): Promise<void> {
    if (this.avPlayer) {
      await this.avPlayer.setSpeed(speed === 2.0 ? 4 : speed === 1.25 ? 2 : 0);
      this.currentState.speed = speed;
      this.notify();
    }
  }

  public release(): void {
    if (this.currentFile) {
      try { fs.closeSync(this.currentFile); } catch (_) {}
      this.currentFile = null;
    }
    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
    }
  }

  private onPlaybackCompleted(): void {
    if (this.onCompletedCallback) {
      this.onCompletedCallback();
    }
  }

  private notify(): void {
    if (this.callback) {
      this.callback({
        dramaId: this.currentState.dramaId,
        dramaTitle: this.currentState.dramaTitle,
        episodeIndex: this.currentState.episodeIndex,
        currentPosition: this.currentState.currentPosition,
        duration: this.currentState.duration,
        isPlaying: this.currentState.isPlaying,
        isBuffering: this.currentState.isBuffering,
        speed: this.currentState.speed,
        autoAdvance: this.currentState.autoAdvance,
        videoWidth: this.currentState.videoWidth,
        videoHeight: this.currentState.videoHeight,
        aspectRatio: this.currentState.aspectRatio
      });
    }
  }
}
