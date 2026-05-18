import { createRouter, createWebHistory } from 'vue-router'
import HomeView from './views/HomeView.vue'
import MtlsView from './components/mtls/MtlsView.vue'
import Ipv6View from './components/ipv6/Ipv6View.vue'

// History mode: URLs limpas (/mtls, /ipv6). O backend Sinatra tem um
// catch-all que serve o index.html pra essas rotas (SPA fallback).
const routes = [
  { path: '/', name: 'home', component: HomeView, meta: { label: 'Home' } },
  { path: '/mtls', name: 'mtls', component: MtlsView, meta: { label: 'mTLS' } },
  { path: '/ipv6', name: 'ipv6', component: Ipv6View, meta: { label: 'IPv6' } },
  { path: '/:pathMatch(.*)*', redirect: '/' }
]

export const router = createRouter({
  history: createWebHistory(),
  routes
})
