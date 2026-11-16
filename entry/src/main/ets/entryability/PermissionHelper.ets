import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

async function requestCameraPermission(context: common.UIAbilityContext): Promise<boolean> {
  const atManager = abilityAccessCtrl.createAtManager();
  const permissions: Permissions[] = ['ohos.permission.CAMERA'];

  try {
    const result = await atManager.requestPermissionsFromUser(context, permissions);
    // authResults[0] === 0 表示授权成功
    if (result.authResults[0] === 0) {
      console.info('相机权限已授权');
      return true;
    } else {
      console.error('用户拒绝了相机权限');
      return false;
    }
  } catch (err) {
    const e = err as BusinessError;
    console.error(`权限申请失败: ${e.code} ${e.message}`);
    return false;
  }
}

export { requestCameraPermission };