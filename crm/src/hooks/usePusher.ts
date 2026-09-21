'use client'

/**
 * usePusher — hook de realtime para o cliente
 * Substitui supabase.channel().on('postgres_changes').subscribe()
 *
 * Uso:
 *   usePusherChannel(`lead-${leadId}`, {
 *     'activity.created': (data) => { ... },
 *     'lead.updated': () => refetch(),
 *   })
 */
import { useEffect, useRef } from 'react'
import PusherClient from 'pusher-js'

let _pusherClient: PusherClient | null = null

function getPusherClient(): PusherClient {
  if (typeof window === 'undefined') throw new Error('Pusher só pode ser usado no cliente')
  if (!_pusherClient) {
    const key = process.env.NEXT_PUBLIC_PUSHER_KEY
    const cluster = process.env.NEXT_PUBLIC_PUSHER_CLUSTER
    if (!key || !cluster) {
      throw new Error('NEXT_PUBLIC_PUSHER_KEY e NEXT_PUBLIC_PUSHER_CLUSTER não definidos')
    }
    _pusherClient = new PusherClient(key, { cluster })
  }
  return _pusherClient
}

type EventHandlers = Record<string, (data?: any) => void>

/**
 * handlers['__reconnected'], se fornecido, é chamado sempre que a conexão
 * WebSocket reconectar após cair (ex: notebook hibernou, troca de rede).
 * Eventos publicados enquanto desconectado não chegam retroativamente,
 * então use esse handler para refazer o fetch e não perder atualizações.
 */
export function usePusherChannel(channelName: string, handlers: EventHandlers) {
  const handlersRef = useRef(handlers)
  handlersRef.current = handlers

  useEffect(() => {
    if (!channelName || typeof window === 'undefined') return

    let pusher: PusherClient
    let channel: ReturnType<PusherClient['subscribe']>
    let wasConnected = false

    const handleStateChange = (states: { previous: string; current: string }) => {
      if (states.current === 'connected') {
        if (wasConnected) handlersRef.current['__reconnected']?.()
        wasConnected = true
      }
    }

    try {
      pusher = getPusherClient()
      channel = pusher.subscribe(channelName)

      Object.entries(handlersRef.current).forEach(([event, handler]) => {
        if (event === '__reconnected') return
        channel.bind(event, handler)
      })

      pusher.connection.bind('state_change', handleStateChange)
    } catch (err) {
      console.warn('[Pusher] Falha ao assinar canal:', channelName, err)
      return
    }

    return () => {
      try {
        Object.keys(handlersRef.current).forEach((event) => {
          if (event === '__reconnected') return
          channel.unbind(event)
        })
        pusher.connection.unbind('state_change', handleStateChange)
        pusher.unsubscribe(channelName)
      } catch {}
    }
  }, [channelName])
}
