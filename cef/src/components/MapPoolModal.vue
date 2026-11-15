<script setup lang="ts">
import { onMounted, ref } from 'vue'

import IconChevronLeft from '~icons/lucide/chevron-left'
import IconChevronRight from '~icons/lucide/chevron-right'
import IconMap from '~icons/lucide/map'
import IconSearch from '~icons/lucide/search'
import IconX from '~icons/lucide/x'
import { emitAction } from '@/mta/bridge'
import type { MapPoolPage } from '@/mta/protocol'
import { ui } from '@/stores/ui'

const search = ref('')
const PAGE_SIZE = 30

function request(page: number): void {
  const requestId = ui.mapPoolRequestId + 1
  ui.mapPoolRequestId = requestId
  ui.mapPoolLoading = true
  emitAction('maps:page', {
    page,
    pageSize: PAGE_SIZE,
    search: search.value.trim(),
    requestId,
  })
}

function submitSearch(): void {
  request(1)
}

function go(page: number): void {
  if (!ui.mapPool) return
  request(Math.max(1, Math.min(ui.mapPool.pages, page)))
}

function close(): void {
  ui.mapPoolOpen = false
}

function formatPages(pool: MapPoolPage | null): string {
  if (!pool) return ''
  return `第 ${pool.page} / ${pool.pages} 页 · 共 ${pool.total} 张`
}

onMounted(() => request(1))
</script>

<template>
  <div class="map-pool">
    <section class="map-pool__panel">
      <header class="map-pool__head">
        <div class="map-pool__title">
          <IconMap class="icon" />
          <div>
            <span>地图池</span>
            <small>{{ formatPages(ui.mapPool) }}</small>
          </div>
        </div>
        <button type="button" class="map-pool__close" aria-label="关闭" @click="close">
          <IconX class="icon" />
        </button>
      </header>

      <form class="map-pool__search" @submit.prevent="submitSearch">
        <IconSearch class="icon icon--sm" />
        <input
          v-model="search"
          maxlength="80"
          autocomplete="off"
          placeholder="搜索地图名 / 作者 / resource…"
        />
        <button type="submit">搜索</button>
      </form>

      <div class="map-pool__list">
        <p v-if="ui.mapPoolLoading" class="map-pool__empty">加载中…</p>
        <p v-else-if="!ui.mapPool?.items.length" class="map-pool__empty">没有匹配的地图</p>

        <div
          v-for="map in ui.mapPool?.items || []"
          :key="map.id"
          class="map-pool__row"
        >
          <span class="map-pool__index">{{ map.dimension }}</span>
          <span class="map-pool__main">
            <strong>{{ map.name }}</strong>
            <small>
              {{ map.author }} · {{ map.id }}
              <template v-if="map.downloads"> · {{ map.downloads }} 下载</template>
            </small>
          </span>
          <span v-if="map.popularity" class="map-pool__heat">{{ map.popularity }} 热度</span>
        </div>
      </div>

      <footer class="map-pool__foot">
        <button type="button" :disabled="!ui.mapPool || ui.mapPool.page <= 1" @click="go((ui.mapPool?.page || 1) - 1)">
          <IconChevronLeft class="icon icon--sm" />
          上一页
        </button>
        <span>{{ formatPages(ui.mapPool) }}</span>
        <button
          type="button"
          :disabled="!ui.mapPool || ui.mapPool.page >= ui.mapPool.pages"
          @click="go((ui.mapPool?.page || 1) + 1)"
        >
          下一页
          <IconChevronRight class="icon icon--sm" />
        </button>
      </footer>
    </section>
  </div>
</template>

<style scoped>
.map-pool {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 26px;
  background: rgba(2, 6, 12, 0.62);
  backdrop-filter: blur(10px);
  pointer-events: auto;
  z-index: 40;
}

.map-pool__panel {
  display: flex;
  flex-direction: column;
  width: min(760px, calc(100vw - 52px));
  max-height: min(82vh, 760px);
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: var(--rst-panel);
  box-shadow: var(--rst-shadow);
  overflow: hidden;
}

.map-pool__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 16px 18px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.map-pool__title {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--rst-text);
}

.map-pool__title > .icon {
  color: var(--rst-accent);
}

.map-pool__title span {
  display: block;
  font-size: 16px;
  font-weight: 700;
}

.map-pool__title small {
  display: block;
  margin-top: 2px;
  color: var(--rst-muted);
  font-size: 10px;
}

.map-pool__close {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 8px;
  color: var(--rst-muted);
}

.map-pool__close:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.08);
}

.map-pool__search {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 12px 18px;
  padding: 8px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  background: rgba(0, 0, 0, 0.18);
  color: var(--rst-muted);
}

.map-pool__search input {
  flex: 1;
  min-width: 0;
  border: 0;
  outline: none;
  background: transparent;
  color: var(--rst-text);
  font: inherit;
  font-size: 12px;
}

.map-pool__search button {
  padding: 4px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 6px;
  color: var(--rst-muted);
  font-size: 10px;
}

.map-pool__search button:hover {
  color: var(--rst-text);
  border-color: var(--rst-accent);
}

.map-pool__list {
  flex: 1;
  min-height: 180px;
  overflow-y: auto;
  padding: 0 18px;
}

.map-pool__row {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  padding: 10px 4px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.045);
  text-align: left;
}

.map-pool__row:hover {
  background: rgba(var(--rst-accent-rgb), 0.05);
}

.map-pool__index {
  display: grid;
  place-items: center;
  width: 30px;
  height: 24px;
  border-radius: 6px;
  background: rgba(var(--rst-accent-rgb), 0.1);
  color: var(--rst-accent);
  font-size: 10px;
  font-variant-numeric: tabular-nums;
}

.map-pool__main {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.map-pool__main strong {
  overflow: hidden;
  color: var(--rst-text);
  font-size: 12px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.map-pool__main small {
  overflow: hidden;
  color: var(--rst-muted);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.map-pool__heat {
  margin-left: auto;
  flex: 0 0 auto;
  color: var(--rst-accent);
  font-size: 9px;
  font-variant-numeric: tabular-nums;
  opacity: 0.8;
}

.map-pool__empty {
  padding: 32px 0;
  color: var(--rst-muted);
  font-size: 12px;
  text-align: center;
}

.map-pool__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 18px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  color: var(--rst-muted);
  font-size: 10px;
}

.map-pool__foot button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 6px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 7px;
  color: var(--rst-muted);
  font-size: 10px;
}

.map-pool__foot button:hover:not(:disabled) {
  color: var(--rst-text);
  border-color: var(--rst-accent);
}

.map-pool__foot button:disabled {
  opacity: 0.4;
}
</style>
