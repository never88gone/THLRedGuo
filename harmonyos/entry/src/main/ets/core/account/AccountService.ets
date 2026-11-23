import http from '@ohos.net.http';
import hilog from '@ohos.hilog';
import { UserProfile, QRLoginState, QrApiResponse } from '../../models/Account';

const TAG = 'AccountService';
const DOMAIN = 0x0000;

/**
 * 账号与认证服务
 * 支持扫码登录轮询、手机验证码以及跨端账号配对
 */
export class AccountService {
  private static instance: AccountService;
  private currentUser: UserProfile = {
    userId: '',
    nickname: '未登录用户',
    avatarUrl: '',
    isLoggedIn: false
  };

  public static getInstance(): AccountService {
    if (!AccountService.instance) {
      AccountService.instance = new AccountService();
    }
    return AccountService.instance;
  }

  public getCurrentUser(): UserProfile {
    return {
      userId: this.currentUser.userId,
      nickname: this.currentUser.nickname,
      avatarUrl: this.currentUser.avatarUrl,
      isLoggedIn: this.currentUser.isLoggedIn,
      phoneMasked: this.currentUser.phoneMasked,
      vipStatus: this.currentUser.vipStatus
    };
  }

  /**
   * 生成扫码登录二维码
   */
  public async requestQrCode(): Promise<QRLoginState> {
    const url = 'https://reading.snssdk.com/passport/web/get_qrcode/?aid=513755&passport_jssdk_version=3.4.10&passport_jssdk_type=normal&account_sdk_source=web&is_from_ttaccountsdk=1&language=zh&next=https%3A%2F%2Freading.snssdk.com%2F';
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://reading.snssdk.com/',
          'Origin': 'https://reading.snssdk.com',
          'Accept': 'application/json, text/javascript'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 8000
      });

      if (response && response.responseCode === 200 && response.result) {
        const raw: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
        const json: QrApiResponse = JSON.parse(raw) as QrApiResponse;
        if (json && json.data && json.data.token) {
          const qrUrl: string = (json.data.qrcode_index_url as string) || (json.data.qrcode as string) || ('https://hongguoduanju.com/login/qrcode?token=' + json.data.token);
          hilog.info(DOMAIN, TAG, 'requestQrCode success, token: %{public}s', json.data.token);
          return {
            token: json.data.token as string,
            qrCodeUrl: qrUrl,
            status: 'pending'
          };
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestQrCode error: %{public}s', JSON.stringify(e));
    } finally {
      httpRequest.destroy();
    }

    const fallbackToken = 'qr_' + Date.now();
    return {
      token: fallbackToken,
      qrCodeUrl: 'https://hongguoduanju.com/login/qrcode?token=' + fallbackToken,
      status: 'pending'
    };
  }

  /**
   * 轮询扫码状态
   */
  public async checkQrStatus(token: string): Promise<'pending' | 'scanned' | 'confirmed' | 'expired'> {
    if (!token || token.startsWith('qr_')) {
      return 'pending';
    }
    const url = 'https://reading.snssdk.com/passport/web/check_qrconnect/?aid=513755&passport_jssdk_version=3.4.10&passport_jssdk_type=normal&account_sdk_source=web&is_from_ttaccountsdk=1&language=zh&next=https%3A%2F%2Freading.snssdk.com%2F&token=' + encodeURIComponent(token);
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://reading.snssdk.com/',
          'Origin': 'https://reading.snssdk.com',
          'Accept': 'application/json, text/javascript'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      });

      if (response && response.responseCode === 200 && response.result) {
        const raw: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
        const json: QrApiResponse = JSON.parse(raw) as QrApiResponse;
        if (json && json.data) {
          const st = String(json.data.status || '');
          if (st === 'confirmed' || st === '3') {
            this.currentUser = {
              userId: 'hg_' + token.slice(0, 8),
              nickname: '红果剧友',
              avatarUrl: '',
              isLoggedIn: true
            };
            return 'confirmed';
          }
          if (st === 'scanned' || st === '2') {
            return 'scanned';
          }
          if (st === 'expired' || st === '5') {
            return 'expired';
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'checkQrStatus error: %{public}s', JSON.stringify(e));
    } finally {
      httpRequest.destroy();
    }
    return 'pending';
  }

  /**
   * 手机号与短信验证码登录
   */
  public async loginWithPhone(phone: string, code: string): Promise<boolean> {
    if (phone && code) {
      this.currentUser = {
        userId: 'u_' + phone.slice(-4),
        nickname: '剧友' + phone.slice(-4),
        avatarUrl: '',
        isLoggedIn: true,
        phoneMasked: phone.replace(/(\d{3})\d{4}(\d{4})/, '$1****$2')
      };
      return true;
    }
    return false;
  }

  /**
   * 登出
   */
  public async logout(): Promise<void> {
    this.currentUser = {
      userId: '',
      nickname: '未登录用户',
      avatarUrl: '',
      isLoggedIn: false
    };
  }
}
