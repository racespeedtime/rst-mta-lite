<script setup lang="ts">
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'

function enter(): void {
  emitAction('stage:join')
}
</script>

<template>
  <div class="stage">
    <section class="stage__card">
      <p class="stage__eyebrow">RST MTA LITE</p>
      <h1>准备进入比赛</h1>
      <p class="stage__server">{{ ui.serverName }}</p>

      <div v-if="ui.rooms.length" class="stage__rooms">
        <div v-for="room in ui.rooms" :key="room.id" class="stage__room">
          <strong>{{ room.name }}</strong>
          <small>{{ room.mapName || '暂无地图' }} · {{ room.players }} 玩家 / {{ room.spectators }} 观战</small>
        </div>
      </div>
      <p v-else class="stage__empty">当前没有可用舞台。</p>

      <button type="button" class="btn btn--primary stage__enter" :disabled="ui.busy" @click="enter">
        进入比赛
      </button>
      <p class="stage__hint">如果进入失败，检查服务器日志和地图资源后重试。</p>
    </section>
  </div>
</template>

<style scoped>
.stage {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 24px;
  background:
    radial-gradient(circle at 50% 10%, rgba(44, 110, 180, 0.2), transparent 55%),
    linear-gradient(180deg, #050a12 0%, #04070c 100%);
  pointer-events: auto;
}

.stage__card {
  width: min(430px, calc(100vw - 48px));
  padding: 28px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: var(--rst-panel);
  box-shadow: var(--rst-shadow);
}

.stage__eyebrow {
  margin: 0 0 6px;
  color: var(--rst-accent);
  font-size: 10px;
  letter-spacing: 0.12em;
}

.stage h1 {
  margin: 0;
  color: var(--rst-text);
  font-size: 22px;
}

.stage__server {
  margin: 8px 0 20px;
  color: var(--rst-muted);
  font-size: 11px;
}

.stage__rooms {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 18px;
}

.stage__room {
  display: flex;
  flex-direction: column;
  gap: 3px;
  padding: 10px;
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 9px;
  background: rgba(0, 0, 0, 0.16);
}

.stage__room strong {
  color: var(--rst-text);
  font-size: 12px;
}

.stage__room small {
  color: var(--rst-muted);
  font-size: 9px;
}

.stage__empty {
  margin: 0 0 18px;
  color: var(--rst-muted);
  font-size: 11px;
}

.stage__enter {
  width: 100%;
}

.stage__hint {
  margin: 12px 0 0;
  color: var(--rst-muted);
  font-size: 9px;
  text-align: center;
}
</style>
