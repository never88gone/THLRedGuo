/**
 * 账号与登录相关数据模型
 */
export interface UserProfile {
  userId: string;
  nickname: string;
  avatarUrl: string;
  isLoggedIn: boolean;
  phoneMasked?: string;
  vipStatus?: string;
}

export interface QRLoginState {
  token: string;
  qrCodeUrl: string;
  status: 'pending' | 'scanned' | 'confirmed' | 'expired';
}

export interface AccountSession {
  token: string;
  deviceId: string;
  installId: string;
  expireTime: number;
}
