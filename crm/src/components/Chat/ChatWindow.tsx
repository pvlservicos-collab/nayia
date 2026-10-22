'use client'

import { useState, useRef, useEffect, useCallback } from 'react'
import { codigoReferenciado } from '@/lib/imovelCodigo'
import { Image as ImageIcon, ArrowLeft, User, SidebarSimple, Robot } from '@phosphor-icons/react'
import { useLeadActivities, useAuth, useChatButtonSettings, useIsMobile } from '@/hooks'
import { usePinnedMessages } from '@/hooks/usePinnedMessages'
import { uploadClientFile } from '@/lib/blobClient'
import { formatPhone } from '@/lib/utils'
import { LeadWithOwner, LeadActivityWithActor } from '@/lib/types'
import type { LinhaWhatsapp } from '@/lib/leadChannel'
import type { EstadoDaNay, MarcaDaNay } from '@/lib/tiposNay'
import { useParceriaMarcas, recarregarMarcasDaParceria } from '@/hooks/useParceriaMarcas'
import ActivityTimeline from './ActivityTimeline'
import ActivityComposer, { ActivityComposerHandle } from './ActivityComposer'
import PinnedMessagesBar from './PinnedMessagesBar'

import { ChatButtonKey } from '@/hooks/useChatButtonSettings'
import { quandoCurtoEmManaus } from '@/lib/fusoDeManaus'
import { nayEmPausa } from '@/lib/etapaDaParceria'
import type { DonoNaLista } from '@/lib/tiposNay'
import { nomeDoDono, imovelDoDono } from './LeadListItem'
import { useEtiquetas, marcarEtiqueta } from '@/lib/etiquetas'

interface ChatWindowProps {
  lead: LeadWithOwner
  organizationId: string
  onMessageSent?: (content: string) => void
  /** A linha de WhatsApp da conversa: a Parceria tem transcrição de áudio e as marcas da Nay. */
  linha?: LinhaWhatsapp
  marca?: MarcaDaNay
  /** Oficial: o dono na captação. O título do lead ali é só o número, então o cabeçalho mostra o nome dele. */
  dono?: DonoNaLista
  painelAberto?: boolean
  aoAlternarPainel?: () => void
  /** Só no celular: volta para a lista. */
  aoVoltar?: () => void
  /** 19/10: a lista suspensa de etiquetas no cabeçalho (Captação) avisa a tela quando marca/desmarca */
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
}

export interface ReplyContext {
  messageId: string
  text: string
  sender: string
}

/* a hora da visita é a de Manaus, não a do computador (src/lib/fusoDeManaus.ts) */
function quandoCurto(iso: string | null): string {
  return quandoCurtoEmManaus(iso)
}

/**
 * A barra de cima da conversa, como no WhatsApp Web: foto, nome e, embaixo,
 * o telefone -- na Parceria, o que a Nay sabe da pessoa. Clicar no nome abre
 * (ou fecha) o card do contato.
 */
/*
 * O ROBÔ DA NAY (Pedro, 29/09/2026): "uma tagzinha de robô ao lado esquerdo no
 * topo do lead para sabermos se a Nay está ou não ativa nesse número... verde
 * ativa, vermelha inativa, ex. quando o Tel manda msg fica vermelho".
 * Vermelho: a Nay parada no geral (pausa, modo) ou nesta conversa (o Tel ou
 * alguém da equipe escreveu -- ela cala 30 min --, escalada, visita parada).
 * Quem decide é a Nay (crm_parceria_marcas / crm_nay_ligada).
 */
function RoboDaNay({ nay, marca }: { nay: EstadoDaNay | null; marca?: MarcaDaNay }) {
  const parada = !!nay && (!nay.ligada || !!marca?.telAtendendo)
  const cor = !nay ? 'var(--wa-text-2)' : parada ? 'var(--wa-tag-tel)' : 'var(--wa-green)'
  const texto = !nay ? 'Lendo a Nay…'
    : !nay.ligada ? `Nay parada: ${nay.motivo || 'desligada'}`
    : nayEmPausa(marca) ? 'Nay em pausa: alguém escreveu à mão nesta conversa, e ela espera 30 minutos antes de voltar a responder'
    : marca?.telAtendendo ? `Nay parada nesta conversa: ${marca.telMotivo || 'o Tel está com a conversa'}`
    : 'Nay atendendo esta conversa'
  return (
    <span className="wa-robo" style={{ ['--cor' as string]: cor }} title={texto} aria-label={texto} role="img">
      <Robot size={16} weight="fill" />
    </span>
  )
}

