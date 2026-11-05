/**
 * 视频播放解析结果数据模型
 */
export interface PlayResult {
  url: string;                          // 真实流媒体播放地址 (如 mp4/m3u8)
  headers: Record<string, string>;      // 防盗链与鉴权请求头 (Referer, User-Agent 等)
  danmakuUrl?: string;                  // 弹幕链接
  duration?: number;                    // 视频预估总时长 (ms)
  width?: number;                       // 宽
  height?: number;                      // 高
  isEncrypted?: boolean;                // 是否涉及加密
  decryptionKey?: string;               // CENC AES-128 解密密钥
  mediaBytes?: number;                  // 视频总字节数
}

export interface PlaybackState {
  dramaId: string;
  dramaTitle: string;
  episodeIndex: number;
  currentPosition: number;              // 毫秒
  duration: number;                     // 毫秒
  isPlaying: boolean;
  isBuffering: boolean;
  speed: number;                        // 播放倍速 (1.0, 1.25, 1.5, 2.0)
  autoAdvance: boolean;                 // 自动连播下一集
}
