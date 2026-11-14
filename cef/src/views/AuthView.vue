<script setup lang="ts">
import { ref } from 'vue'

import IconGhost from '~icons/lucide/ghost'
import IconLock from '~icons/lucide/lock'
import IconLogIn from '~icons/lucide/log-in'
import IconServer from '~icons/lucide/server'
import IconSwords from '~icons/lucide/swords'
import IconUser from '~icons/lucide/user'
import IconUserPlus from '~icons/lucide/user-plus'
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'

type AuthMode = 'login' | 'register'

const mode = ref<AuthMode>('login')
const password = ref('')
const confirmPassword = ref('')

function switchMode(next: AuthMode): void {
  if (ui.busy) return
  mode.value = next
  ui.authError = ''
}

function submit(): void {
  if (ui.busy) return
  if (!password.value) {
    ui.authError = '请输入密码'
    return
  }
  if (mode.value === 'register' && password.value !== confirmPassword.value) {
    ui.authError = '两次密码不一致'
    return
  }

  ui.authError = ''
  ui.busy = true
  emitAction(mode.value === 'login' ? 'auth:login' : 'auth:register', {
    password: password.value,
    confirmPassword: confirmPassword.value,
  })
}

function playAsGuest(): void {
  if (ui.busy) return
  ui.authError = ''
  ui.busy = true
  emitAction('auth:guest')
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Enter') submit()
}
</script>

<template>
  <div class="auth">
    <div class="auth__grid" />
    <div class="auth__glow auth__glow--a" />
    <div class="auth__glow auth__glow--b" />

    <section class="auth__card">
      <header class="auth__head">
        <span class="auth__emblem"><IconSwords class="icon icon--lg" /></span>
        <div>
          <p class="auth__eyebrow">RST MTA LITE</p>
          <h1 class="auth__title">进入服务器</h1>
        </div>
      </header>

      <p class="auth__server">
        <IconServer class="icon icon--sm" />
        <span>{{ ui.serverName }}</span>
      </p>

      <div class="auth__identity">
        <span class="auth__avatar"><IconUser class="icon" /></span>
        <div class="auth__identity-main">
          <span class="auth__identity-label">玩家昵称</span>
          <strong class="auth__identity-name">{{ ui.playerName }}</strong>
        </div>
        <small class="auth__identity-hint">账号名使用当前游戏昵称</small>
      </div>

      <div class="auth__tabs">
        <button
          type="button"
          :class="{ 'is-active': mode === 'login' }"
          :disabled="ui.busy"
          @click="switchMode('login')"
        >
          登录
        </button>
        <button
          type="button"
          :class="{ 'is-active': mode === 'register' }"
          :disabled="ui.busy"
          @click="switchMode('register')"
        >
          注册
        </button>
      </div>

      <label class="auth__label" for="rst-password">{{ mode === 'login' ? '密码' : '设置密码' }}</label>
      <div class="auth__field">
        <IconLock class="icon auth__field-icon" />
        <input
          id="rst-password"
          v-model="password"
          class="auth__input"
          type="password"
          maxlength="128"
          :placeholder="mode === 'login' ? '输入登录密码' : '设置注册密码（至少 8 位）'"
          autocomplete="off"
          autofocus
          @keydown="onKeydown"
        />
      </div>

      <template v-if="mode === 'register'">
        <label class="auth__label" for="rst-confirm-password">确认密码</label>
        <div class="auth__field">
          <IconLock class="icon auth__field-icon" />
          <input
            id="rst-confirm-password"
            v-model="confirmPassword"
            class="auth__input"
            type="password"
            maxlength="128"
            placeholder="再输入一次密码"
            autocomplete="off"
            @keydown="onKeydown"
          />
        </div>
      </template>

      <p v-if="ui.authError" class="auth__error">{{ ui.authError }}</p>

      <button type="button" class="btn btn--primary auth__submit" :disabled="ui.busy" @click="submit">
        <IconLogIn v-if="mode === 'login'" class="icon" />
        <IconUserPlus v-else class="icon" />
        <span>{{ mode === 'login' ? '登录' : '注册并进入' }}</span>
      </button>

      <div class="auth__divider"><span>或</span></div>

      <button type="button" class="auth__guest" :disabled="ui.busy" @click="playAsGuest">
        <IconGhost class="icon" />
        <span>Play as Guest · 游客进入</span>
      </button>

      <p class="auth__foot">
        {{ mode === 'login' ? '登录后进入舞台选择。' : '两次密码一致后创建账号并自动登录。' }}
      </p>
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
  overflow: hidden;
  background:
    radial-gradient(circle at 50% 12%, rgba(44, 110, 180, 0.22), transparent 55%),
    linear-gradient(180deg, #050a12 0%, #04070c 100%);
}

.auth__grid {
  position: absolute;
  inset: -15%;
  background-image:
    linear-gradient(rgba(120, 170, 255, 0.055) 1px, transparent 1px),
    linear-gradient(90deg, rgba(120, 170, 255, 0.055) 1px, transparent 1px);
  background-size: 46px 46px;
  mask-image: radial-gradient(circle at 50% 45%, #000 0%, transparent 72%);
  -webkit-mask-image: radial-gradient(circle at 50% 45%, #000 0%, transparent 72%);
  pointer-events: none;
}

.auth__glow {
  position: absolute;
  width: 460px;
  height: 460px;
  border-radius: 50%;
  filter: blur(20px);
  pointer-events: none;
}

.auth__glow--a {
  top: -160px;
  left: 8%;
  background: radial-gradient(circle, rgba(76, 194, 255, 0.16), transparent 65%);
}

.auth__glow--b {
  right: 6%;
  bottom: -200px;
  background: radial-gradient(circle, rgba(139, 124, 255, 0.14), transparent 65%);
}

.auth__card {
  position: relative;
  width: min(430px, calc(100vw - 80px));
  padding: 30px 30px 24px;
  border: 1px solid var(--rst-border);
  border-radius: 20px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.94), rgba(7, 11, 19, 0.96));
  box-shadow: var(--rst-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.04);
  display: flex;
  flex-direction: column;
  gap: 14px;
  animation: auth-in 0.35s cubic-bezier(0.2, 0.8, 0.2, 1);
}

