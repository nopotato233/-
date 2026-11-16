import { deviceInfo } from "@kit.BasicServicesKit"
import { AppColors } from '../AppTheme'

@Component
export struct BreathingCircle {
  @State private coreScale: number = 1.0
  @State private coreOpacity: number = 0.92
  @State private haloOpacity: number = 0.16
  @State private rippleScale: number = 1.0
  @State private rippleOpacity: number = 0.26

  aboutToAppear(): void {
    // 核心圆 + 光晕：同节奏呼吸
    this.getUIContext().animateTo({
      duration: 1800,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.coreScale = 1.08
      this.coreOpacity = 1.0
      this.haloOpacity = 0.06
    })

    // 外层涟漪：延迟 400ms，错开节奏持续向外扩散
    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 1800,
        curve: Curve.EaseOut,
        iterations: -1,
        playMode: PlayMode.Normal
      }, () => {
        this.rippleScale = 1.45
        this.rippleOpacity = 0
      })
    }, 400)
  }

  build() {
    Stack() {

      if (deviceInfo.apiAvailable('26.0.0')) {
        Circle()
          .width(150).height(150)
          .fill(AppColors.sage)
          .opacity(this.rippleOpacity)
          .scale({ x: this.rippleScale, y: this.rippleScale })
      } else {
        Circle()
          .width(150).height(150)
          .backgroundColor(AppColors.sage)
          .opacity(this.rippleOpacity)
          .scale({ x: this.rippleScale, y: this.rippleScale })
      }

      if (deviceInfo.apiAvailable('26.0.0')) {
        Circle()
          .width(150).height(150)
          .fill(AppColors.sage)
          .opacity(this.haloOpacity)
          .scale({ x: this.coreScale, y: this.coreScale })
      } else {
        Circle()
          .width(150).height(150)
          .backgroundColor(AppColors.sage)
          .opacity(this.haloOpacity)
          .scale({ x: this.coreScale, y: this.coreScale })
      }

      if (deviceInfo.apiAvailable('26.0.0')) {
        Circle()
          .width(116).height(116)
          .radialGradient({
            center: [40, 36],
            radius: 130,
            colors: [
              [AppColors.sageLight, 0.0],
              [AppColors.sage, 0.55],
              [AppColors.sageDeep, 1.0]
            ]
          })
          .opacity(this.coreOpacity)
          .scale({ x: this.coreScale, y: this.coreScale })
          .shadow({ radius: 26, color: 'rgba(99, 145, 138, 0.45)', offsetX: 0, offsetY: 12 })
      } else {
        Circle()
          .width(116).height(116)
          .backgroundColor(AppColors.sage)
          .opacity(this.coreOpacity)
          .scale({ x: this.coreScale, y: this.coreScale })
          .shadow({ radius: 26, color: 'rgba(99, 145, 138, 0.45)', offsetX: 0, offsetY: 12 })
      }

      Text('探步')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.white)
        .letterSpacing(2)
    }
    .width(190)
    .height(190)
  }
}