/* A LISTA SUSPENSA DE ETIQUETAS (Pedro, 19/10/2026: "coloca do lado do nome, no número de captação, uma lista suspensa
   com os nomes das etiquetas; ele pode selecionar por lá"). Escolheu uma: entra no card na hora; escolheu uma que ele
   já tem: sai. As etiquetas são as mesmas da prancheta (lib/etiquetas). */
function EtiquetasNoCabecalho({ lead, onTagsChange }: {
  lead: { id: string; lead_tags?: Array<{ tag_id: string; tag?: any }> | null }
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
}) {
  const etiquetas = useEtiquetas()
  const [mexendo, setMexendo] = useState(false)
  const tem = new Set((lead.lead_tags || []).map((lt) => lt.tag_id))
  const escolher = async (id: string) => {
    if (!id || mexendo) return
    const e = etiquetas.find((x) => x.id === id)
    const por = !tem.has(id)
    setMexendo(true)
    try {
      await marcarEtiqueta(lead.id, id, por)
      onTagsChange?.(lead.id, id, por ? 'add' : 'remove', e)
    } catch (err: any) {
      window.alert(err?.message || 'Não consegui mudar a etiqueta.')
    } finally {
      setMexendo(false)
    }
  }
  return (
    <span className="inline-flex items-center gap-1 flex-shrink-0 max-w-[46%]" onClick={(e) => e.stopPropagation()}>
      <span className="hidden md:flex items-center gap-1 overflow-hidden">
        {(lead.lead_tags || []).slice(0, 3).map((lt) => lt.tag && (
          <span key={lt.tag_id} className="text-[10px] font-semibold px-1.5 py-0.5 rounded-full truncate max-w-[88px]"
                style={{ background: (lt.tag.color || '#64748b') + '22', color: lt.tag.color || '#64748b' }} title={lt.tag.name}>{lt.tag.name}</span>
        ))}
      </span>
      <select value="" disabled={mexendo || !etiquetas.length} onChange={(e) => void escolher(e.target.value)}
              className="text-[12px] rounded-md px-1.5 py-1 max-w-[120px]"
              style={{ background: 'var(--wa-panel)', color: 'var(--wa-text-2)', border: '1px solid var(--wa-divider)' }}
              title="Marcar ou tirar uma etiqueta deste contato">
        <option value="">{mexendo ? '…' : etiquetas.length ? 'Etiqueta…' : 'sem etiquetas'}</option>
        {etiquetas.map((e) => (
          <option key={e.id} value={e.id}>{tem.has(e.id) ? '✓ ' : ''}{e.name}</option>
        ))}
      </select>
    </span>
  )
}

