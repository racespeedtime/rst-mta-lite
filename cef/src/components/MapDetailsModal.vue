<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import IconCalendar from '~icons/lucide/calendar'
import IconDownload from '~icons/lucide/download'
import IconExternalLink from '~icons/lucide/external-link'
import IconFileArchive from '~icons/lucide/file-archive'
import IconLink from '~icons/lucide/link'
import IconMapPinned from '~icons/lucide/map-pinned'
import IconSparkles from '~icons/lucide/sparkles'
import IconX from '~icons/lucide/x'
import { ui } from '@/stores/ui'
import { formatBytes } from '@/utils/format'

const copied = ref('')

const details = computed(() => ui.mapDetails)
const coverSrc = computed(() => (details.value?.cover ? `../${details.value.cover}` : ''))
const youtube = computed(() => details.value?.youtube || '')
const sourceUrl = computed(() => details.value?.sourceUrl || '')

function close(): void {
  ui.mapDetailsOpen = false
}

async function copy(value: string, key: string): Promise<void> {
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
  } catch {
    const textarea = document.createElement('textarea')
    textarea.value = value
    textarea.style.position = 'fixed'
    textarea.style.opacity = '0'
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand('copy')
    textarea.remove()
  }
  copied.value = key
  window.setTimeout(() => {
    if (copied.value === key) copied.value = ''
  }, 1600)
}

function formatDate(value?: string | null): string {
  if (!value) return '未知'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  return date.toLocaleDateString('zh-CN')
}

function vehicleNames(models?: number[]): string {
  if (!models || models.length === 0) return '地图默认'
  return models.map((model) => `#${model}`).join(' / ')
}

watch(
  () => ui.mapDetailsOpen,
  (open) => {
    if (!open) copied.value = ''
  },
)
</script>

<template>
  <div v-if="ui.mapDetailsOpen" class="map-detail" @click.self="close">
    <section class="map-detail__panel">
      <header class="map-detail__head">
        <div class="map-detail__title">
          <span class="map-detail__icon"><IconMapPinned class="icon" /></span>
          <div>
            <p class="map-detail__eyebrow">MAP DETAILS</p>
            <h2>{{ details?.name || ui.room?.mapName || '地图详情' }}</h2>
            <p>{{ details?.author || ui.room?.author || '未知作者' }}</p>
          </div>
        </div>
        <button type="button" class="map-detail__close" aria-label="关闭" @click="close">
          <IconX class="icon" />
        </button>
      </header>

      <div v-if="details" class="map-detail__body">
        <div class="map-detail__preview">
          <img v-if="coverSrc" :src="coverSrc" :alt="ui.room?.mapName || '地图封面'" />
          <div v-else class="map-detail__preview-empty">
            <IconSparkles class="icon icon--lg" />
            <span>本地暂无封面</span>
          </div>
        </div>

        <div class="map-detail__info">
          <div class="map-detail__facts">
            <span><IconCalendar class="icon icon--sm" />上传 {{ formatDate(details.uploadedAt) }}</span>
            <span><IconDownload class="icon icon--sm" />{{ details.downloads ?? 0 }} 下载</span>
            <span><IconFileArchive class="icon icon--sm" />{{ formatBytes(details.fileSize) }}</span>
            <span><IconSparkles class="icon icon--sm" />{{ details.difficulty || '未知难度' }}</span>
          </div>

          <p class="map-detail__resource">
            <IconMapPinned class="icon icon--sm" />
            {{ details.resource }}
          </p>

          <div class="map-detail__native">
            <span>出生点 <strong>{{ details.spawns }}</strong></span>
            <span>车辆 <strong>{{ vehicleNames(details.vehicles) }}</strong></span>
            <span>维度 <strong>{{ details.dimension }}</strong></span>
            <span>终点 <strong>{{ details.finish ? 'Hunter / 检查点' : '未配置' }}</strong></span>
          </div>

          <div v-if="details.tags?.length" class="map-detail__tags">
            <span v-for="tag in details.tags" :key="tag">{{ tag }}</span>
          </div>

          <div v-if="youtube" class="map-detail__link">
            <span class="map-detail__link-label"><IconLink class="icon icon--sm" />YouTube</span>
            <code>{{ youtube }}</code>
            <button type="button" @click="copy(youtube, 'youtube')">
              {{ copied === 'youtube' ? '已复制' : '复制链接' }}
            </button>
          </div>

          <div v-if="sourceUrl" class="map-detail__link">
            <span class="map-detail__link-label"><IconExternalLink class="icon icon--sm" />mtavault</span>
            <code>{{ sourceUrl }}</code>
            <button type="button" @click="copy(sourceUrl, 'source')">
              {{ copied === 'source' ? '已复制' : '复制链接' }}
            </button>
          </div>
        </div>
      </div>

      <div v-else class="map-detail__empty">当前地图还没有详情数据。</div>
    </section>
  </div>
