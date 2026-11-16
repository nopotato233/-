import { AppColors, PAGE_GRADIENT } from '../AppTheme'

@Component
export struct SettingsPage {
  @Consume('pageStack') pageStack: NavPathStack

  build() {
    Column() {

      Stack() {
        Circle()
          .width(64)
          .height(64)
          .backgroundColor(AppColors.sage)
        Text('探')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.white)
      }
      .shadow({ radius: 16, color: 'rgba(99, 145, 138, 0.35)', offsetX: 0, offsetY: 8 })
      .margin({ top: 56 })

      Text('探步')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.ink)
        .letterSpacing(2)
        .margin({ top: 18 })

      Text('设置与帮助')
        .fontSize(16)
        .fontColor(AppColors.stone)
        .margin({ top: 8 })

      Blank()

      Button('开始识别')
        .width('86%')
        .height(76)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.white)
        .backgroundColor(AppColors.sage)
        .borderRadius(22)
        .shadow(AppColors.shadowButton)
        .onClick(() => {
          this.pageStack.pushPath({ name: 'CameraPage' })
        })
        .margin({ bottom: 18 })

      Button('使用说明')
        .width('86%')
        .height(66)
        .fontSize(21)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.ink)
        .backgroundColor(AppColors.card)
        .borderRadius(20)
        .border({ width: 1, color: AppColors.line })
        .shadow(AppColors.shadowCard)
        .onClick(() => {
          this.pageStack.clear()
        })
        .margin({ bottom: 18 })

      Button('设置')
        .width('86%')
        .height(66)
        .fontSize(21)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.ink)
        .backgroundColor(AppColors.card)
        .borderRadius(20)
        .border({ width: 1, color: AppColors.line })
        .shadow(AppColors.shadowCard)

      Blank()

      Text('看见环境，听见世界')
        .fontSize(14)
        .fontColor(AppColors.mist)
        .margin({ bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 160, colors: PAGE_GRADIENT })
    .alignItems(HorizontalAlign.Center)
  }
}