function CabecalhoConversa({ lead, marca, nay, mostrarRobo, painelAberto, aoAlternarPainel, aoVoltar, dono, etiquetasRapidas, onTagsChange }: {
  /** 19/10: a lista suspensa de etiquetas ao lado do nome (Captação) */
  etiquetasRapidas?: boolean
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
  lead: LeadWithOwner
  marca?: MarcaDaNay
  dono?: DonoNaLista
  nay?: EstadoDaNay | null
  mostrarRobo?: boolean
  painelAberto?: boolean
  aoAlternarPainel?: () => void
  aoVoltar?: () => void
}) {
  const partes: string[] = []
  if (nayEmPausa(marca)) partes.push('Nay em pausa (30 min)')
  else if (marca?.telAtendendo) partes.push((marca.telMotivo || '').startsWith('Rayssa:') ? 'com a Rayssa' : 'com o Tel')
  if (marca?.visitaAberta) partes.push(`visita ${quandoCurto(marca.visitaQuando)}`)
  if (marca?.corretor) partes.push(marca.creci ? `corretor · CRECI ${marca.creci}` : 'corretor')
  if (marca?.proprietario) partes.push('proprietário')
  /* O NOME DE QUEM É (Pedro, 09/10/2026: "o chat do api oficial está muito cru"). Na Oficial a conversa nasce do
     nosso modelo, e o título do lead é o número: o cabeçalho mostrava só "+55 92 9...". Com o dono da captação,
     aparece o nome e o imóvel dele, como na lista; o número desce para a linha de baixo. */
  const nomeDono = dono ? nomeDoDono(dono.nome) : ''
  if (nomeDono) {
    if (imovelDoDono(dono)) partes.push(imovelDoDono(dono))
    partes.push(formatPhone(lead.phone || ''))
  }
  const subtitulo = partes.length ? partes.join(' · ') : formatPhone(lead.phone || '')

  return (
    <div className="wa-topo gap-3 flex-shrink-0 relative z-20 !px-3" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
      {aoVoltar && (
        <button type="button" className="wa-icone-btn -mr-1" onClick={aoVoltar} aria-label="Voltar para a lista"><ArrowLeft size={22} /></button>
      )}
      {mostrarRobo && <RoboDaNay nay={nay ?? null} marca={marca} />}
      <button type="button" onClick={aoAlternarPainel} className="flex items-center gap-3 min-w-0 flex-1 text-left" title="Dados do contato">
        <span className="w-10 h-10 rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center" style={{ background: 'var(--wa-row-selected)' }}>
          {lead.avatar_url
            ? <img src={lead.avatar_url} alt="" className="w-full h-full object-cover" />
            : <User size={24} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.55 }} />}
        </span>
        <span className="min-w-0">
          <span className="block text-[16px] leading-[21px] truncate" style={{ color: 'var(--wa-text)' }}>{nomeDono || formatPhone(lead.title)}</span>
          <span className="block text-[13px] leading-[18px] truncate" style={{ color: marca?.telAtendendo ? 'var(--wa-tag-tel)' : 'var(--wa-text-2)' }}>
            {subtitulo}
          </span>
        </span>
      </button>
      {etiquetasRapidas && <EtiquetasNoCabecalho lead={lead} onTagsChange={onTagsChange} />}
      {aoAlternarPainel && (
        <button type="button" onClick={aoAlternarPainel} className={`wa-icone-btn ${painelAberto ? 'wa-icone-btn--on' : ''}`}
                title={painelAberto ? 'Fechar os dados do contato' : 'Dados do contato'} aria-pressed={!!painelAberto}>
          <SidebarSimple size={22} className="-scale-x-100" />
        </button>
      )}
    </div>
  )
}