.auth__head {
  display: flex;
  align-items: center;
  gap: 14px;
}

.auth__emblem {
  display: grid;
  place-items: center;
  width: 46px;
  height: 46px;
  border-radius: 14px;
  background: linear-gradient(150deg, rgba(88, 200, 255, 0.5), rgba(139, 124, 255, 0.3));
  border: 1px solid rgba(140, 200, 255, 0.35);
  color: #eaf6ff;
  box-shadow: 0 10px 26px rgba(76, 194, 255, 0.2);
}

.auth__eyebrow {
  margin: 0 0 3px;
  font-size: 10px;
  letter-spacing: 0.22em;
  color: var(--rst-muted);
}

.auth__title {
  margin: 0;
  font-size: 24px;
  font-weight: 600;
  letter-spacing: 0.01em;
}

.auth__server {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  margin: 0;
  padding: 7px 11px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.03);
  font-size: 11px;
  color: var(--rst-muted);
}

.auth__identity {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 4px 10px;
  padding: 12px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.035);
}

.auth__avatar {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border-radius: 10px;
  background: rgba(88, 200, 255, 0.12);
  border: 1px solid rgba(88, 200, 255, 0.22);
  color: var(--rst-accent);
  grid-row: span 2;
}

.auth__identity-main {
  display: flex;
  align-items: baseline;
  gap: 8px;
}

.auth__identity-label {
  font-size: 10px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}

.auth__identity-name {
  font-size: 15px;
}

.auth__identity-hint {
  grid-column: 2;
  font-size: 10px;
  color: var(--rst-muted);
}

.auth__label {
  margin-top: 2px;
  font-size: 11px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}

.auth__field {
  position: relative;
  display: flex;
  align-items: center;
}

.auth__field-icon {
  position: absolute;
  left: 13px;
  color: var(--rst-muted);
  pointer-events: none;
}

.auth__input {
  width: 100%;
  padding: 12px 13px 12px 38px;
  border: 1px solid var(--rst-border);
  border-radius: 11px;
  background: rgba(4, 8, 14, 0.72);
  color: var(--rst-text);
  font: inherit;
  font-size: 14px;
  outline: none;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.auth__input:focus {
  border-color: rgba(88, 200, 255, 0.55);
  box-shadow: 0 0 0 3px rgba(88, 200, 255, 0.12);
}

.auth__input::placeholder {
  color: rgba(147, 164, 189, 0.7);
}

.auth__error {
  margin: 0;
  padding: 8px 11px;
  border: 1px solid rgba(255, 92, 92, 0.24);
  border-radius: 9px;
  background: rgba(255, 92, 92, 0.1);
  color: #ff9b9b;
  font-size: 12px;
}

.auth__tabs {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px;
  padding: 4px;
  border: 1px solid var(--rst-border);
  border-radius: 10px;
  background: rgba(0, 0, 0, 0.18);
}

.auth__tabs button {
  padding: 8px 10px;
  border-radius: 7px;
  color: var(--rst-muted);
  font-size: 12px;
  transition: color 0.15s ease, background 0.15s ease;
}

.auth__tabs button:hover:not(:disabled) {
  color: var(--rst-text);
}

.auth__tabs button.is-active {
  color: var(--rst-text);
  background: rgba(88, 200, 255, 0.13);
}

.auth__submit {
  width: 100%;
  margin-top: 2px;
}

.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 11px 14px;
  border: 1px solid var(--rst-border);
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.045);
  font-size: 14px;
  transition: background 0.15s ease, border-color 0.15s ease, transform 0.15s ease;
}

.btn:hover:not(:disabled) {
  transform: translateY(-1px);
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(88, 200, 255, 0.4);
}

.btn:disabled {
  opacity: 0.5;
}

.btn--primary {
  border-color: rgba(88, 200, 255, 0.45);
  background: linear-gradient(180deg, rgba(88, 200, 255, 0.3), rgba(88, 200, 255, 0.14));
}

.auth__divider {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--rst-muted);
  font-size: 10px;
}

.auth__divider::before,
.auth__divider::after {
  content: '';
  height: 1px;
  flex: 1;
  background: var(--rst-border);
}

.auth__guest {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 11px 12px;
  border: 1px dashed var(--rst-border);
  border-radius: 11px;
  color: var(--rst-muted);
  font-size: 12px;
  transition: color 0.15s ease, border-color 0.15s ease, background 0.15s ease;
}

.auth__guest:hover:not(:disabled) {
  color: var(--rst-text);
  border-color: rgba(88, 200, 255, 0.4);
  background: rgba(88, 200, 255, 0.06);
}

.auth__guest:disabled {
  opacity: 0.5;
}

.auth__foot {
  margin: 2px 0 0;
  text-align: center;
  font-size: 10px;
  color: var(--rst-muted);
}

@keyframes auth-in {
  from {
    opacity: 0;
    transform: translateY(12px) scale(0.99);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}
</style>
