/**
 * 探步 · 全局设计令牌
 * -------------------------------------------------------
 * 主色板：#30363A（墨）/ #D5D9D5（纸）/ #63918A（青）
 * 其余颜色均由三色派生调和，保证全应用视觉统一。
 */

export class AppColors {
  // ---------- 主色板 ----------
  static readonly ink: string = '#30363A'    // 主深色：大标题 / 深色悬浮层
  static readonly paper: string = '#D5D9D5'  // 页面背景基色
  static readonly sage: string = '#63918A'   // 品牌主色：主按钮 / 强调态

  // ---------- 派生色（由主色调和） ----------
  static readonly sageDeep: string = '#4F7A73'   // 深一档的青：按压态 / 渐变末端
  static readonly sageLight: string = '#8FB1AA'  // 亮一档的青：深底上的点缀
  static readonly sageSoft: string = '#E4EBE8'   // 极浅青底：选中态 / 信息卡
  static readonly card: string = '#F6F7F4'       // 卡片底（暖白，比纯白更柔和）
  static readonly stone: string = '#68746D'      // 次要文字（替代偏蓝的 #667085）
  static readonly mist: string = '#97A19A'       // 辅助文字 / 弱提示
  static readonly line: string = '#C8CEC7'       // 分隔线 / 描边
  static readonly white: string = '#FFFFFF'

  // ---------- 相机页悬浮层 ----------
  static readonly overlay: string = 'rgba(48, 54, 58, 0.55)'     // 半透明墨底（状态胶囊）
  static readonly overlayDeep: string = 'rgba(48, 54, 58, 0.92)' // 深墨底（退出按钮）

  // ---------- 常用阴影 ----------
  static readonly shadowCard: ShadowOptions = {
    radius: 18, color: 'rgba(48, 54, 58, 0.08)', offsetX: 0, offsetY: 6
  }
  static readonly shadowButton: ShadowOptions = {
    radius: 16, color: 'rgba(99, 145, 138, 0.35)', offsetX: 0, offsetY: 8
  }
}

/** 页面背景渐变：以 paper 为基底的微妙过渡 */
export const PAGE_GRADIENT: Array<[ResourceColor, number]> = [
  ['#DEE2DD', 0.0],
  ['#D5D9D5', 0.55],
  ['#CBD2CB', 1.0]
]