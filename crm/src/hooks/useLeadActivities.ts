'use client'

/**
 * useLeadActivities — substitui queries diretas ao Supabase
 * Busca atividades via API + Pusher para realtime
 */
import { useState, useEffect, useCallback, useRef } from 'react'
import { useSession } from 'next-auth/react'
import { LeadActivityWithActor } from '@/lib/types'
import { usePusherChannel } from './usePusher'
import { useAtualizacaoPeriodica } from './useAtualizacaoPeriodica'
import { useNotification } from '@/contexts/NotificationContext'

const CHANNEL_LABELS: Record<string, string> = {
  whatsapp_evolution: 'Nº 2 (Evolution)',
  whatsapp_zapi: 'Z-API',
  whatsapp_cloud_official: 'API Oficial',
}

/*
 * Última versão de cada conversa já aberta nesta aba. Reabrir uma conversa
 * mostra na hora o que ela tinha (e atualiza por trás), em vez de esperar o
 * servidor. É por conversa — a chave é o id do lead —, então nunca mistura.
 */
const conversasJaAbertas = new Map<string, LeadActivityWithActor[]>()
const LIMITE_DE_CONVERSAS_GUARDADAS = 60

function guardarConversa(leadId: string, atividades: LeadActivityWithActor[]) {
  conversasJaAbertas.delete(leadId) // reinsere no fim: a mais recente fica por último
  conversasJaAbertas.set(leadId, atividades)
  if (conversasJaAbertas.size > LIMITE_DE_CONVERSAS_GUARDADAS) {
    const maisAntiga = conversasJaAbertas.keys().next().value
    if (maisAntiga) conversasJaAbertas.delete(maisAntiga)
  }
}

