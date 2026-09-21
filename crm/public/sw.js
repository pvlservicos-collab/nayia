// Service worker mínimo — existe só pra satisfazer o critério de instalabilidade do
// Chrome/Android ("Adicionar à tela de início"). Este é um CRM de atendimento ao vivo,
// então não faz sentido cachear dados/mensagens: toda requisição segue direto pra rede.
self.addEventListener('install', () => {
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('fetch', () => {
  // Intencionalmente vazio — deixa o navegador seguir com o fetch normal.
})

// Notificações push (mensagem nova chegou) — payload vem de src/lib/push.ts:
// { title, body, url, tag }.
self.addEventListener('push', (event) => {
  if (!event.data) return
  let payload
  try {
    payload = event.data.json()
  } catch {
    payload = { title: 'Nova mensagem', body: event.data.text() }
  }

  event.waitUntil(
    self.registration.showNotification(payload.title || 'Nova mensagem', {
      body: payload.body || '',
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      tag: payload.tag || 'atlaseye-message',
      // Sem isso, mensagens seguintes com a mesma tag (mesmo lead) substituem a
      // notificação em silêncio em vez de alertar de novo — igual o WhatsApp alerta
      // a cada mensagem nova mesmo dentro da mesma conversa.
      renotify: true,
      data: { url: payload.url || '/chat' },
    })
  )
})

// Toca na notificação → foca uma aba já aberta do CRM se existir, senão abre uma nova
// direto na conversa (mesmo formato de link /chat?leadId=... usado no sino do app).
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const targetUrl = event.notification.data?.url || '/chat'

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (new URL(client.url).origin === self.location.origin && 'focus' in client) {
          if ('navigate' in client) client.navigate(targetUrl)
          return client.focus()
        }
      }
      return self.clients.openWindow(targetUrl)
    })
  )
})
