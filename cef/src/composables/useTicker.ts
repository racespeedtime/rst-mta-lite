import { onMounted, onUnmounted, ref } from 'vue'

const TICK_MS = 40
const now = ref(performance.now())

let users = 0
let timer = 0

function start(): void {
  users += 1
  if (timer) return
  now.value = performance.now()
  timer = window.setInterval(() => {
    now.value = performance.now()
  }, TICK_MS)
}

function stop(): void {
  users = Math.max(0, users - 1)
  if (users > 0 || !timer) return
  window.clearInterval(timer)
  timer = 0
}

/** 全局共享高频时钟，供各计时组件在两次服务端 state 之间插值。 */
export function useTicker(): typeof now {
  onMounted(start)
  onUnmounted(stop)
  return now
}
