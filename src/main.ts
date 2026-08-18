import './assets/main.css'

import { createApp } from 'vue'
import App from './App.vue'
import router from './router'

// Use a wrapper that decides which page to render
import Root from './Root.vue'

createApp(Root).use(router).mount('#app')
