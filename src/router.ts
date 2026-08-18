import { createRouter, createWebHistory } from 'vue-router'
import ScanPage from './pages/ScanPage.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/scan', component: ScanPage },
    { path: '/:pathMatch(.*)*', component: () => import('./App.vue') },
  ],
})

export default router
