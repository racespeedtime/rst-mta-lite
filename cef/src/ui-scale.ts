/**
 * CEF 逻辑分辨率缩放。
 *
 * 以 1080p 为 1.0x：
 * - 720p  -> 0.75x（下限）
 * - 1080p -> 1.0x
 * - 1440p -> 1.333x
 * - 2160p -> 2.0x
 *
 * 使用 Chromium 的 CSS zoom 缩放整个布局，鼠标注入仍然按原生浏览器坐标工作。
 */

const BASE_HEIGHT = 1080
const MIN_SCALE = 0.75
const MAX_SCALE = 2.5

function clampScale(height: number): number {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, height / BASE_HEIGHT))
}

function applyScale(height: number): void {
  if (!Number.isFinite(height) || height <= 0) return
  const scale = clampScale(height)
  document.documentElement.style.setProperty('zoom', String(scale))
  document.documentElement.style.setProperty('--ui-scale', String(scale))
  document.documentElement.dataset.uiScale = scale.toFixed(3)
}

export function installUiScale(): void {
  if (window.rst) {
    window.rst.setViewportSize = (width: number, height: number) => {
      if (width > 0 && height > 0) applyScale(height)
    }
  }

  // 浏览器开发模式 / Lua 尚未同步前，用当前视口兜底
  applyScale(window.innerHeight || BASE_HEIGHT)
}
