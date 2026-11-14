import { createApp } from 'vue'

import App from './App.vue'
import { installBridge, installMockServer } from './mta/bridge'
import { installUiScale } from './ui-scale'
import './styles/main.css'

installBridge()
installUiScale()
installMockServer()

createApp(App).mount('#app')