export default function ChatWindow({ lead, organizationId, onMessageSent, linha, marca, dono, painelAberto, aoAlternarPainel, aoVoltar, onTagsChange }: ChatWindowProps) {
  const {
    activities, loading, error: erroDasMensagens, refresh: recarregarMensagens, sendHumanMessage, sendMediaMessage, deleteMessage,
    temMais, carregandoAnteriores, carregarAnteriores,
  } = useLeadActivities(organizationId, lead.id)
  const { pinned, pinnedActivityIds, togglePin } = usePinnedMessages(lead.id)
  const { currentOrganization } = useAuth()
  const { settings: chatButtonSettings, fireWebhook } = useChatButtonSettings()
  const [replyContext, setReplyContext] = useState<ReplyContext | null>(null)
  const [sendError, setSendError] = useState<string | null>(null)
  const ehCelular = useIsMobile()
  const composerRef = useRef<ActivityComposerHandle>(null)
  const ehParceria = linha === 'parceria'
  // o robô: a chave geral da Nay (a marca desta conversa já vem do pai)
  const { nay } = useParceriaMarcas(ehParceria)
  /* Mandou pelo CRM: a Nay vai calar por 30 min assim que o eco chegar a ela
     (segundos). Pede uma leitura nova para o robô ficar vermelho sem esperar
     o minuto da atualização. */
  const avisarANay = useCallback(() => {
    if (!ehParceria) return
    setTimeout(() => { void recarregarMarcasDaParceria(true) }, 8000)
  }, [ehParceria])

  /**
   * Abriu a conversa? O cursor já vai pro campo de texto (só no computador:
   * no celular o teclado cobriria a mensagem que a pessoa abriu pra ler).
   */
  useEffect(() => {
    if (ehCelular) return
    const id = requestAnimationFrame(() => composerRef.current?.focar())
    return () => cancelAnimationFrame(id)
  }, [lead.id, ehCelular])

  /*
   * OS ÁUDIOS ANTIGOS DA PARCERIA GANHAM TEXTO (29/09): o áudio novo é
   * transcrito quando chega; os de antes, quando a conversa abre -- uma vez
   * por abertura, e só se houver algum ainda sem texto. Cada transcrição
   * chega sozinha pela atualização da conversa.
   */
  const jaPediTranscricao = useRef(false)
  useEffect(() => {
    // as três linhas de WhatsApp (29/09); antes, só a Parceria
    if (!linha || jaPediTranscricao.current || loading) return
    const falta = activities.some((a) => a.metadata?.media_type === 'audio' && typeof a.metadata?.transcricao !== 'string'
      && !['sem_audio', 'falhou', 'andando'].includes(String(a.metadata?.transcricao_status || '')) && !a.metadata?.is_optimistic)
    if (!falta) return
    jaPediTranscricao.current = true
    fetch(`/api/leads/${lead.id}/transcrever`, { method: 'POST' }).catch(() => { jaPediTranscricao.current = false })
  }, [linha, activities, loading, lead.id])

  // Arrastar-e-soltar um arquivo em qualquer ponto da conversa (não só no clipe).
  const [isDraggingFile, setIsDraggingFile] = useState(false)
  const dragCounter = useRef(0)

  const handleDragEnter = (e: React.DragEvent) => {
    e.preventDefault()
    if (!e.dataTransfer.types.includes('Files')) return
    dragCounter.current += 1
    setIsDraggingFile(true)
  }
  const handleDragOver = (e: React.DragEvent) => { e.preventDefault() }
  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault()
    dragCounter.current = Math.max(0, dragCounter.current - 1)
    if (dragCounter.current === 0) setIsDraggingFile(false)
  }
  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault()
    dragCounter.current = 0
    setIsDraggingFile(false)
    const file = e.dataTransfer.files?.[0]
    if (file) composerRef.current?.receiveDroppedFile(file)
  }

  const handleSendActivity = async (content: string) => {
    if (!content.trim()) return
    setSendError(null)

    if (!currentOrganization) {
      setSendError('Sessão não identificada. Recarregue a página e tente novamente.')
      return
    }

    /* `/3050` MANDA O IMÓVEL (Tel, 27/09/2026): o card igual ao dos grupos e
       depois as fotos. Só a barra dispara isso: um "3050" solto é texto. */
    const codigoPedido = codigoReferenciado(content)
    if (codigoPedido) {
      try {
        const res = await fetch(`/api/leads/${lead.id}/enviar-imovel`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ codigo: codigoPedido }),
        })
        const j = await res.json()
        if (!res.ok) throw new Error(j?.error || 'não consegui mandar o imóvel')
        if (j.e_parceiro) {
          setSendError(`Atenção: o ${codigoPedido} é imóvel DE PARCEIRO. Ele foi enviado porque `
            + 'você pediu, mas a Nay nunca manda imóvel de parceiro.')
        } else if (j.fotos_que_falharam > 0) {
          setSendError(`O card do ${codigoPedido} saiu, mas ${j.fotos_que_falharam} foto(s) não foram.`)
        }
        recarregarMensagens()
      } catch (error: any) {
        console.error('Failed to send imóvel:', error)
        setSendError(error?.message || `Não consegui mandar o imóvel ${codigoPedido}.`)
      }
      return
    }

    try {
      avisarANay(); if (onMessageSent) onMessageSent(content)
      const replyMessageId = replyContext?.messageId
      const replyPreview = replyContext ? { text: replyContext.text, sender: replyContext.sender } : undefined
      setReplyContext(null)
      await sendHumanMessage(content, 'whatsapp', currentOrganization.id, replyMessageId, replyPreview)
    } catch (error) {
      console.error('Failed to send activity:', error)
      setSendError('Falha ao enviar mensagem. Verifique sua conexão e tente novamente.')
    }
  }

  const handleSendMedia = async (file: File, caption?: string) => {
    setSendError(null)
    let mediaType: 'image' | 'video' | 'audio' | 'document' = 'document'
    if (file.type.startsWith('image/')) mediaType = 'image'
    else if (file.type.startsWith('video/')) mediaType = 'video'
    else if (file.type.startsWith('audio/')) mediaType = 'audio'

    try {
      const url = await uploadClientFile(file, 'chat-media', lead.id)
      avisarANay(); if (onMessageSent) onMessageSent(caption || `[${mediaType}]`)
      await sendMediaMessage(url, mediaType, caption || '', file.name, file.type)
    } catch (error: any) {
      console.error('Failed to send media:', error)
      setSendError(`Falha ao enviar ${mediaType === 'audio' ? 'o áudio' : 'o arquivo'}: ${error?.message || 'verifique o arquivo e tente novamente'}.`)
    }
  }

  // Nota de voz não aceita legenda no WhatsApp: áudio com texto vai como duas mensagens.
  const sendQuickReplyStep = async (step: {
    content: string
    mediaUrl: string | null
    mediaType: string | null
    mediaFilename?: string | null
    mediaMimetype?: string | null
  }) => {
    if (step.mediaUrl && step.mediaType) {
      if (step.mediaType === 'audio' && step.content.trim()) {
        await sendMediaMessage(step.mediaUrl, 'audio', '', step.mediaFilename || undefined, step.mediaMimetype || undefined)
        await sendHumanMessage(step.content, 'whatsapp', currentOrganization?.id)
      } else {
        await sendMediaMessage(
          step.mediaUrl,
          step.mediaType as 'image' | 'video' | 'audio' | 'document' | 'sticker',
          step.content,
          step.mediaFilename || undefined,
          step.mediaMimetype || undefined
        )
      }
      return
    }
    if (step.content.trim()) await sendHumanMessage(step.content, 'whatsapp', currentOrganization?.id)
  }

  const handleSendQuickReplyMedia = async (qr: {
    content: string
    mediaUrl: string
    mediaType: string
    mediaFilename?: string | null
    mediaMimetype?: string | null
  }) => {
    setSendError(null)
    try {
      avisarANay(); if (onMessageSent) onMessageSent(qr.content || `[${qr.mediaType}]`)
      await sendQuickReplyStep(qr)
    } catch (error) {
      console.error('Failed to send quick reply media:', error)
      setSendError('Falha ao enviar mídia. Verifique sua conexão e tente novamente.')
    }
  }

  const handleSendQuickReplySequence = async (steps: {
    content: string
    mediaUrl: string | null
    mediaType: string | null
    mediaFilename?: string | null
    mediaMimetype?: string | null
    delaySeconds: number
  }[]) => {
    setSendError(null)
    for (let i = 0; i < steps.length; i++) {
      const step = steps[i]
      try {
        avisarANay(); if (onMessageSent) onMessageSent(step.content || (step.mediaType ? `[${step.mediaType}]` : ''))
        await sendQuickReplyStep(step)
        if (step.delaySeconds > 0 && i < steps.length - 1) {
          await new Promise((resolve) => setTimeout(resolve, step.delaySeconds * 1000))
        }
      } catch (error) {
        console.error(`Failed to send quick reply sequence step ${i + 1}/${steps.length}:`, error)
        setSendError(`Falha ao enviar o passo ${i + 1} de ${steps.length}. As mensagens anteriores já foram enviadas.`)
        return
      }
    }
  }

  /* Estáveis entre um desenho e outro: sem isso a conversa inteira (até 300
     balões) se redesenhava a cada atualização, e abrir conversa ficava lento. */
  const handleDeleteMessage = useCallback(async (activity: LeadActivityWithActor, deleteForEveryone: boolean) => {
    setSendError(null)
    try {
      const result = await deleteMessage(activity.id, deleteForEveryone)
      if (deleteForEveryone && result.channel_supports_delete && !result.deleted_for_everyone) {
        setSendError(`Mensagem removida do CRM, mas não foi possível apagar no WhatsApp do cliente: ${result.delete_error || 'erro desconhecido'}`)
      }
    } catch (error) {
      console.error('Failed to delete message:', error)
      setSendError(error instanceof Error ? error.message : 'Falha ao apagar mensagem.')
    }
  }, [deleteMessage])

  const tituloDoLead = lead.title
  const handleReply = useCallback((activity: LeadActivityWithActor) => {
    const messageId = activity.metadata?.message_id || activity.id
    const text = activity.content || ''
    const sender = activity.metadata?.sender_name || activity.actor?.profiles?.full_name || tituloDoLead || 'Lead'
    setReplyContext({ messageId, text, sender })
  }, [tituloDoLead])

  const handleUnpin = (activityId: string) => {
    const pin = pinned.find((p) => p.activity_id === activityId)
    if (pin) togglePin(pin.activity)
  }

  return (
    <div
      className="wa-papel flex flex-col h-full relative overflow-x-hidden"
      onDragEnter={handleDragEnter}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <CabecalhoConversa lead={lead} marca={marca} nay={nay} mostrarRobo={false} painelAberto={painelAberto} aoAlternarPainel={aoAlternarPainel} aoVoltar={aoVoltar} dono={dono}
                         etiquetasRapidas={linha === 'captacao'} onTagsChange={onTagsChange} />

      {/* Arrastar-e-soltar — cobre a conversa inteira, não só o clipe */}
      {isDraggingFile && (
        <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/50 backdrop-blur-sm pointer-events-none animate-in fade-in duration-150">
          <div className="flex flex-col items-center gap-3 border-4 border-dashed rounded-2xl px-12 py-10"
               style={{ borderColor: 'var(--wa-green)', background: 'var(--wa-panel)' }}>
            <ImageIcon size={40} weight="bold" style={{ color: 'var(--wa-green)' }} />
            <p className="text-sm font-bold" style={{ color: 'var(--wa-text)' }}>Solte o arquivo para enviar</p>
          </div>
        </div>
      )}

      <div className="relative z-10"><PinnedMessagesBar pinned={pinned} onUnpin={handleUnpin} /></div>

      {/* Falha ao carregar: avisa e deixa tentar de novo, em vez de abrir calada. */}
      {erroDasMensagens && activities.length === 0 && !loading && (
        <div className="relative z-10 mx-4 mt-2 px-4 py-2.5 bg-amber-500/10 border border-amber-500/30 rounded-xl flex items-center justify-between gap-3">
          <span className="text-sm" style={{ color: 'var(--wa-tag-prop)' }}>Não consegui carregar as mensagens desta conversa.</span>
          <button onClick={() => recarregarMensagens(true)} className="btn btn-outline btn-sm !py-1 !text-[11px] flex-shrink-0 text-[var(--wa-text)] dark:text-ink">Tentar de novo</button>
        </div>
      )}

      <ActivityTimeline
        activities={activities}
        loading={loading}
        lead={lead}
        onReply={handleReply}
        onTogglePin={togglePin}
        onDelete={handleDeleteMessage}
        pinnedActivityIds={pinnedActivityIds}
        mostrarTranscricao={!!linha}
        temMais={temMais}
        carregandoAnteriores={carregandoAnteriores}
        onCarregarAnteriores={carregarAnteriores}
      />

      {sendError && (
        <div className="relative z-10 mx-4 mb-2 px-4 py-2.5 bg-red-500/10 border border-red-500/30 rounded-xl flex items-center justify-between">
          <span className="text-sm" style={{ color: 'var(--wa-tag-tel)' }}>{sendError}</span>
          <button onClick={() => setSendError(null)} className="text-xs font-bold ml-3" style={{ color: 'var(--wa-tag-tel)' }}>✕</button>
        </div>
      )}

      <ActivityComposer
        ref={composerRef}
        onSend={handleSendActivity}
        onSendMedia={handleSendMedia}
        onSendQuickReplyMedia={handleSendQuickReplyMedia}
        onSendQuickReplySequence={handleSendQuickReplySequence}
        organizationId={organizationId}
        lead={{ title: lead.title, phone: lead.phone }}
        rascunhoId={lead.id}
        replyContext={replyContext}
        onCancelReply={() => setReplyContext(null)}
        chatButtonSettings={chatButtonSettings}
        fireWebhook={async (key: ChatButtonKey) => {
          return fireWebhook(key, {
            id: lead.id,
            title: lead.title,
            phone: lead.phone,
            email: lead.email,
            stageName: lead.stage?.name,
          })
        }}
      />
    </div>
  )
}
