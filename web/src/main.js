import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { http } from './api/http'
import { createAppI18n, persistLocale } from './i18n'
import { createAppRouter } from './router'
import './styles/base.css'

const i18n = createAppI18n()
const locale = i18n.global.locale.value
persistLocale(locale)
http.language = locale

const pinia = createPinia()
const router = createAppRouter(pinia)

createApp(App).use(pinia).use(i18n).use(router).mount('#app')
