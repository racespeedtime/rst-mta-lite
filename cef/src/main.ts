import { createApp } from 'vue'

import App from './App.vue'
import { installBridge, installMockServer } from './mta/bridge'
import { applyTheme, loadThemeSettings } from './theme'
import { installUiScale } from './ui-scale'
import './styles/main.css'

installBridge()
installUiScale()
installMockServer()

applyTheme(loadThemeSettings())

createApp(App).mount('#app')
