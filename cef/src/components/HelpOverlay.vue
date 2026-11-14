<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'

import IconCar from '~icons/lucide/car'
import IconCircleQuestionMark from '~icons/lucide/circle-question-mark'
import IconEye from '~icons/lucide/eye'
import IconInfo from '~icons/lucide/info'
import IconKeyboard from '~icons/lucide/keyboard'
import IconX from '~icons/lucide/x'
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'

function close(): void {
  emitAction('help:close')
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape' || event.key === 'F1') {
    event.preventDefault()
    close()
  }
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <div class="help">
    <section class="help__panel">
      <header class="help__head">
        <div class="help__title-row">
          <span class="help__emblem"><IconCircleQuestionMark class="icon" /></span>
          <div>
            <p class="help__eyebrow">RST MTA LITE</p>
            <h1 class="help__title">操作帮助</h1>
          </div>
        </div>
        <button type="button" class="help__close" aria-label="关闭帮助" @click="close">
          <IconX class="icon" />
        </button>
      </header>

      <div class="help__grid">
        <section class="help__section">
          <h2 class="help__section-title">
            <IconKeyboard class="icon icon--sm" />
            基础操作
          </h2>
          <ul class="help__list">
            <li>
              <span class="help__keys"><kbd>F1</kbd></span>
              <span>打开 / 关闭帮助</span>
            </li>
            <li>
              <span class="help__keys"><kbd>F2</kbd></span>
              <span>菜单：换图投票 / 离开舞台</span>
            </li>
            <li>
              <span class="help__keys"><kbd>T</kbd></span>
              <span>打开聊天输入</span>
            </li>
            <li>
              <span class="help__keys"><kbd>Enter</kbd><kbd>Esc</kbd></span>
              <span>发送 / 取消聊天</span>
            </li>
            <li>
              <span class="help__keys"><kbd>Y</kbd></span>
              <span>长按回放最近 8 秒</span>
            </li>
            <li>
              <span class="help__keys"><kbd>GO</kbd></span>
              <span>出生后 3-2-1-GO 倒计时结束才能移动</span>
            </li>
          </ul>
        </section>

        <section class="help__section">
          <h2 class="help__section-title">
            <IconEye class="icon icon--sm" />
            观战
          </h2>
          <ul class="help__list">
            <li>
              <span class="help__keys"><kbd>左键</kbd></span>
              <span>切换到下一位玩家</span>
            </li>
            <li>
              <span class="help__keys"><kbd>右键</kbd></span>
              <span>切换到上一位玩家</span>
            </li>
          </ul>
          <p class="help__note">进入已有玩家的舞台会先观战，下一回合自动加入比赛。</p>
        </section>

        <section class="help__section">
          <h2 class="help__section-title">
            <IconCar class="icon icon--sm" />
            载具
          </h2>
          <ul class="help__list">
            <li>
              <span class="help__keys"><kbd>F</kbd></span>
              <span>上车 / 下车</span>
            </li>
            <li>
              <span class="help__keys"><kbd>Ctrl</kbd></span>
              <span>使用氮气</span>
            </li>
            <li>
              <span class="help__keys"><kbd>/car</kbd></span>
              <span>生成带氮气的测试车</span>
            </li>
          </ul>
        </section>

        <section class="help__section">
          <h2 class="help__section-title">
            <IconInfo class="icon icon--sm" />
            小提示
          </h2>
          <ul class="help__list">
            <li>
              <span class="help__keys"><kbd>F2</kbd></span>
              <span>提前发起换图投票</span>
            </li>
            <li>
              <span class="help__keys"><kbd>计时</kbd></span>
              <span>顶部「本图」是你在当前地图的个人时长</span>
            </li>
          </ul>
        </section>
      </div>

      <footer class="help__foot">
        <span>Esc 关闭帮助</span>
        <span class="help__version">{{ ui.serverName }}</span>
      </footer>
    </section>
  </div>
</template>

<style scoped>
.help {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(circle at 50% 25%, rgba(20, 40, 70, 0.45), rgba(3, 6, 11, 0.78));
  animation: help-fade 0.16s ease-out;
}

.help__panel {
  width: min(720px, calc(100vw - 96px));
  max-height: 84vh;
  overflow-y: auto;
  padding: 24px 26px 18px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.95), rgba(7, 11, 19, 0.96));
  box-shadow: var(--rst-shadow);
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.help__panel::-webkit-scrollbar {
  width: 4px;
}

.help__panel::-webkit-scrollbar-thumb {
  border-radius: 2px;
  background: rgba(140, 180, 255, 0.22);
}

.help__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.help__title-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.help__emblem {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 12px;
  border: 1px solid rgba(88, 200, 255, 0.24);
  background: rgba(88, 200, 255, 0.1);
  color: var(--rst-accent);
}

.help__eyebrow {
  margin: 0 0 2px;
  font-size: 9px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.help__title {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
}

.help__close {
  display: grid;
  place-items: center;
  width: 32px;
  height: 32px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  color: var(--rst-muted);
  transition: color 0.15s ease, background 0.15s ease;
}

.help__close:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.06);
}

.help__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

.help__section {
  padding: 14px 16px;
  border: 1px solid rgba(255, 255, 255, 0.04);
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.03);
}

.help__section-title {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0 0 10px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.08em;
  color: var(--rst-accent);
}

.help__list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.help__list li {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 11px;
  color: var(--rst-muted);
  line-height: 1.45;
}

.help__keys {
  display: inline-flex;
  flex: 0 0 auto;
  gap: 4px;
}

kbd {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 22px;
  height: 20px;
  padding: 0 6px;
  border: 1px solid rgba(140, 180, 255, 0.22);
  border-bottom-color: rgba(140, 180, 255, 0.34);
  border-radius: 5px;
  background: rgba(255, 255, 255, 0.05);
  color: var(--rst-text);
  font-family: inherit;
  font-size: 10px;
  line-height: 1;
  white-space: nowrap;
}

.help__note {
  margin: 10px 0 0;
  font-size: 10px;
  line-height: 1.5;
  color: rgba(147, 164, 189, 0.8);
}

.help__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding-top: 4px;
  border-top: 1px solid var(--rst-border);
  font-size: 10px;
  color: var(--rst-muted);
}

.help__version {
  opacity: 0.7;
}

@keyframes help-fade {
  from {
    opacity: 0;
    transform: translateY(5px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (max-width: 760px) {
  .help__grid {
    grid-template-columns: 1fr;
  }
}
</style>
