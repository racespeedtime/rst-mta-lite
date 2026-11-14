<script setup lang="ts">
import { ref } from 'vue'

import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'

const password = ref('')

function submit(action: 'auth:login' | 'auth:register'): void {
  if (ui.busy) return

  if (!password.value) {
    ui.authError = '请输入密码'
    return
  }

  ui.authError = ''
  ui.busy = true
  emitAction(action, { password: password.value })
}

function playAsGuest(): void {
  if (ui.busy) return
  ui.authError = ''
  ui.busy = true
  emitAction('auth:guest')
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Enter') submit('auth:login')
}
</script>

<template>
  <div class="auth">
    <div class="auth__glow" />
    <section class="auth__card">
      <p class="auth__eyebrow">RST MTA LITE</p>
      <h1 class="auth__title">进入服务器</h1>
      <p class="auth__subtitle">{{ ui.serverName }}</p>

      <div class="auth__identity">
        <span class="auth__identity-label">玩家昵称</span>
        <strong class="auth__identity-name">{{ ui.playerName }}</strong>
        <small>账号名使用当前游戏昵称</small>
      </div>

      <label class="auth__label" for="rst-password">密码</label>
      <input
        id="rst-password"
        v-model="password"
        class="auth__input"
        type="password"
        maxlength="128"
        placeholder="输入密码（注册 / 登录共用）"
        autocomplete="off"
        autofocus
        @keydown="onKeydown"
      />

      <p v-if="ui.authError" class="auth__error">{{ ui.authError }}</p>

      <div class="auth__actions">
        <button type="button" class="btn btn--primary" :disabled="ui.busy" @click="submit('auth:login')">
          登录
        </button>
        <button type="button" class="btn" :disabled="ui.busy" @click="submit('auth:register')">
          注册
        </button>
      </div>

      <button type="button" class="auth__guest" :disabled="ui.busy" @click="playAsGuest">
        Play as Guest · 游客进入
      </button>
    </section>
  </div>
</template>

<style scoped>
.auth {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background:
    radial-gradient(circle at 50% 18%, rgba(38, 92, 160, 0.18), transparent 55%),
    rgba(4, 8, 14, 0.55);
}

.auth__glow {
  position: absolute;
  width: 520px;
  height: 520px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(76, 194, 255, 0.14), transparent 65%);
  filter: blur(10px);
  pointer-events: none;
}

.auth__card {
  position: relative;
  width: min(420px, calc(100vw - 80px));
  padding: 30px 30px 26px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: var(--rst-panel);
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.5);
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.auth__eyebrow {
  margin: 0;
  font-size: 10px;
  letter-spacing: 0.22em;
  color: var(--rst-muted);
}

.auth__title {
  margin: 0;
  font-size: 24px;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.auth__subtitle {
  margin: -8px 0 6px;
  font-size: 12px;
  color: var(--rst-muted);
}

.auth__identity {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 6px 10px;
  padding: 10px 12px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.04);
}

.auth__identity-label {
  font-size: 11px;
  color: var(--rst-muted);
}

.auth__identity-name {
  font-size: 15px;
}

.auth__identity small {
  width: 100%;
  font-size: 10px;
  color: var(--rst-muted);
}

.auth__label {
  margin-top: 4px;
  font-size: 11px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}

.auth__input {
  width: 100%;
  padding: 11px 13px;
  border: 1px solid var(--rst-border);
  border-radius: 10px;
  background: rgba(5, 9, 15, 0.7);
  color: var(--rst-text);
  font: inherit;
  font-size: 14px;
  outline: none;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.auth__input:focus {
  border-color: rgba(76, 194, 255, 0.55);
  box-shadow: 0 0 0 3px rgba(76, 194, 255, 0.12);
}

.auth__error {
  margin: 0;
  padding: 8px 10px;
  border-radius: 8px;
  background: rgba(255, 92, 92, 0.12);
  color: #ff9b9b;
  font-size: 12px;
}

.auth__actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: 4px;
}

.auth__guest {
  margin-top: 4px;
  padding: 10px 12px;
  border: 1px dashed var(--rst-border);
  border-radius: 10px;
  color: var(--rst-muted);
  font-size: 12px;
  transition: color 0.15s ease, border-color 0.15s ease;
}

.auth__guest:hover {
  color: var(--rst-text);
  border-color: rgba(76, 194, 255, 0.4);
}

.btn {
  padding: 11px 14px;
  border: 1px solid var(--rst-border);
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.05);
  font-size: 14px;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.btn:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.09);
  border-color: rgba(76, 194, 255, 0.4);
}

.btn:disabled,
.auth__guest:disabled {
  opacity: 0.5;
}

.btn--primary {
  border-color: rgba(76, 194, 255, 0.45);
  background: linear-gradient(180deg, rgba(76, 194, 255, 0.28), rgba(76, 194, 255, 0.14));
}
</style>
