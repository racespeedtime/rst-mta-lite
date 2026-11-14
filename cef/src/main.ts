import { createApp } from 'vue'

import App from './App.vue'
import { installBridge, installMockServer } from './mta/bridge'
import router from './router'
import './styles/main.css'

installBridge()
installMockServer()

createApp(App).use(router).mount('#app')
