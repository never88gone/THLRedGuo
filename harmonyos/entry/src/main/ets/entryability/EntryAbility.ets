import UIAbility from '@ohos.app.ability.UIAbility';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import window from '@ohos.window';
import hilog from '@ohos.hilog';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { LocalStore } from '../core/store/LocalStore';
import { CatPawJsRuntime } from '../core/js/CatPawJsRuntime';

const TAG = 'EntryAbility';
const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    LocalStore.getInstance().init(this.context);
    CatPawJsRuntime.getInstance().init(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    try {
      let windowClass = windowStage.getMainWindowSync();
      try {
        windowClass.setWindowLayoutFullScreen(true);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen error: %{public}s', JSON.stringify(e));
      }
      try {
        windowClass.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000'
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties error: %{public}s', JSON.stringify(e));
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getMainWindowSync error: %{public}s', JSON.stringify(e));
    }

    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content. Data: %{public}s', JSON.stringify(data) ?? '');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
