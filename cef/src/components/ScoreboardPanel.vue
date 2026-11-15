<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'

import IconUsers from '~icons/lucide/users'
import { onBridge } from '@/mta/bridge'
import { ui } from '@/stores/ui'

const scrollRef = ref<HTMLElement | null>(null)
let offScroll: (() => void) | undefined

const players = computed(() => ui.scoreboard?.players || [])
const count = computed(() => ui.scoreboard?.count ?? players.value.length)

function onScroll(payload: { delta: number }): void {
  if (!scrollRef.value) return
  scrollRef.value.scrollTop += Math.sign(payload.delta) * 48
}

onMounted(() => {
  offScroll = onBridge('scoreboardScroll', onScroll)
})

onUnmounted(() => {
  offScroll?.()
})
</script>

<template>
  <aside class="scoreboard" aria-label="全服玩家列表">
    <header class="scoreboard__head">
      <span class="scoreboard__title">
        <IconUsers class="icon icon--sm" />
        全服玩家
      </span>
      <span class="scoreboard__meta">{{ count }} 人 · 按住 Tab 查看</span>
    </header>

    <div ref="scrollRef" class="scoreboard__scroll">
      <table class="scoreboard__table">
        <colgroup>
          <col class="scoreboard__col-id" />
          <col class="scoreboard__col-name" />
          <col class="scoreboard__col-status" />
          <col class="scoreboard__col-num" />
          <col class="scoreboard__col-num" />
        </colgroup>
        <thead>
          <tr>
            <th class="scoreboard__id">ID</th>
            <th>昵称</th>
            <th>状态</th>
            <th class="scoreboard__num">FPS</th>
            <th class="scoreboard__num">Ping</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="player in players"
            :key="player.id"
            :class="{ 'scoreboard__row--me': player.me }"
          >
            <td class="scoreboard__id">{{ player.id }}</td>
            <td class="scoreboard__name">{{ player.name }}</td>
            <td>
              <span class="scoreboard__status" :class="`scoreboard__status--${player.statusKey}`">
                {{ player.status }}
              </span>
            </td>
            <td class="scoreboard__num">{{ player.fps || '--' }}</td>
            <td class="scoreboard__num">{{ player.ping }} ms</td>
          </tr>
        </tbody>
      </table>

      <p v-if="!players.length" class="scoreboard__empty">正在获取玩家列表…</p>
    </div>
  </aside>
</template>

<style scoped>
.scoreboard {
  position: absolute;
  top: 50%;
  left: 50%;
  width: min(720px, calc(100vw - 64px));
  max-height: min(66vh, 620px);
  transform: translate(-50%, -50%);
  border: 1px solid var(--rst-border);
  border-radius: 12px;
  background: rgba(8, 15, 25, 0.68);
  box-shadow: var(--rst-shadow);
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
  overflow: hidden;
  pointer-events: none;
  z-index: 35;
}

.scoreboard__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.07);
}

.scoreboard__title {
  display: flex;
  align-items: center;
  gap: 7px;
  color: var(--rst-text);
  font-size: 14px;
  font-weight: 700;
}

.scoreboard__title .icon {
  color: var(--rst-accent);
}

.scoreboard__meta {
  color: var(--rst-muted);
  font-size: 9px;
}

.scoreboard__scroll {
  max-height: calc(min(66vh, 620px) - 44px);
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: rgba(88, 200, 255, 0.4) transparent;
}

.scoreboard__scroll::-webkit-scrollbar {
  width: 8px;
}

.scoreboard__scroll::-webkit-scrollbar-thumb {
  border-radius: 8px;
  background: rgba(88, 200, 255, 0.35);
}

.scoreboard__table {
  width: 100%;
  border-collapse: collapse;
  table-layout: fixed;
}

.scoreboard__col-id {
  width: 54px;
}

.scoreboard__col-name {
  width: auto;
}

.scoreboard__col-status {
  width: 112px;
}

.scoreboard__col-num {
  width: 82px;
}

.scoreboard__table th {
  position: sticky;
  top: 0;
  z-index: 1;
  padding: 8px 10px;
  background: rgba(8, 15, 25, 0.78);
  color: var(--rst-muted);
  font-size: 9px;
  font-weight: 500;
  text-align: left;
  letter-spacing: 0.08em;
}

.scoreboard__table td {
  padding: 8px 10px;
  border-top: 1px solid rgba(255, 255, 255, 0.045);
  color: var(--rst-muted);
  font-size: 11px;
}

.scoreboard__table tbody tr:hover {
  background: rgba(88, 200, 255, 0.06);
}

.scoreboard__row--me {
  background: rgba(88, 200, 255, 0.1);
}

.scoreboard__id {
  color: var(--rst-accent);
  font-variant-numeric: tabular-nums;
  text-align: left;
}

.scoreboard__name {
  overflow: hidden;
  color: var(--rst-text);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scoreboard__num {
  text-align: right;
  font-variant-numeric: tabular-nums;
}

.scoreboard__status {
  display: inline-block;
  padding: 2px 6px;
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.06);
  font-size: 9px;
}

.scoreboard__status--alive {
  color: #7ee787;
  background: rgba(126, 231, 135, 0.1);
}

.scoreboard__status--dead,
.scoreboard__status--out {
  color: #ff7b72;
  background: rgba(255, 123, 114, 0.1);
}

.scoreboard__status--spectate {
  color: #79c0ff;
  background: rgba(121, 192, 255, 0.1);
}

.scoreboard__status--ready,
.scoreboard__status--vote {
  color: #e3b341;
  background: rgba(227, 179, 65, 0.1);
}

.scoreboard__status--finished {
  color: #d2a8ff;
  background: rgba(210, 168, 255, 0.1);
}

.scoreboard__empty {
  padding: 30px 0;
  color: var(--rst-muted);
  font-size: 11px;
  text-align: center;
}
</style>
