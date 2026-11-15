export type ThemeMode = 'dark' | 'light' | 'system'
export type ResolvedTheme = 'dark' | 'light'

export interface ThemeSettings {
  mode: ThemeMode
  accent: string
}

const STORAGE_KEY = 'rst.theme'
const DEFAULT_THEME: ThemeSettings = {
  mode: 'dark',
  accent: '#58c8ff',
}

function isThemeMode(value: unknown): value is ThemeMode {
  return value === 'dark' || value === 'light' || value === 'system'
}

export function normalizeAccent(value: unknown): string {
  const accent = typeof value === 'string' ? value.trim() : ''
  return /^#[0-9a-f]{6}$/i.test(accent) ? accent.toLowerCase() : DEFAULT_THEME.accent
}

export function hexToRgbChannels(hex: string): string {
  const value = normalizeAccent(hex).slice(1)
  return `${parseInt(value.slice(0, 2), 16)}, ${parseInt(value.slice(2, 4), 16)}, ${parseInt(value.slice(4, 6), 16)}`
}

export function loadThemeSettings(): ThemeSettings {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY)
    if (!raw) return DEFAULT_THEME
    const parsed = JSON.parse(raw) as Partial<ThemeSettings>
    return {
      mode: isThemeMode(parsed.mode) ? parsed.mode : DEFAULT_THEME.mode,
      accent: normalizeAccent(parsed.accent),
    }
  } catch {
    return DEFAULT_THEME
  }
}

export function saveThemeSettings(settings: ThemeSettings): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings))
  } catch {
    // CEF 某些缓存策略下 localStorage 可能不可写，界面仍会在当前会话生效
  }
}

export function resolveTheme(mode: ThemeMode): ResolvedTheme {
  if (mode === 'system') {
    return window.matchMedia?.('(prefers-color-scheme: light)').matches ? 'light' : 'dark'
  }
  return mode
}

export function applyTheme(settings: ThemeSettings): void {
  const root = document.documentElement
  const resolved = resolveTheme(settings.mode)
  const accent = normalizeAccent(settings.accent)
  root.dataset.theme = resolved
  root.dataset.themeMode = settings.mode
  root.style.setProperty('--rst-accent', accent)
  root.style.setProperty('--rst-accent-rgb', hexToRgbChannels(accent))
}

export function watchSystemTheme(onChange: () => void): () => void {
  const media = window.matchMedia?.('(prefers-color-scheme: light)')
  if (!media) return () => undefined
  media.addEventListener('change', onChange)
  return () => media.removeEventListener('change', onChange)
}
