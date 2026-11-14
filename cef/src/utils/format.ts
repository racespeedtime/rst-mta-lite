export function formatTime(seconds: number): string {
  const total = Math.max(0, Math.floor(Number(seconds) || 0))
  const mm = String(Math.floor(total / 60)).padStart(2, '0')
  const ss = String(total % 60).padStart(2, '0')
  return `${mm}:${ss}`
}

/** 毫秒 -> mm:ss.mmm（超过 1 小时显示 h:mm:ss.mmm）。 */
export function formatMs(milliseconds: number): string {
  const total = Math.max(0, Math.floor(Number(milliseconds) || 0))
  const hours = Math.floor(total / 3_600_000)
  const minutes = Math.floor(total / 60_000) % 60
  const seconds = Math.floor(total / 1000) % 60
  const millis = total % 1000

  const mm = String(minutes).padStart(2, '0')
  const ss = String(seconds).padStart(2, '0')
  const mmm = String(millis).padStart(3, '0')

  if (hours > 0) {
    return `${hours}:${mm}:${ss}.${mmm}`
  }
  return `${mm}:${ss}.${mmm}`
}

export function formatSeconds(seconds: number): string {
  return `${(Math.max(0, Number(seconds) || 0)).toFixed(1)}s`
}

export function formatClock(timestamp?: number): string {
  const date = timestamp ? new Date(timestamp * 1000) : new Date()
  const hours = String(date.getHours()).padStart(2, '0')
  const minutes = String(date.getMinutes()).padStart(2, '0')
  return `${hours}:${minutes}`
}

export function formatBytes(value?: number): string {
  const bytes = Math.max(0, Number(value) || 0)
  if (bytes <= 0) return '未知'
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}
