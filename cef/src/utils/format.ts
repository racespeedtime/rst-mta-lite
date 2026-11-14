export function formatTime(seconds: number): string {
  const total = Math.max(0, Math.floor(Number(seconds) || 0))
  const mm = String(Math.floor(total / 60)).padStart(2, '0')
  const ss = String(total % 60).padStart(2, '0')
  return `${mm}:${ss}`
}

export function formatSeconds(seconds: number): string {
  return `${(Math.max(0, Number(seconds) || 0)).toFixed(1)}s`
}

export function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, Number(value) || 0))
}
