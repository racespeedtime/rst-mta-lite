import { createRouter, createWebHashHistory } from 'vue-router'

import EmptyView from '@/views/EmptyView.vue'
import MenuView from '@/views/MenuView.vue'

const router = createRouter({
  // CEF 里页面走 http://mta/local/ 自定义协议，不能依赖服务端 rewrite，必须用 hash
  history: createWebHashHistory(),
  routes: [
    { path: '/', name: 'hud', component: EmptyView },
    { path: '/menu', name: 'menu', component: MenuView },
  ],
})

export default router
