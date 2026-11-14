/// <reference types="vite/client" />

declare const __RST_BUILD_DATE__: string
declare const __RST_BUILD_TIME__: string
declare const __RST_BUILD_HASH__: string

declare module '*.vue' {
  import type { DefineComponent } from 'vue'

  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>
  export default component
}