export function useLeadActivities(organizationId: string, leadId: string) {
  const { data: session } = useSession()
  const { addNotification } = useNotification()
  const [activities, setActivities] = useState<LeadActivityWithActor[]>(() => conversasJaAbertas.get(leadId) ?? [])
  const [loading, setLoading] = useState(() => !conversasJaAbertas.has(leadId))
  const [error, setError] = useState<string | null>(null)

  /*
   * Precisão ao trocar de conversa. As mensagens chegam do servidor depois de
   * um tempo, e sem estas duas travas a tela mostrava a conversa errada:
   *
   *   1. trocou de A pra B: o nome já era B, mas as mensagens continuavam as de
   *      A até as de B chegarem — "cliquei numa e abriu outra";
   *   2. uma busca de A ainda em andamento (a abertura ou a atualização de 4 em
   *      4 segundos) terminava DEPOIS da de B e escrevia as mensagens de A por
   *      cima de B.
   *
   * Agora a troca limpa na hora (ou mostra a versão guardada de B), e toda
   * resposta confere se ainda é da conversa aberta antes de entrar na tela.
   * Quem usa isto no chat também remonta a conversa por lead (key), o que já
   * garante o mesmo — as travas ficam pra qualquer outro uso.
   */
  const leadAberto = useRef(leadId)
  leadAberto.current = leadId
  const [leadDoEstado, setLeadDoEstado] = useState(leadId)
  if (leadDoEstado !== leadId) {
    setLeadDoEstado(leadId)
    setActivities(conversasJaAbertas.get(leadId) ?? [])
    setLoading(!conversasJaAbertas.has(leadId))
  }

  const fetchActivities = useCallback(async (showLoading = true) => {
    if (!organizationId || !leadId) return
    if (!session) return
    const alvo = leadId
    try {
      if (showLoading && !conversasJaAbertas.has(alvo)) setLoading(true)
      const res = await fetch(`/api/leads/${alvo}/messages`)
      if (!res.ok) throw new Error('Falha ao carregar atividades')
      const json = await res.json()
      if (leadAberto.current !== alvo) return // a pessoa já está em outra conversa

      const filtered = (json.data || []).filter((a: any) => {
        if (a.type === 'system' && a.metadata?.source === 'custom_field') return false
        return true
      })
      guardarConversa(alvo, filtered)
      setError(null) // deu certo agora: some o aviso de falha anterior
      // Mensagem otimista (a que acabou de ser digitada e ainda está a caminho do
      // servidor) fica na tela até o envio terminar — a busca periódica pode
      // chegar no meio e, sem isto, a mensagem piscaria: some e volta.
      setActivities((prev) => {
        const pendentes = prev.filter((a) => a.metadata?.is_optimistic && a.lead_id === alvo)
        const proxima = pendentes.length ? [...filtered, ...pendentes] : filtered
        // Nada mudou: devolve o mesmo array e o React não redesenha a conversa.
        if (JSON.stringify(proxima) === JSON.stringify(prev)) return prev
        return proxima
      })
    } catch (err) {
      if (leadAberto.current === alvo) setError(err instanceof Error ? err.message : 'Erro desconhecido')
    } finally {
      if (leadAberto.current === alvo) setLoading(false)
    }
  }, [organizationId, leadId, session])

  useEffect(() => {
    fetchActivities(true)
  }, [fetchActivities])

  // Mensagem que o lead manda aparece sozinha na conversa aberta, sem recarregar
  // (ver useAtualizacaoPeriodica — é o que substitui o Pusher, que está fora).
  useAtualizacaoPeriodica(() => fetchActivities(false), 4000, { ativo: !!leadId })

  // Realtime via Pusher
  usePusherChannel(`lead-${leadId}`, {
    'activity.created': () => {
      setActivities((prev) => prev.filter((a) => !a.metadata?.is_optimistic))
      fetchActivities(false)
    },
    'activity.updated': () => fetchActivities(false),
    '__reconnected': () => fetchActivities(false),
  })

  const sendHumanMessage = async (
    content: string,
    type: 'whatsapp' | 'note' | 'system' = 'whatsapp',
    memberId?: string,
    replyMessageId?: string,
    replyPreview?: { text: string; sender: string }
  ) => {
    if (!content.trim()) return

    // Optimistic update
    const tempId = `temp-${Date.now()}`
    const optimisticMsg: LeadActivityWithActor = {
      id: tempId,
      organization_id: organizationId,
      lead_id: leadId,
      type,
      content,
      actor_member_id: memberId || null,
      metadata: {
        direction: 'outbound',
        source: 'human',
        status: 'sent',
        is_optimistic: true,
        ...(replyMessageId && replyPreview
          ? { quoted_text: replyPreview.text, quoted_sender: replyPreview.sender, quoted_stanza_id: replyMessageId }
          : {}),
      },
      created_at: new Date().toISOString(),
      actor: undefined,
    }
    setActivities((prev) => [...prev, optimisticMsg])


    try {
      const body: any = {
        content,
        type,
        source: 'human',
        direction: 'outbound',
      }
      if (replyMessageId) body.reply_to_message_id = replyMessageId

      const res = await fetch(`/api/leads/${leadId}/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })

      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.error || 'Falha ao enviar mensagem')
      }

      const data = await res.json()
      if (data.send_status === 'failed') {
        const channelLabel = CHANNEL_LABELS[data.channel] || data.channel || 'WhatsApp'
        addNotification({
          type: 'error',
          title: 'Falha ao enviar mensagem',
          message: `Não foi possível enviar para ${data.lead_name || 'o contato'} via ${channelLabel}: ${data.send_error || 'erro desconhecido'}`,
        })
      }

      // Busca a mensagem real ANTES de tirar a otimista. Antes a otimista era
      // removida esperando o tempo real trazer a verdadeira — e com o tempo real
      // fora do ar, a mensagem que a pessoa acabou de mandar SUMIA da tela até
      // recarregar a página.
      await fetchActivities(false)
      setActivities((prev) => prev.filter((a) => a.id !== tempId))
    } catch (err) {
      // Revert optimistic on error
      setActivities((prev) => prev.filter((a) => a.id !== tempId))
      throw err
    }
  }

  const MEDIA_LABELS: Record<string, string> = {
    image: '📷 Imagem',
    video: '🎥 Vídeo',
    audio: '🎵 Áudio',
    document: '📄 Documento',
    sticker: '✨ Figurinha',
  }

  const sendMediaMessage = async (
    mediaUrl: string,
    mediaType: 'image' | 'video' | 'audio' | 'document' | 'sticker',
    caption: string,
    mediaFilename?: string,
    mediaMimetype?: string
  ) => {
    const content = caption.trim() || MEDIA_LABELS[mediaType] || '📎 Mídia'
    const tempId = `temp-${Date.now()}`
    const optimisticMsg: LeadActivityWithActor = {
      id: tempId,
      organization_id: organizationId,
      lead_id: leadId,
      type: 'whatsapp',
      content,
      actor_member_id: null,
      metadata: {
        direction: 'outbound',
        source: 'human',
        status: 'sent',
        is_optimistic: true,
        media_url: mediaUrl,
        media_type: mediaType,
        media_filename: mediaFilename,
        media_mimetype: mediaMimetype,
      },
      created_at: new Date().toISOString(),
      actor: undefined,
    }
    setActivities((prev) => [...prev, optimisticMsg])

    try {
      const body: any = {
        content,
        // Legenda de verdade — só preenchida se alguém realmente escreveu algo.
        // "content" acima pode ser um rótulo interno (ex: "📷 Imagem") usado só
        // pra timeline/lista do CRM; nunca deve ser enviado como legenda real.
        caption: caption.trim() || null,
        type: 'whatsapp',
        source: 'human',
        direction: 'outbound',
        media_url: mediaUrl,
        media_type: mediaType,
        media_filename: mediaFilename,
        media_mimetype: mediaMimetype,
      }

      const res = await fetch(`/api/leads/${leadId}/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })

      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.error || 'Falha ao enviar mídia')
      }

      const data = await res.json()
      if (data.send_status === 'failed') {
        const channelLabel = CHANNEL_LABELS[data.channel] || data.channel || 'WhatsApp'
        addNotification({
          type: 'error',
          title: 'Falha ao enviar mídia',
          message: `Não foi possível enviar para ${data.lead_name || 'o contato'} via ${channelLabel}: ${data.send_error || 'erro desconhecido'}`,
        })
      }

      // Mesmo motivo do envio de texto: a real primeiro, a otimista depois.
      await fetchActivities(false)
      setActivities((prev) => prev.filter((a) => a.id !== tempId))
    } catch (err) {
      setActivities((prev) => prev.filter((a) => a.id !== tempId))
      throw err
    }
  }

  const deleteMessage = async (activityId: string, deleteForEveryone: boolean) => {
    // Optimistic: já mostra o balão "Mensagem apagada" antes da resposta do servidor
    const prevActivities = activities
    setActivities((prev) =>
      prev.map((a) => (a.id === activityId ? { ...a, metadata: { ...a.metadata, deleted: true } } : a))
    )

    try {
      const res = await fetch(`/api/leads/${leadId}/messages/${activityId}`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deleteForEveryone }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) throw new Error(data.error || 'Falha ao apagar mensagem')
      return data as {
        success: true
        deleted_for_everyone: boolean
        channel_supports_delete: boolean
        delete_error: string | null
      }
    } catch (err) {
      setActivities(prevActivities)
      throw err
    }
  }

  return { activities, loading, error, sendHumanMessage, sendMediaMessage, deleteMessage, refresh: fetchActivities }
}
