<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'

import HudBar from '@/components/HudBar.vue'
import { emitToLua, onBridge } from '@/mta/bridge'
import { session } from '@/stores/session'

const router = useRouter()
const offHandlers: Array<() => void> = []

onMounted(() => {
  offHandlers.push(
    onBridge('bootstrap', (payload) => {
      session.playerName = payload.playerName || 'player'
      session.serverName = payload.serverName || 'rst-mta-lite'
      session.online = Number(payload.online) || 0
      session.revision = payload.revision || 'dev'
    }),
    onBridge('stats', (payload) => {
      session.health = Math.round(Number(payload.health) || 0)
      session.armor = Math.round(Number(payload.armor) || 0)
    }),
    onBridge('menu', (payload) => {
      const target = payload?.open ? '/menu' : '/'
      if (router.currentRoute.value.path !== target) {
        void router.push(target)
      }
    }),
  )

  // 监听器全部就绪后再通知 Lua，避免 bootstrap 丢失
  emitToLua('ready')
})

onUnmounted(() => {
  for (const off of offHandlers) off()
})
</script>

<template>
  <div class="app-root">
    <HudBar />
    <RouterView />
  </div>
</template>
