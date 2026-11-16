<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'

import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'

const now = ref(Date.now())
let interval: number | undefined
let lastLabel = ''

const duration = computed(() => Math.max(1, ui.countdown.duration))
const elapsed = computed(() => Math.max(0, (now.value - ui.countdown.startedAt) / 1000))
const remaining = computed(() => Math.max(0, duration.value - elapsed.value))
const go = computed(() => remaining.value <= 0.001)
const label = computed(() => (go.value ? 'GO' : String(Math.ceil(remaining.value))))
const progress = computed(() => Math.min(1, elapsed.value / duration.value))
const ringDash = computed(() => `${Math.max(0.001, (1 - progress.value) * 100)} 100`)

function tick(): void {
  now.value = Date.now()
  if ((now.value - ui.countdown.startedAt) / 1000 >= duration.value + 1.0) {
    ui.countdown.active = false
  }
}

watch(
  label,
  (value) => {
    if (!value || value === lastLabel) return
    lastLabel = value
    emitAction('sound', { name: value === 'GO' ? 'go' : 'countdown' })
  },
  { immediate: true },
)

watch(
  () => ui.countdown.startedAt,
  () => {
    lastLabel = ''
    now.value = Date.now()
  },
)

onMounted(() => {
  now.value = Date.now()
  interval = window.setInterval(tick, 50)
})

onUnmounted(() => {
  window.clearInterval(interval)
})
</script>

<template>
  <div class="countdown" :class="{ 'countdown--go': go }" aria-hidden="true">
    <div class="countdown__ring-wrap">
      <svg class="countdown__ring" viewBox="0 0 200 200">
        <defs>
          <linearGradient id="countdownRingGradient" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="var(--rst-accent)" />
            <stop offset="68%" stop-color="#8b7cff" />
            <stop offset="100%" stop-color="#ffd479" />
          </linearGradient>
        </defs>
        <circle
          class="countdown__ring-track"
          cx="100"
          cy="100"
          r="88"
          pathLength="100"
        />
        <circle
          class="countdown__ring-progress"
          cx="100"
          cy="100"
          r="88"
          pathLength="100"
          :stroke-dasharray="ringDash"
        />
      </svg>

      <div class="countdown__content">
        <p class="countdown__eyebrow">准备出发</p>
        <div class="countdown__number-wrap">
          <span :key="label" class="countdown__number" :class="{ 'countdown__number--go': go }">
            {{ label }}
          </span>
        </div>
        <p class="countdown__hint">{{ go ? '开始移动' : '倒计时结束后可以移动' }}</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
.countdown {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  pointer-events: none;
}

/* 外围柔光：纯渐变，不用 filter: blur，避免每帧软合成 */
.countdown::before {
  content: '';
  position: absolute;
  width: 560px;
  height: 560px;
  border-radius: 50%;
  background: radial-gradient(
    circle,
    rgba(3, 8, 14, 0.6) 0%,
    rgba(3, 8, 14, 0.34) 42%,
    rgba(3, 8, 14, 0.12) 62%,
    transparent 76%
  );
}

.countdown__ring-wrap {
  position: relative;
  width: 232px;
  height: 232px;
  display: grid;
  place-items: center;
}

/* 数字背后的半透明底盘：在明亮场景里也保证可读，不再是全透明 */
.countdown__ring-wrap::before {
  content: '';
  position: absolute;
  inset: 6px;
  border-radius: 50%;
  background: radial-gradient(
    circle at 50% 40%,
    rgba(10, 21, 36, 0.86) 0%,
    rgba(6, 13, 24, 0.74) 58%,
    rgba(4, 9, 17, 0.55) 100%
  );
  border: 1px solid rgba(140, 180, 255, 0.14);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 18px 48px rgba(0, 0, 0, 0.38);
}

.countdown__ring {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  transform: rotate(-90deg);
  overflow: visible;
}

.countdown__ring-track,
.countdown__ring-progress {
  fill: none;
  stroke-width: 4;
}

.countdown__ring-track {
  stroke: rgba(140, 180, 255, 0.12);
}

.countdown__ring-progress {
  stroke: url(#countdownRingGradient);
  stroke-linecap: round;
  filter: drop-shadow(0 0 8px rgba(var(--rst-accent-rgb), 0.45));
}

.countdown--go .countdown__ring-progress {
  stroke: var(--rst-gold);
  filter: drop-shadow(0 0 12px rgba(255, 212, 121, 0.6));
}

.countdown__content {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
}

.countdown__eyebrow {
  margin: 0;
  font-size: 10px;
  letter-spacing: 0.24em;
  color: var(--rst-muted);
}

.countdown__number-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 88px;
}

.countdown__number {
  display: block;
  font-size: 78px;
  font-weight: 600;
  line-height: 1;
  letter-spacing: 0.01em;
  font-variant-numeric: tabular-nums;
  background: linear-gradient(180deg, #f3fbff 0%, var(--rst-accent) 68%, #8b7cff 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  filter: drop-shadow(0 0 22px rgba(var(--rst-accent-rgb), 0.3));
  animation: count-pop 0.26s cubic-bezier(0.2, 0.8, 0.2, 1);
}

.countdown__number--go {
  font-size: 62px;
  letter-spacing: 0.06em;
  background: linear-gradient(180deg, #fff7df 0%, #ffd479 62%, #ff9f43 100%);
  -webkit-background-clip: text;
  background-clip: text;
  filter: drop-shadow(0 0 26px rgba(255, 212, 121, 0.45));
}

.countdown__hint {
  margin: 0;
  font-size: 10px;
  letter-spacing: 0.1em;
  color: var(--rst-muted);
}

.countdown--go .countdown__hint {
  color: var(--rst-gold);
}

@keyframes count-pop {
  from {
    opacity: 0;
    transform: scale(1.38);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
</style>
