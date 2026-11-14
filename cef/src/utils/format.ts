export function formatTime(seconds: number): string {
  const total = Math.max(0, Math.floor(Number(seconds) || 0))
  const mm = String(Math.floor(total / 60)).padStart(2, '0')
  const ss = String(total % 60).padStart(2, '0')
  return `${mm}:${ss}`
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
