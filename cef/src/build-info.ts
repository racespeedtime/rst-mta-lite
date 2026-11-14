export interface BuildInfo {
  /** 本地构建日期 YYYY.MM.DD */
  date: string
  /** ISO 构建时间，用于 tooltip */
  time: string
  /** git 短提交号，非 git 环境为 dev */
  hash: string
}

export const buildInfo: BuildInfo = {
  date: __RST_BUILD_DATE__,
  time: __RST_BUILD_TIME__,
  hash: __RST_BUILD_HASH__,
}
