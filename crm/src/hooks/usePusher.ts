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
import { useEffect, useRef, useState } from 'react'
import PusherClient from 'pusher-js'

let _pusherClient: PusherClient | null = null

/*
 * QUEM VOLTA PARA A ABA (04/10, Pedro: "a Rayssa comentou que o CRM dela não
 * estava chegando mensagem"). No celular o navegador congela a aba que sai da
 * tela e a ligação com o Pusher morre calada: o pusher-js só percebe no próximo
 * teste de vida (até 2 min e meio), e até lá a tela acha que está ligada e não
 * recebe nada. Quem ficou mais de 30 s fora refaz a ligação ao voltar; os canais
 * são reassinados sozinhos e cada tela busca de novo pelo `__reconnected`.
 */
const FORA_DA_TELA_MS = 30_000

function refazerAoVoltar(pusher: PusherClient) {
  let escondidaDesde = 0
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      escondidaDesde = Date.now()
      return
    }
    const fora = escondidaDesde ? Date.now() - escondidaDesde : 0
    escondidaDesde = 0
    if (fora < FORA_DA_TELA_MS) return
    try {
      pusher.disconnect()
      pusher.connect()
    } catch {}
  })
}

function getPusherClient(): PusherClient {
  if (typeof window === 'undefined') throw new Error('Pusher só pode ser usado no cliente')
  if (!_pusherClient) {
    const key = process.env.NEXT_PUBLIC_PUSHER_KEY
    const cluster = process.env.NEXT_PUBLIC_PUSHER_CLUSTER
    if (!key || !cluster) {
      throw new Error('NEXT_PUBLIC_PUSHER_KEY e NEXT_PUBLIC_PUSHER_CLUSTER não definidos')
    }
    _pusherClient = new PusherClient(key, { cluster })
    refazerAoVoltar(_pusherClient)
  }
  return _pusherClient
}

type EventHandlers = Record<string, (data?: any) => void>

/*
 * Quantas telas usam cada canal. O canal da organização é assinado pela lista
 * de conversas E pelo aviso de desconexão; o da conversa, pelas mensagens E
 * pelas fixadas. Antes, a primeira que saía desassinava o canal inteiro e
 * tirava os ouvintes das outras (unbind sem a função tira todos): a que ficava
 * parava de receber até ser montada de novo. Agora cada uma tira só o que é
 * dela, e o canal só é desassinado quando a última sai.
 */
const usosDoCanal = new Map<string, number>()

/**
 * handlers['__reconnected'], se fornecido, é chamado sempre que a conexão
 * WebSocket reconectar após cair (ex: notebook hibernou, troca de rede).
 * Eventos publicados enquanto desconectado não chegam retroativamente,
 * então use esse handler para refazer o fetch e não perder atualizações.
 */
export function usePusherChannel(channelName: string, handlers: EventHandlers) {
  const handlersRef = useRef(handlers)
  handlersRef.current = handlers
  const eventos = Object.keys(handlers).filter((e) => e !== '__reconnected').sort().join('|')

  useEffect(() => {
    if (!channelName || typeof window === 'undefined') return

    let pusher: PusherClient
    let channel: ReturnType<PusherClient['subscribe']>
    let wasConnected = false
    const meus: Array<[string, (data?: any) => void]> = []

    const handleStateChange = (states: { previous: string; current: string }) => {
      if (states.current === 'connected') {
        if (wasConnected) handlersRef.current['__reconnected']?.()
        wasConnected = true
      }
    }

    try {
      pusher = getPusherClient()
      // quem entra com a ligação já de pé também é avisado na primeira queda
      wasConnected = pusher.connection.state === 'connected'
      channel = pusher.subscribe(channelName)
      usosDoCanal.set(channelName, (usosDoCanal.get(channelName) || 0) + 1)

      for (const event of eventos.split('|').filter(Boolean)) {
        // sempre a função de agora, não a da hora da inscrição
        const meu = (data?: any) => handlersRef.current[event]?.(data)
        channel.bind(event, meu)
        meus.push([event, meu])
      }

      pusher.connection.bind('state_change', handleStateChange)
    } catch (err) {
      console.warn('[Pusher] Falha ao assinar canal:', channelName, err)
      return
    }

    return () => {
      try {
        for (const [event, meu] of meus) channel.unbind(event, meu)
        pusher.connection.unbind('state_change', handleStateChange)
        const resto = (usosDoCanal.get(channelName) || 1) - 1
        if (resto > 0) {
          usosDoCanal.set(channelName, resto)
        } else {
          usosDoCanal.delete(channelName)
          pusher.unsubscribe(channelName)
        }
      } catch {}
    }
  }, [channelName, eventos])
}

/**
 * A ligação com o Pusher está de pé agora? Enquanto não está (rede caiu, celular
 * voltando do descanso), nenhum evento chega: quem depende deles deve buscar por
 * conta própria, mais depressa. Sem Pusher configurado, é sempre `false`.
 */
export function usePusherConectado(): boolean {
  const [conectado, setConectado] = useState(true)

  useEffect(() => {
    let pusher: PusherClient
    try {
      pusher = getPusherClient()
    } catch {
      setConectado(false)
      return
    }
    const ver = () => setConectado(pusher.connection.state === 'connected')
    ver()
    pusher.connection.bind('state_change', ver)
    return () => {
      pusher.connection.unbind('state_change', ver)
    }
  }, [])

  return conectado
}
