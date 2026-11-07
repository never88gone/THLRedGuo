import http from '@ohos.net.http';
import hilog from '@ohos.hilog';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import pasteboard from '@ohos.pasteboard';
import { Constants } from '../../common/Constants';

const TAG = 'AppUpdateService';
const DOMAIN = 0x0000;

export interface UpdateAsset {
  name: string;
  downloadUrl: string;
  sizeBytes: number;
}

export interface AppUpdateInfo {
  currentVersion: string;
  currentBuild: string;
  remoteVersion: string;
  remoteBuild: string;
  remoteTagName: string;
  title: string;
  releaseNotes: string;
  htmlUrl: string;
  hasUpdate: boolean;
  primaryAsset?: UpdateAsset;
}

export class AppUpdateService {
  private static instance: AppUpdateService;
  static readonly GITHUB_RELEASES_API = 'https://api.github.com/repos/never88gone/THLRedGuo/releases/latest';

  public static getInstance(): AppUpdateService {
    if (!AppUpdateService.instance) {
      AppUpdateService.instance = new AppUpdateService();
    }
    return AppUpdateService.instance;
  }

  /**
   * 检查 GitHub Releases 最新版本
   */
  async checkUpdate(overrideCurrentVersion?: string, overrideCurrentBuild?: string): Promise<AppUpdateInfo> {
    const curVer = overrideCurrentVersion || Constants.APP_VERSION || '1.0.0';
    const curBuild = overrideCurrentBuild || Constants.APP_BUILD_NUMBER || '263111341';

    const req = http.createHttp();
    try {
      const response = await req.request(AppUpdateService.GITHUB_RELEASES_API, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': `THLRedGuo-UpdateChecker/${curVer}`
        },
        readTimeout: 12000,
        connectTimeout: 8000
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      const rawJson = typeof response.result === 'string'
        ? JSON.parse(response.result) as Record<string, Object>
        : response.result as Record<string, Object>;

      return this.parseReleaseJson(rawJson, curVer, curBuild);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'checkUpdate error: %{public}s', JSON.stringify(e));
      throw new Error(`checkUpdate failed: ${JSON.stringify(e)}`);
    } finally {
      try {
        req.destroy();
      } catch (_) {}
    }
  }

  parseReleaseJson(json: Record<string, Object>, curVer: string, curBuild: string): AppUpdateInfo {
    const tagName = (json['tag_name'] as string) || '';
    const title = (json['name'] as string) || tagName;
    const body = (json['body'] as string) || '';
    const htmlUrl = (json['html_url'] as string) || 'https://github.com/never88gone/THLRedGuo/releases';

    const remoteVersion = this.cleanVersion(tagName);
    const remoteBuild = this.extractBuildNumber(title, tagName, body);

    const hasUpdate = this.isNewerVersion(curVer, curBuild, remoteVersion, remoteBuild);

    const rawAssets = (json['assets'] as Array<Record<string, Object>>) || [];
    let primaryAsset: UpdateAsset | undefined = undefined;

    for (const item of rawAssets) {
      const name = (item['name'] as string) || '';
      const downloadUrl = (item['browser_download_url'] as string) || '';
      const sizeBytes = (item['size'] as number) || 0;
      if (name.toLowerCase().endsWith('.hap')) {
        primaryAsset = { name, downloadUrl, sizeBytes };
        break;
      }
    }

    return {
      currentVersion: curVer,
      currentBuild: curBuild,
      remoteVersion,
      remoteBuild,
      remoteTagName: tagName,
      title,
      releaseNotes: body,
      htmlUrl,
      hasUpdate,
      primaryAsset
    };
  }

  cleanVersion(raw: string): string {
    let v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1).trim();
    }
    if (v.includes('+')) {
      v = v.split('+')[0];
    }
    if (v.includes('-')) {
      v = v.split('-')[0];
    }
    return v;
  }

  extractBuildNumber(title: string, tag: string, body: string): string {
    const titleMatch = title.match(/Build\s*(\d+)/i);
    if (titleMatch && titleMatch[1]) {
      return titleMatch[1];
    }
    const tagMatch = tag.match(/\+(\d+)/) || tag.match(/-(\d{6,})/);
    if (tagMatch && tagMatch[1]) {
      return tagMatch[1];
    }
    const bodyMatch = body.match(/Build\s*(\d+)/i);
    if (bodyMatch && bodyMatch[1]) {
      return bodyMatch[1];
    }
    return '';
  }

  isNewerVersion(curVer: string, curBuild: string, remVer: string, remBuild: string): boolean {
    const curParts = this.parseVersionParts(curVer);
    const remParts = this.parseVersionParts(remVer);
    const maxLen = Math.max(curParts.length, remParts.length);

    for (let i = 0; i < maxLen; i++) {
      const c = i < curParts.length ? curParts[i] : 0;
      const r = i < remParts.length ? remParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }

    const cBuild = parseInt(curBuild, 10);
    const rBuild = parseInt(remBuild, 10);
    if (!isNaN(cBuild) && !isNaN(rBuild)) {
      return rBuild > cBuild;
    }
    return false;
  }

  private parseVersionParts(version: string): number[] {
    const clean = this.cleanVersion(version);
    if (!clean) return [0];
    return clean.split('.').map(p => parseInt(p, 10) || 0);
  }

  openUpdateUrl(context: common.UIAbilityContext, url: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };
      context.startAbility(want).catch(() => {
        this.copyToClipboard(url);
      });
    } catch (_) {
      this.copyToClipboard(url);
    }
  }

  copyToClipboard(text: string): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制链接到剪贴板，可在浏览器中打开' });
    } catch (_) {
      promptAction.showToast({ message: '复制失败，请在浏览器中访问 GitHub Releases' });
    }
  }
}
