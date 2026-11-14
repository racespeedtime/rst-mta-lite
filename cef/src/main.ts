import { createApp } from 'vue'

import App from './App.vue'
import { installBridge, installMockServer } from './mta/bridge'
import './styles/main.css'

installBridge()
installMockServer()

createApp(App).mount('#app')
