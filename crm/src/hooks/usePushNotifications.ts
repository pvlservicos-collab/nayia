'use client'

import { useCallback, useEffect, useState } from 'react'

export type PushStatus = 'loading' | 'unsupported' | 'ios-not-installed' | 'denied' | 'unsubscribed' | 'subscribed'

// VAPID exige a chave pública nesse formato (Uint8Array), não a string base64url crua
// que vem do env — conversão padrão do protocolo Web Push.
function urlBase64ToUint8Array(base64Url: string): Uint8Array<ArrayBuffer> {
  const padding = '='.repeat((4 - (base64Url.length % 4)) % 4)
  const base64 = (base64Url + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(base64)
  const bytes = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i)
  return bytes
}

export function usePushNotifications() {
  const [status, setStatus] = useState<PushStatus>('loading')

  const checkStatus = useCallback(async () => {
    // Mesma checagem de iOS/instalado do InstallAppBanner.tsx — no Safari do iPhone,
    // push só funciona se o app já estiver adicionado à Tela de Início.
    const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent)
    const isStandalone =
      window.matchMedia('(display-mode: standalone)').matches || (window.navigator as any).standalone === true
    if (isIOS && !isStandalone) {
      setStatus('ios-not-installed')
      return
    }

    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      setStatus('unsupported')
      return
    }
    if (Notification.permission === 'denied') {
      setStatus('denied')
      return
    }

    try {
      const registration = await navigator.serviceWorker.ready
      const sub = await registration.pushManager.getSubscription()
      setStatus(sub ? 'subscribed' : 'unsubscribed')
    } catch {
      setStatus('unsupported')
    }
  }, [])

  useEffect(() => {
    checkStatus()
  }, [checkStatus])

  const subscribe = useCallback(async () => {
    const permission = await Notification.requestPermission()
    if (permission !== 'granted') {
      // 'denied' de verdade só quando a pessoa clica "Bloquear" — se ela só fechou o
      // prompt sem escolher (Esc, tocar fora), o navegador devolve 'default' e ainda
      // deixa perguntar de novo depois. Só nesse segundo caso volta pra
      // 'unsubscribed' em vez de 'denied', senão o convite para de aparecer mesmo
      // sem ter sido bloqueado de verdade.
      setStatus(permission === 'denied' ? 'denied' : 'unsubscribed')
      return
    }

    const registration = await navigator.serviceWorker.ready
    const sub = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!),
    })
    const json = sub.toJSON()

    await fetch('/api/push-subscriptions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ endpoint: json.endpoint, keys: json.keys, userAgent: navigator.userAgent }),
    })
    setStatus('subscribed')
  }, [])

  const unsubscribe = useCallback(async () => {
    const registration = await navigator.serviceWorker.ready
    const sub = await registration.pushManager.getSubscription()
    if (sub) {
      await fetch(`/api/push-subscriptions?endpoint=${encodeURIComponent(sub.endpoint)}`, { method: 'DELETE' }).catch(() => {})
      await sub.unsubscribe()
    }
    setStatus('unsubscribed')
  }, [])

  return { status, subscribe, unsubscribe }
}
