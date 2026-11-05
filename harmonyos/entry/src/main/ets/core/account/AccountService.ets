import { UserProfile, QRLoginState } from '../../models/Account';

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
    const mockToken = 'qr_' + Date.now();
    return {
      token: mockToken,
      qrCodeUrl: 'https://hongguoduanju.com/login/qrcode?token=' + mockToken,
      status: 'pending'
    };
  }

  /**
   * 轮询扫码状态
   */
  public async checkQrStatus(token: string): Promise<'pending' | 'scanned' | 'confirmed' | 'expired'> {
    return 'pending';
  }

  /**
   * 模拟确认扫码登录（供本地开发与测试）
   */
  public async mockConfirmQr(token: string): Promise<boolean> {
    this.currentUser = {
      userId: 'qr_user_' + Math.floor(Math.random() * 8999 + 1000),
      nickname: '红果VIP会员',
      avatarUrl: '',
      isLoggedIn: true,
      vipStatus: 'VIP有效',
      phoneMasked: '138****8888'
    };
    return true;
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