</template>

<style scoped>
.map-detail {
  position: absolute;
  inset: 0;
  z-index: 80;
  display: grid;
  place-items: center;
  padding: 40px;
  background: rgba(2, 6, 12, 0.55);
  backdrop-filter: blur(3px);
  pointer-events: auto;
}

.map-detail__panel {
  width: min(860px, 100%);
  max-height: min(760px, 88vh);
  overflow: auto;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(155deg, rgba(17, 29, 45, 0.98), rgba(6, 11, 19, 0.98));
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.5);
}

.map-detail__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  padding: 22px 24px 16px;
  border-bottom: 1px solid var(--rst-border);
}

.map-detail__title {
  display: flex;
  align-items: center;
  gap: 13px;
}

.map-detail__icon {
  display: grid;
  place-items: center;
  width: 42px;
  height: 42px;
  border: 1px solid rgba(88, 200, 255, 0.25);
  border-radius: 12px;
  color: var(--rst-accent);
  background: rgba(88, 200, 255, 0.1);
}

.map-detail__eyebrow {
  margin: 0 0 3px;
  color: var(--rst-muted);
  font-size: 9px;
  letter-spacing: 0.18em;
}

.map-detail__title h2 {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
}

.map-detail__title p:last-child {
  margin: 4px 0 0;
  color: var(--rst-muted);
  font-size: 11px;
}

.map-detail__close {
  display: grid;
  place-items: center;
  width: 32px;
  height: 32px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  color: var(--rst-muted);
  background: rgba(255, 255, 255, 0.03);
}

.map-detail__close:hover {
  color: var(--rst-text);
}

.map-detail__body {
  display: grid;
  grid-template-columns: minmax(240px, 0.9fr) minmax(300px, 1.1fr);
  gap: 22px;
  padding: 20px 24px 24px;
}

.map-detail__preview {
  min-height: 210px;
  border: 1px solid var(--rst-border);
  border-radius: 12px;
  overflow: hidden;
  background: rgba(255, 255, 255, 0.03);
}

.map-detail__preview img {
  width: 100%;
  height: 100%;
  min-height: 210px;
  object-fit: cover;
  display: block;
}

.map-detail__preview-empty {
  height: 100%;
  min-height: 210px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 9px;
  color: var(--rst-muted);
  font-size: 11px;
}

.map-detail__info {
  display: flex;
  flex-direction: column;
  gap: 13px;
  min-width: 0;
}

.map-detail__facts {
  display: flex;
  flex-wrap: wrap;
  gap: 7px 13px;
  color: var(--rst-muted);
  font-size: 10px;
}

.map-detail__facts span,
.map-detail__link-label {
  display: inline-flex;
  align-items: center;
  gap: 5px;
}

.map-detail__resource {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0;
  padding: 7px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 7px;
  color: var(--rst-muted);
  font-size: 10px;
  word-break: break-all;
}

.map-detail__native {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 7px;
  padding: 10px;
  border-radius: 9px;
  background: rgba(255, 255, 255, 0.035);
  font-size: 10px;
  color: var(--rst-muted);
}

.map-detail__native strong {
  color: var(--rst-text);
  font-weight: 500;
}

.map-detail__tags {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
}

.map-detail__tags span {
  padding: 3px 7px;
  border: 1px solid rgba(88, 200, 255, 0.18);
  border-radius: 999px;
  color: var(--rst-muted);
  background: rgba(88, 200, 255, 0.06);
  font-size: 9px;
}

.map-detail__link {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 8px;
  padding: 8px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  min-width: 0;
}

.map-detail__link code {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--rst-muted);
  font-size: 9px;
}

.map-detail__link button {
  padding: 4px 7px;
  border: 1px solid rgba(88, 200, 255, 0.3);
  border-radius: 5px;
  color: var(--rst-accent);
  background: rgba(88, 200, 255, 0.08);
  font-size: 9px;
  white-space: nowrap;
}

.map-detail__empty {
  padding: 36px 24px;
  color: var(--rst-muted);
  font-size: 12px;
  text-align: center;
}

@media (max-width: 760px) {
  .map-detail {
    padding: 18px;
  }

  .map-detail__body {
    grid-template-columns: 1fr;
  }
}
</style>
