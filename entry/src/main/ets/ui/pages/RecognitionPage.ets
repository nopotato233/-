import { BreathingCircle } from '../components/BreathingCircle'
import { AppColors, PAGE_GRADIENT } from '../AppTheme'

@Component
export struct RecognitionPage {
  build() {
    Stack() {
      // 背景装饰圆
      Circle()
        .width(260)
        .height(260)
        .backgroundColor(AppColors.sage)
        .opacity(0.06)
        .position({ x: '-22%', y: '-6%' })
      Circle()
        .width(200)
        .height(200)
        .backgroundColor(AppColors.sageDeep)
        .opacity(0.05)
        .position({ x: '74%', y: '78%' })

      Column() {
        // 状态胶囊
        Row() {
          Circle()
            .width(9)
            .height(9)
            .backgroundColor(AppColors.sage)
          Text('识别进行中')
            .fontSize(14)
            .fontColor(AppColors.sageDeep)
            .margin({ left: 8 })
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('rgba(246, 247, 244, 0.7)')
        .borderRadius(18)

        BreathingCircle()
          .margin({ top: 64 })

        Text('正在识别环境')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.ink)
          .margin({ top: 52 })

        Text('语音辅助已开启，请缓慢移动手机')
          .fontSize(15)
          .fontColor(AppColors.stone)
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 160, colors: PAGE_GRADIENT })
  }
}