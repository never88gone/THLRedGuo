/**
 * 规范化剧集封面 URL，解决字节跳动/红果官方接口返回 image/heic 导致无法解码的问题。
 * 将 novel-pic 及 HEIC 模板自动映射到官方高兼容度 JPEG/PNG CDN 直链。
 */
export function normalizeCoverUrl(rawUrl: string): string {
  if (!rawUrl || typeof rawUrl !== 'string') return '';
  const trimmed = rawUrl.trim();
  if (!trimmed) return '';

  // novel-pic 匹配替换
  const match = trimmed.match(/novel-pic\/([a-zA-Z0-9_-]+)/);
  if (match && match[1]) {
    const picId = match[1];
    return `https://p3-novel.byteimg.com/novel-pic/${picId}~tplv-shrink:640:0.image`;
  }

  // heic 格式替换为兼容的 image 格式
  if (trimmed.indexOf('.heic') >= 0) {
    return trimmed.replace(/\.heic/g, '.image');
  }

  // 确保 http 升级为 https 避免明文传输拦截
  if (trimmed.startsWith('http://')) {
    return 'https://' + trimmed.substring(7);
  }

  return trimmed;
}
