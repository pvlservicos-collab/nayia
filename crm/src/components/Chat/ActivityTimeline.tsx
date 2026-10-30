'use client'

import { useRef, useEffect, useLayoutEffect, useState, useMemo, memo, useCallback } from 'react'
import { Sparkle, X, Play, Pause, Microphone, ArrowBendUpLeft, ArrowBendUpRight, Check, Checks, WarningCircle, Lightning, PushPin, Trash, Prohibit, FileText, DownloadSimple, CaretDown, CaretLeft, CaretRight } from '@phosphor-icons/react'
import { LeadActivityWithActor, LeadWithOwner } from '@/lib/types'
import { formatTime } from '@/lib/utils'
import ImovelCitado from './ImovelCitado'
import TextoComLinks from './TextoComLinks'
import ContatoCompartilhado from './ContatoCompartilhado'
import DocumentoPdf, { ehPdf } from './VisualizadorPdf'
import { useAuth } from '@/hooks'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

/**
 * A CONVERSA NO DESENHO DO WHATSAPP WEB (Pedro, 29/09/2026).
 *
 * Balão com "rabinho" só na primeira mensagem de cada sequência, hora e tique
 * dentro do balão, data no meio da conversa, sem foto ao lado (conversa de
 * duas pessoas). O que é da Nay ou da automação leva o nome em cima, dentro
 * do balão, como o nome de quem fala num grupo.
 *
 * O áudio: o tocador só baixa o arquivo quando alguém aperta o play -- antes
 * cada áudio da conversa passava pela conversão do servidor ao abrir, e
 * conversa com áudio demorava para abrir. Na Parceria, a transcrição aparece
 * embaixo, como no WhatsApp ("usar api de transcrição do gpt e por a
 * transcrição embaixo do áudio igual no whatsapp").
 */
interface ActivityTimelineProps {
  activities: LeadActivityWithActor[]
  loading: boolean
  lead: LeadWithOwner
  onReply?: (activity: LeadActivityWithActor) => void
  onForward?: (activity: LeadActivityWithActor) => void
  onTogglePin?: (activity: LeadActivityWithActor) => void
  onDelete?: (activity: LeadActivityWithActor, deleteForEveryone: boolean) => void | Promise<void>
  pinnedActivityIds?: Set<string>
  /** Parceria: mostra a transcrição embaixo do áudio */
  mostrarTranscricao?: boolean
  /** há mensagens mais antigas no servidor (subir até o topo busca) */
  temMais?: boolean
  carregandoAnteriores?: boolean
  onCarregarAnteriores?: () => void
}

// ── Datas ──
const WEEKDAYS_PT = ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado']

function getDateLabel(date: Date): string {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const target = new Date(date)
  target.setHours(0, 0, 0, 0)
  const diffDays = Math.round((today.getTime() - target.getTime()) / 86400000)
  if (diffDays === 0) return 'Hoje'
  if (diffDays === 1) return 'Ontem'
  if (diffDays >= 2 && diffDays <= 6) return WEEKDAYS_PT[target.getDay()]
  return `${String(target.getDate()).padStart(2, '0')}/${String(target.getMonth() + 1).padStart(2, '0')}/${target.getFullYear()}`
}

function getDateKey(date: Date): string {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`
}

// ── Quem mandou ──
type SenderType = 'lead' | 'ai' | 'user' | 'automated' | 'system_other'

function getSenderType(activity: LeadActivityWithActor): SenderType {
  if (activity.type === 'note' || activity.type === 'call' || activity.type === 'email') return 'system_other'
  if (activity.metadata?.direction === 'inbound') return 'lead'
  if (activity.metadata?.automated) return 'automated'
  if (activity.metadata?.source === 'ai' || activity.metadata?.source === 'ai_agent' || activity.type === 'system') return 'ai'
  return 'user'
}

function isOutgoing(senderType: SenderType): boolean {
  return senderType === 'ai' || senderType === 'user' || senderType === 'automated'
}

const ROTULOS_DE_MIDIA = ['📷 Imagem', '🎥 Vídeo', '🎵 Áudio', '📄 Documento', '✨ Figurinha']

// ── A data no meio da conversa ──
function DateDivider({ label }: { label: string }) {
  return (
    <div className="flex justify-center py-2 sticky top-1 z-20">
      <span className="wa-data">{label}</span>
    </div>
  )
}

// ── O tocador de áudio ──
function tempo(t: number) {
  if (!isFinite(t) || isNaN(t) || t < 0) return '0:00'
  const m = Math.floor(t / 60)
  const s = Math.floor(t % 60)
  return `${m}:${s < 10 ? '0' : ''}${s}`
}

const VELOCIDADES = [1, 1.5, 2]

function CustomAudioPlayer({ url, isOutgoing, senderAvatar, segundos }: { url: string; isOutgoing: boolean; senderAvatar?: string; segundos?: number }) {
  const [isPlaying, setIsPlaying] = useState(false)
  const [duration, setDuration] = useState(segundos && segundos > 0 ? segundos : 0)
  const [currentTime, setCurrentTime] = useState(0)
  const [falhou, setFalhou] = useState(false)
  const [carregando, setCarregando] = useState(false)
  const [velocidade, setVelocidade] = useState(1)
  const audioRef = useRef<HTMLAudioElement>(null)

  /*
   * O ÁUDIO PASSA PELO CRM (Tel, 26/09/2026: "quando clico em reproduzir
   * audio no crm não reproduz"): a rota converte o ogg da Z-API para m4a, que
   * o Safari toca. `preload="none"`: nada baixa até o play (29/09).
   */
  const fonte = url.startsWith('/api/media/audio') ? url : `/api/media/audio?url=${encodeURIComponent(url)}`

  const togglePlay = async () => {
    const a = audioRef.current
    if (!a) return
    if (isPlaying) { a.pause(); setIsPlaying(false); return }
    try {
      setCarregando(a.readyState < 2)
      a.playbackRate = velocidade
      await a.play()
      setFalhou(false)
      setIsPlaying(true)
    } catch {
      setFalhou(true)
      setIsPlaying(false)
    } finally {
      setCarregando(false)
    }
  }

  const trocarVelocidade = () => {
    const nova = VELOCIDADES[(VELOCIDADES.indexOf(velocidade) + 1) % VELOCIDADES.length]
    setVelocidade(nova)
    if (audioRef.current) audioRef.current.playbackRate = nova
  }

  const progresso = duration > 0 ? Math.min(100, (currentTime / duration) * 100) : 0
  const cor = isOutgoing ? 'var(--wa-out-ink)' : 'var(--wa-in-ink)'

  return (
    <div className="flex items-center gap-2.5 w-[300px] max-w-full pt-1 pr-1">
      <audio
        ref={audioRef}
        src={fonte}
        preload="none"
        onTimeUpdate={() => audioRef.current && setCurrentTime(audioRef.current.currentTime)}
        onLoadedMetadata={() => audioRef.current && isFinite(audioRef.current.duration) && setDuration(audioRef.current.duration)}
        onEnded={() => { setIsPlaying(false); setCurrentTime(0) }}
        onWaiting={() => setCarregando(true)}
        onPlaying={() => setCarregando(false)}
        onError={() => { setFalhou(true); setIsPlaying(false); setCarregando(false) }}
      />

      {!isOutgoing && (
        <div className="relative flex-shrink-0">
          <div className="w-[46px] h-[46px] rounded-full overflow-hidden flex items-center justify-center" style={{ background: 'var(--wa-row-selected)' }}>
            {senderAvatar ? <img src={senderAvatar} alt="" className="w-full h-full object-cover" /> : <Microphone size={22} weight="fill" style={{ color: 'var(--wa-text-2)' }} />}
          </div>
          {senderAvatar && (
            <Microphone size={16} weight="fill" className="absolute -bottom-0.5 -right-1" style={{ color: 'var(--wa-green)' }} />
          )}
        </div>
      )}

      <button type="button" onClick={togglePlay} className="flex-shrink-0 hover:opacity-80" style={{ color: 'var(--wa-icon)' }}
              aria-label={isPlaying ? 'Pausar' : 'Tocar'}>
        {carregando ? <span className="block w-6 h-6 rounded-full border-2 border-current border-t-transparent animate-spin" />
          : isPlaying ? <Pause size={28} weight="fill" /> : <Play size={28} weight="fill" />}
      </button>

      <div className="flex-1 min-w-0">
        <div className="relative h-6 flex items-center">
          <input
            type="range"
            min={0}
            max={duration || 100}
            step={0.1}
            value={currentTime}
            onChange={(e) => {
              if (audioRef.current) {
                audioRef.current.currentTime = Number(e.target.value)
                setCurrentTime(Number(e.target.value))
              }
            }}
            className="absolute z-10 w-full h-full opacity-0 cursor-pointer"
            aria-label="Posição do áudio"
          />
          <div className="w-full h-[3px] rounded-full" style={{ background: 'var(--wa-divider)' }}>
            <div className="h-full rounded-full" style={{ width: `${progresso}%`, background: 'var(--wa-tick-read)' }} />
          </div>
          <div className="absolute w-3 h-3 rounded-full pointer-events-none"
               style={{ left: `calc(${progresso}% - 6px)`, background: 'var(--wa-tick-read)' }} />
        </div>
        <div className="flex items-center justify-between -mt-0.5">
          <span className="wa-hora">{tempo(currentTime > 0 ? currentTime : duration)}</span>
          {falhou && (
            <a href={fonte} target="_blank" rel="noreferrer" className="text-[11px] underline" style={{ color: cor }}
               title="Não consegui tocar aqui — abre o arquivo">abrir áudio</a>
          )}
        </div>
      </div>

      {isPlaying || currentTime > 0 ? (
        <button type="button" onClick={trocarVelocidade}
                className="flex-shrink-0 text-[12px] font-semibold rounded-full px-2 h-6 min-w-[36px]"
                style={{ background: 'var(--wa-quote)', color: cor }} title="Velocidade">
          {velocidade}×
        </button>
      ) : isOutgoing ? (
        <div className="relative flex-shrink-0">
          <div className="w-[46px] h-[46px] rounded-full overflow-hidden flex items-center justify-center" style={{ background: 'var(--wa-row-selected)' }}>
            {senderAvatar ? <img src={senderAvatar} alt="" className="w-full h-full object-cover" /> : <Microphone size={22} weight="fill" style={{ color: 'var(--wa-text-2)' }} />}
          </div>
        </div>
      ) : null}
    </div>
  )
}

/** A transcrição embaixo do áudio (nas três linhas desde 29/09). */
function Transcricao({ metadata, atividadeId, leadId }: { metadata: any; atividadeId?: string; leadId?: string }) {
  const [pediu, setPediu] = useState(false)
  // a tentativa voltou (deu certo ou falhou de novo): o botão volta a valer
  const tentativa = String(metadata?.transcricao_em || '')
  useEffect(() => { setPediu(false) }, [tentativa])
  // e se nada voltar em 40 s, também (a tela não fica presa em "de novo…")
  useEffect(() => {
    if (!pediu) return
    const t = setTimeout(() => setPediu(false), 40_000)
    return () => clearTimeout(t)
  }, [pediu])
  const texto = typeof metadata?.transcricao === 'string' ? metadata.transcricao : null
  const status = String(metadata?.transcricao_status || '')
  if (texto !== null) {
    if (!texto.trim()) return <p className="wa-transcricao wa-transcricao--espera">(sem fala no áudio)</p>
    return <p className="wa-transcricao">&ldquo;{texto}&rdquo;</p>
  }
  if (status === 'andando' || !status) return <p className="wa-transcricao wa-transcricao--espera">Transcrevendo…</p>
  if (status === 'sem_audio') return <p className="wa-transcricao wa-transcricao--espera">Transcrição indisponível: o arquivo do áudio já não existe.</p>
  if (status === 'falhou') {
    // 29/09: a falha de passagem (OpenAI sem crédito) é refeita sozinha a cada
    // 5 min; o botão pede na hora. O "de novo…" só vale até a tentativa voltar
    // (transcricao_em muda): sem isso ficava carregando para sempre quando a
    // tentativa falhava de novo (Pedro: "a transcrição fica carregando").
    const semCredito = /credit|429/i.test(String(metadata?.transcricao_erro || ''))
    return (
      <p className="wa-transcricao wa-transcricao--espera">
        {pediu
          ? 'Transcrevendo de novo…'
          : semCredito
            ? 'Sem transcrição: a conta da OpenAI está sem crédito. Ela sai sozinha quando o crédito voltar. '
            : 'A transcrição falhou. '}
        {!pediu && atividadeId && leadId && (
          <button type="button" className="underline font-medium not-italic"
                  onClick={() => {
                    setPediu(true)
                    fetch(`/api/leads/${leadId}/transcrever`, {
                      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ atividade: atividadeId }),
                    }).catch(() => setPediu(false))
                  }}>
            Tentar de novo
          </button>
        )}
      </p>
    )
  }
  return null
}

// ── Mídia ──
function MediaRenderer({ metadata, isOutgoing, onImageClick, senderAvatar, mostrarTranscricao, atividadeId, leadId }: {
  metadata: any; isOutgoing: boolean; onImageClick?: (url: string) => void; senderAvatar?: string; mostrarTranscricao?: boolean
  atividadeId?: string; leadId?: string
}) {
  if (!metadata?.media_url) return null
  const url = metadata.media_url
  const type = metadata.media_type

  if (type === 'audio') {
    return (
      <div>
        <CustomAudioPlayer url={url} isOutgoing={isOutgoing} senderAvatar={senderAvatar} segundos={Number(metadata.audio_seconds) || undefined} />
        {mostrarTranscricao && <Transcricao metadata={metadata} atividadeId={atividadeId} leadId={leadId} />}
      </div>
    )
  }

  if (type === 'image' || type === 'sticker') {
    const isSticker = type === 'sticker'
    return (
      <button type="button" onClick={() => onImageClick?.(url)} className={`block -mx-[3px] -mt-[3px] mb-0.5 rounded-[6px] overflow-hidden ${isSticker ? 'max-w-[140px]' : ''}`}
              title="Ampliar">
        <img
          src={url}
          alt={isSticker ? 'Figurinha' : 'Foto'}
          loading="lazy"
          decoding="async"
          className={isSticker ? 'w-full h-auto' : 'block w-[330px] max-w-full max-h-[330px] object-cover'}
          style={isSticker ? undefined : { minHeight: 120, background: 'var(--wa-quote)' }}
        />
      </button>
    )
  }

  if (type === 'video') {
    return (
      <div className="-mx-[3px] -mt-[3px] mb-0.5 rounded-[6px] overflow-hidden bg-black">
        <video controls preload="metadata" src={url} className="block w-[330px] max-w-full max-h-[330px] object-contain" />
      </div>
    )
  }

  if (type === 'document') {
    const nome = metadata.media_filename || 'Documento'
    const ext = (String(nome).split('.').pop() || metadata.media_mimetype?.split('/')[1] || 'arquivo').toUpperCase().slice(0, 5)
    // PDF abre no próprio chat, sem baixar (Pedro, 30/09) -- ver VisualizadorPdf
    if (ehPdf(nome, metadata.media_mimetype)) return <DocumentoPdf url={url} nome={nome} ext="PDF" />
    return (
      <a href={url} target="_blank" rel="noopener noreferrer" download={metadata.media_filename || undefined}
         className="flex items-center gap-3 p-2.5 rounded-[6px] w-[300px] max-w-full mb-0.5" style={{ background: 'var(--wa-quote)' }}
         title="Abrir o documento">
        <FileText size={30} weight="fill" style={{ color: ext === 'PDF' ? '#e5252a' : 'var(--wa-icon)' }} className="flex-shrink-0" />
        <span className="flex-1 min-w-0">
          <span className="block text-[14px] truncate">{nome}</span>
          <span className="block wa-hora">{ext}</span>
        </span>
        <DownloadSimple size={20} style={{ color: 'var(--wa-icon)' }} className="flex-shrink-0" />
      </a>
    )
  }

  return <a href={url} target="_blank" rel="noopener noreferrer" className="text-sm underline">Abrir arquivo ({type})</a>
}

// ── A mensagem citada (resposta) ──
function QuotedMessageBar({ metadata }: { metadata: any }) {
  const quotedText = metadata?.quoted_text
  const quotedMediaType = metadata?.quoted_media_type
  const quotedMediaUrl = metadata?.quoted_media_url
  const quotedSender = metadata?.quoted_sender
  const quotedId = metadata?.quoted_message_id
  /* A Z-API manda só o ID do que foi citado, nunca o texto; o texto vem da
     busca por esse ID nas mensagens do CRM e no banco da Nay -- o card e a
     lista do grupo, a foto do post (mensagemCitada.ts). Quando não achamos,
     a barra ainda avisa que ele respondeu citando algo. */
  /* O card inteiro não cabe em três linhas: um toque abre e fecha (09/10/2026,
     "preciso que apareça a mensagem à qual o cara está se referindo"). */
  const [aberta, setAberta] = useState(false)
  if (!quotedText && !quotedMediaType && !quotedId) return null
  const comprida = !!quotedText && (quotedText.length > 140 || quotedText.split('\n').length > 3)
  return (
    <div className="rounded-[6px] mb-1 overflow-hidden flex min-h-[42px]" style={{ background: 'var(--wa-quote)' }}>
      <div className="w-1 flex-shrink-0" style={{ background: 'var(--wa-quote-bar)' }} />
      <div className={`flex-1 px-2.5 py-1.5 min-w-0 ${comprida ? 'cursor-pointer' : ''}`}
           onClick={comprida ? () => setAberta(a => !a) : undefined}
           title={comprida ? (aberta ? 'Recolher' : 'Ver a mensagem inteira') : undefined}>
        <p className={`text-[12.5px] font-semibold ${aberta ? 'break-words' : 'truncate'}`} style={{ color: 'var(--wa-quote-bar)' }}>
          {quotedSender || 'Lead se refere a mensagem:'}
        </p>
        <p className={`text-[13px] leading-[17px] whitespace-pre-wrap break-words opacity-80 ${aberta ? '' : 'line-clamp-3'}`}>
          {quotedText || (quotedMediaType ? `[${quotedMediaType}]` : '(mensagem de fora do CRM e da Nay: não tenho o conteúdo)')}
        </p>
        {comprida && (
          <p className="text-[11.5px] mt-0.5 opacity-60">{aberta ? 'recolher' : 'ver tudo'}</p>
        )}
      </div>
      {quotedMediaUrl && (quotedMediaType === 'image' || quotedMediaType === 'video' || quotedMediaType === 'sticker') && (
        <img src={quotedMediaUrl} alt="" className="w-[52px] h-[52px] object-cover flex-shrink-0" />
      )}
    </div>
  )
}

/** Os tiques: um (saiu), dois (entregue), dois azuis (lido); aviso vermelho se falhou. */
function Tiques({ metadata }: { metadata: any }) {
  if (metadata?.send_status === 'failed' || metadata?.whatsapp_status === 'failed') {
    return (
      <span title={metadata?.send_error || 'Falha ao enviar'} className="inline-flex">
        <WarningCircle size={15} weight="fill" style={{ color: '#ef4444' }} />
      </span>
    )
  }
  const st = String(metadata?.whatsapp_status || metadata?.status || '').toLowerCase()
  if (st === 'read' || st === 'played' || st === 'lida') return <Checks size={16} weight="bold" style={{ color: 'var(--wa-tick-read)' }} />
  if (st === 'delivered' || st === 'received' || st === 'entregue') return <Checks size={16} weight="bold" />
  if (metadata?.is_optimistic) return <span className="inline-block w-3 h-3 rounded-full border border-current border-t-transparent animate-spin" />
  return <Check size={15} weight="bold" />
}

/*
 * AS DUAS BARRINHAS DE CADA MENSAGEM QUE SAIU (Pedro, 14/10/2026: "em cima de cada mensagem tenha 2 barrinhas que vão
 * enchendo, a primeira é enviando, e a segunda é entregue, e que o sistema saiba exatamente se ela foi mesmo entregue").
 *   1ª ENVIANDO: enche enquanto o CRM manda e fica verde quando a linha (Z-API ou Meta) aceita; vermelha se falhou.
 *   2ª ENTREGUE: enche quando o CELULAR DA PESSOA confirma (verde), azul quando ela leu. Sem confirmação em 10 minutos
 *      fica laranja: saiu do nosso lado e não chegou. A confirmação vem do aviso da própria linha
 *      (src/lib/entregaDaMensagem.ts), não do "id" que a Z-API devolve no envio -- esse só diz que ela aceitou o pedido.
 * Mensagem de antes do acompanhamento (14/10) não tem como saber: a 2ª fica vazia (o "título" explica).
 * 14/10, logo depois: "só 2 grandes" -- duas barras iguais, sem tracejado.
 */
const INICIO_DO_ACOMPANHAMENTO = Date.parse('2026-10-14T14:30:00Z')
const DEZ_MINUTOS = 10 * 60 * 1000

function BarrasDeEntrega({ metadata, criadaEm }: { metadata: any; criadaEm: string }) {
  const st = String(metadata?.whatsapp_status || '').toLowerCase()
  const otimista = !!metadata?.is_optimistic
  const falhou = metadata?.send_status === 'failed' || st === 'failed'
  const lida = st === 'read'
  const entregue = lida || st === 'delivered'
  const saiu = !otimista && !falhou && (entregue || st === 'sent' || metadata?.send_status === 'sent'
    || !!metadata?.zapi_message_id || !!metadata?.whatsapp_message_id)
  const criada = Date.parse(criadaEm)
  const antes = Number.isFinite(criada) && criada < INICIO_DO_ACOMPANHAMENTO
  const atrasada = saiu && !entregue && !antes && Date.now() - criada > DEZ_MINUTOS
  const hora = (iso?: string) => (iso ? formatTime(iso) : '')
  // Pedro, 25/10: "naqueles 2 tracinhos pode ter uma cor diferente quando for humano, tipo rosa". Humano = mandada
  // pelo CRM (source human) ou pelo celular (do_celular, a Z-API diz que não saiu pela API).
  const humano = metadata?.source === 'human' || !!metadata?.do_celular
  const verde = humano ? '#ec4899' : 'var(--wa-green, #22c55e)'

  const titulo = (humano ? 'Mandada por uma pessoa da equipe. ' : '') + (falhou ? `Não foi enviada: ${metadata?.send_error || 'a linha recusou'}`
    : otimista ? 'Enviando…'
    : lida ? `Entregue${metadata?.whatsapp_entregue_em ? ` às ${hora(metadata.whatsapp_entregue_em)}` : ''} e lida${metadata?.whatsapp_lida_em ? ` às ${hora(metadata.whatsapp_lida_em)}` : ''}`
    : entregue ? `Entregue no celular da pessoa${metadata?.whatsapp_entregue_em ? ` às ${hora(metadata.whatsapp_entregue_em)}` : ''}`
    : antes ? 'Enviada. Mensagem de antes de 14/10: o CRM não acompanhava a entrega'
    : atrasada ? 'Enviada, mas o celular da pessoa ainda NÃO confirmou o recebimento'
    : 'Enviada; esperando o celular da pessoa confirmar')

  const barra = (cheia: number, cor: string, extra = '') => (
    <span className={`relative block h-[4px] flex-1 rounded-full overflow-hidden ${extra}`} style={{ background: 'rgba(127,127,127,.28)' }}>
      <span className="absolute inset-y-0 left-0 rounded-full transition-all duration-700 ease-out" style={{ width: `${cheia}%`, background: cor }} />
    </span>
  )
  return (
    <span className="flex items-center gap-1 w-[84px] mb-1" title={titulo} aria-label={titulo}>
      {barra(falhou || saiu ? 100 : 55, falhou ? '#ef4444' : saiu ? verde : humano ? '#f9a8d4' : 'var(--wa-text-2, #8696a0)', otimista ? 'animate-pulse' : '')}
      {barra(entregue || atrasada ? 100 : 0, lida ? 'var(--wa-tick-read, #53bdeb)' : entregue ? verde : '#f59e0b')}
    </span>
  )
}

// ── O balão ──
const MessageBubble = memo(function MessageBubble({
  activity,
  senderType,
  showHeader,
  nomeDoLead,
  reactions,
  onImageClick,
  onReply,
  onForward,
  onTogglePin,
  onRequestDelete,
  canDelete,
  isPinned,
  onToggleSelect,
  isSelected,
  mostrarTranscricao,
}: {
  activity: LeadActivityWithActor
  senderType: SenderType | 'system_other'
  showHeader: boolean
  nomeDoLead: string
  reactions?: LeadActivityWithActor[]
  onImageClick?: (url: string) => void
  onReply?: (activity: LeadActivityWithActor) => void
  onForward?: (activity: LeadActivityWithActor) => void
  onTogglePin?: (activity: LeadActivityWithActor) => void
  onRequestDelete?: (activity: LeadActivityWithActor) => void
  canDelete?: boolean
  isPinned?: boolean
  onToggleSelect?: (activity: LeadActivityWithActor) => void
  isSelected?: boolean
  mostrarTranscricao?: boolean
}) {
  if (senderType === 'system_other') return null

  const outgoing = isOutgoing(senderType)
  const m = activity.metadata || {}
  const isDeleted = !!m.deleted
  const isAI = senderType === 'ai'
  const isAutomated = senderType === 'automated'
  const temMidia = !!m.media_url
  // o cartão de contato da Leads já mostra o nome: o "👤 Contato compartilhado: ..." não se repete embaixo
  const cartaoDeContato = !!m.contato_compartilhado && m.channel === 'whatsapp_zapi_captacao'
  const mostraTexto = !!activity.content && !cartaoDeContato && (!temMidia || !ROTULOS_DE_MIDIA.includes(activity.content))
  const ehGrupo = m.is_group === true

  // o nome em cima, dentro do balão: da Nay/automação, ou de quem fala no grupo
  const rotulo = outgoing
    ? (showHeader && (isAI || isAutomated) ? (isAI ? 'Nay (IA)' : 'Automático') : null)
    : (showHeader && ehGrupo ? (m.sender_name || nomeDoLead) : null)
  const corDoRotulo = isAI ? '#7c6bff' : isAutomated ? 'var(--wa-green)' : 'var(--wa-quote-bar)'

  const acoes = !isDeleted && (onTogglePin || onReply || onForward || (outgoing && onRequestDelete && canDelete)) && (
    <div className={`absolute top-1/2 -translate-y-1/2 flex items-center gap-1 z-20 transition-opacity
                     ${outgoing ? 'right-full pr-2' : 'left-full pl-2'} ${isSelected ? 'opacity-100' : 'opacity-0 group-hover/msg:opacity-100'}`}>
      {outgoing && onToggleSelect && canDelete && (
        <button onClick={() => onToggleSelect(activity)} title={isSelected ? 'Remover da seleção' : 'Selecionar mensagem'}
                className="w-7 h-7 rounded-full shadow flex items-center justify-center"
                style={{ background: isSelected ? 'var(--wa-green)' : 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}>
          {isSelected && <Check size={14} weight="bold" className="text-white" />}
        </button>
      )}
      {outgoing && onRequestDelete && canDelete && (
        <button onClick={() => onRequestDelete(activity)} title="Apagar mensagem"
                className="w-7 h-7 rounded-full shadow flex items-center justify-center hover:text-red-500"
                style={{ background: 'var(--wa-menu)', color: 'var(--wa-icon)' }}>
          <Trash size={14} weight="bold" />
        </button>
      )}
      {onTogglePin && (
        <button onClick={() => onTogglePin(activity)} title={isPinned ? 'Desafixar mensagem' : 'Fixar mensagem'}
                className="w-7 h-7 rounded-full shadow flex items-center justify-center" style={{ background: 'var(--wa-menu)', color: isPinned ? 'var(--wa-green)' : 'var(--wa-icon)' }}>
          <PushPin size={14} weight={isPinned ? 'fill' : 'bold'} className={isPinned ? '-rotate-45' : ''} />
        </button>
      )}
      {onReply && (
        <button onClick={() => onReply(activity)} title="Responder"
                className="w-7 h-7 rounded-full shadow flex items-center justify-center" style={{ background: 'var(--wa-menu)', color: 'var(--wa-icon)' }}>
          <ArrowBendUpLeft size={14} weight="bold" />
        </button>
      )}
      {onForward && (
        <button onClick={() => onForward(activity)} title="Encaminhar"
                className="w-7 h-7 rounded-full shadow flex items-center justify-center" style={{ background: 'var(--wa-menu)', color: 'var(--wa-icon)' }}>
          <ArrowBendUpRight size={14} weight="bold" />
        </button>
      )}
    </div>
  )

  const reacoes = reactions && reactions.length > 0 && (
    <div className={`absolute -bottom-3 ${outgoing ? 'right-2' : 'left-2'} rounded-full px-1.5 py-0.5 flex items-center gap-0.5 z-10 shadow`}
         style={{ background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}
         title={reactions.map((r) => `${r.metadata?.direction === 'outbound' ? 'Você' : (r.metadata?.sender_name || nomeDoLead)}: ${r.content}`).join('\n')}>
      {Array.from(new Set(reactions.map((r) => r.content))).map((emoji, idx) => <span key={idx} className="text-[13px] leading-none">{emoji}</span>)}
      {reactions.length > 1 && <span className="text-[11px] ml-0.5" style={{ color: 'var(--wa-text-2)' }}>{reactions.length}</span>}
    </div>
  )

  return (
    <div className={`flex ${outgoing ? 'justify-end' : 'justify-start'} ${outgoing ? 'pl-[10%]' : 'pr-[10%]'} ${reacoes ? 'mb-4' : ''}`}>
      <div className="relative group/msg max-w-[min(65%,680px)] min-w-0">
        {acoes}
        {isDeleted ? (
          <div className={`wa-balao ${outgoing ? 'wa-balao--out' : 'wa-balao--in'} ${showHeader ? 'wa-balao--rabo' : ''}`}>
            <p className="italic flex items-center gap-1.5 opacity-70">
              <Prohibit size={14} weight="bold" /> Mensagem apagada
              <span className="inline-block w-[3.2rem]" />
            </p>
            <span className="absolute bottom-[3px] right-[7px] wa-hora">{formatTime(activity.created_at)}</span>
          </div>
        ) : (
          <div className={`wa-balao ${outgoing ? 'wa-balao--out' : 'wa-balao--in'} ${showHeader ? 'wa-balao--rabo' : ''}`}>
            {outgoing && activity.type === 'whatsapp' && <BarrasDeEntrega metadata={m} criadaEm={activity.created_at} />}
            {rotulo && (
              <p className="text-[12.8px] font-semibold leading-[18px] mb-0.5 flex items-center gap-1" style={{ color: corDoRotulo }}>
                {isAI && <Sparkle size={12} weight="fill" />}
                {isAutomated && <Lightning size={12} weight="fill" />}
                {rotulo}
              </p>
            )}
            <QuotedMessageBar metadata={m} />
            {/* O IMÓVEL DA MENSAGEM MARCADA (Tel, 27/09): antes de ler "ainda
                está disponível?" a pessoa precisa saber DE QUAL imóvel. */}
            <ImovelCitado quotedText={m.quoted_text} quotedMessageId={m.quoted_message_id} ownText={activity.content} isOutgoing={outgoing} />
            {/* POR QUAL NÚMERO SAIU (Tel, 26/09): template da API Oficial numa conversa da Parceria */}
            {m.channel === 'whatsapp_cloud_official' && outgoing && (
              <span className="block mb-0.5 text-[11px] opacity-70">API Oficial{m.template ? ` · ${m.template}` : ''}</span>
            )}
            {temMidia && (
              <MediaRenderer
                metadata={m}
                isOutgoing={outgoing}
                onImageClick={onImageClick}
                senderAvatar={outgoing ? (isAI ? undefined : activity.actor?.profiles?.avatar_url) : undefined}
                mostrarTranscricao={mostrarTranscricao}
                atividadeId={activity.id}
                leadId={activity.lead_id}
              />
            )}
            {/* CARTÃO DE CONTATO no WhatsApp Leads (Pedro, 30/10): o contato e o botão Criar contato */}
            {cartaoDeContato && (
              <ContatoCompartilhado contato={m.contato_compartilhado} />
            )}
            {mostraTexto && (
              <p className="whitespace-pre-wrap break-words">
                <TextoComLinks texto={activity.content} />
                {/* espaço para a hora e o tique não subirem por cima do texto */}
                <span className={`inline-block ${outgoing ? 'w-[4.1rem]' : 'w-[3.1rem]'} ${m.editada ? (outgoing ? '!w-[7.4rem]' : '!w-[6.4rem]') : ''}`} />
              </p>
            )}
            <span className={`${mostraTexto || !temMidia ? 'absolute bottom-[3px] right-[7px]' : 'flex justify-end -mb-1'} wa-hora items-center gap-[3px] inline-flex`}>
              {m.editada && <span className="mr-0.5">Editada</span>}
              {formatTime(activity.created_at)}
              {outgoing && <Tiques metadata={m} />}
            </span>
          </div>
        )}
        {reacoes}
      </div>
    </div>
  )
})

/*
 * O ÁLBUM (Pedro, 29/09/2026): "no WhatsApp fica 4 miniaturas e um número de
 * fotos que tem, 26+ por exemplo, ele junta as fotos". Quatro ou mais fotos
 * seguidas da mesma pessoa, a menos de 2 min uma da outra e sem legenda, viram
 * um balão só: 4 miniaturas, e a quarta com "+N" quando há mais. Tocar abre a
 * galeria com todas.
 */
function fotoAgrupavel(a: LeadActivityWithActor): boolean {
  const m = a.metadata || {}
  if (a.type !== 'whatsapp' || m.media_type !== 'image' || !m.media_url || m.deleted || m.is_reaction) return false
  const c = String(a.content || '').trim()
  if (c === '[Figurinha]' || c === '✨ Figurinha') return false
  return !c || ROTULOS_DE_MIDIA.includes(c) || c === '[Imagem]'
}

const AlbumDeFotos = memo(function AlbumDeFotos({ fotos, outgoing, showHeader, rotulo, aoAbrir }: {
  fotos: LeadActivityWithActor[]
  outgoing: boolean
  showHeader: boolean
  rotulo: string | null
  aoAbrir: (indice: number) => void
}) {
  const ultima = fotos[fotos.length - 1]
  const resto = fotos.length - 3  // como no WhatsApp: a 4ª fica coberta pelo número
  return (
    <div className={`flex ${outgoing ? 'justify-end' : 'justify-start'} ${outgoing ? 'pl-[10%]' : 'pr-[10%]'}`}>
      <div className={`wa-balao ${outgoing ? 'wa-balao--out' : 'wa-balao--in'} ${showHeader ? 'wa-balao--rabo' : ''} !p-[3px]`}>
        {outgoing && <span className="block px-1.5 pt-1"><BarrasDeEntrega metadata={ultima.metadata || {}} criadaEm={ultima.created_at} /></span>}
        {rotulo && <p className="text-[12.8px] font-semibold leading-[18px] px-1.5 pt-0.5 pb-1" style={{ color: 'var(--wa-quote-bar)' }}>{rotulo}</p>}
        <div className="grid grid-cols-2 gap-[3px] w-[min(300px,62vw)]">
          {fotos.slice(0, 4).map((f, i) => (
            <button key={f.id} type="button" onClick={() => aoAbrir(i)} className="relative aspect-square overflow-hidden rounded-md bg-black/10"
                    aria-label={i === 3 && fotos.length > 4 ? `Ver as ${fotos.length} fotos` : `Abrir a foto ${i + 1}`}>
              <img src={f.metadata?.media_url} alt="" loading="lazy" decoding="async" className="w-full h-full object-cover" />
              {i === 3 && fotos.length > 4 && (
                <span className="absolute inset-0 flex items-center justify-center bg-black/55 text-white text-[28px] font-semibold">+{resto}</span>
              )}
            </button>
          ))}
        </div>
        <span className="flex justify-end items-center gap-[3px] wa-hora px-1.5 pt-0.5">
          {fotos.length} fotos · {formatTime(ultima.created_at)}
          {outgoing && <Tiques metadata={ultima.metadata || {}} />}
        </span>
      </div>
    </div>
  )
})

// ── A conversa ──
export default function ActivityTimeline({
  activities,
  loading,
  lead,
  onReply,
  onForward,
  onTogglePin,
  onDelete,
  pinnedActivityIds,
  mostrarTranscricao,
  temMais,
  carregandoAnteriores,
  onCarregarAnteriores,
}: ActivityTimelineProps) {
  // a galeria: uma foto (clique numa imagem) ou o álbum inteiro
  const [galeria, setGaleria] = useState<{ urls: string[]; i: number } | null>(null)
  const setSelectedImage = useCallback((url: string) => setGaleria({ urls: [url], i: 0 }), [])
  useEffect(() => {
    if (!galeria) return
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setGaleria(null)
      if (e.key === 'ArrowRight') setGaleria((g) => g && { ...g, i: Math.min(g.urls.length - 1, g.i + 1) })
      if (e.key === 'ArrowLeft') setGaleria((g) => g && { ...g, i: Math.max(0, g.i - 1) })
    }
    window.addEventListener('keydown', tecla)
    return () => window.removeEventListener('keydown', tecla)
  }, [galeria])

  /* O BOTÃO DE DESCER (Pedro, 29/09): subiu para ler, aparece a setinha no
     canto de baixo, com quantas mensagens chegaram desde então. */
  const [longeDoFim, setLongeDoFim] = useState(false)
  const quantasAoSubir = useRef(0)
  const [deleteTarget, setDeleteTarget] = useState<LeadActivityWithActor | null>(null)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [bulkDeleteOpen, setBulkDeleteOpen] = useState(false)
  const [bulkDeleting, setBulkDeleting] = useState(false)
  const rolagemRef = useRef<HTMLDivElement>(null)
  const jaRolou = useRef(false)
  const { currentOrganization, isMaster, roleName } = useAuth()
  const isOrgAdminUser = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner'
  const nomeDoLead = lead.title || 'Lead'

  // Só quem enviou (ou um admin) apaga; mensagem otimista (sem id real) não.
  const canDeleteActivity = (activity: LeadActivityWithActor) => {
    if (activity.metadata?.is_optimistic || activity.metadata?.direction !== 'outbound') return false
    if (isOrgAdminUser) return true
    return activity.metadata?.source === 'human' && !!currentOrganization?.id && activity.actor_member_id === currentOrganization.id
  }

  const toggleSelect = (activity: LeadActivityWithActor) => {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(activity.id)) next.delete(activity.id)
      else next.add(activity.id)
      return next
    })
  }
  const clearSelection = () => setSelectedIds(new Set())

  const selectableActivityIds = activities
    .filter((a) => a.type !== 'note' && a.type !== 'call' && a.type !== 'email' && canDeleteActivity(a))
    .map((a) => a.id)
  const selectAllEligible = () => setSelectedIds(new Set(selectableActivityIds))

  useEffect(() => { clearSelection(); jaRolou.current = false }, [lead.id])

  /* Abrir a conversa já no fim, sem animação (a rolagem "suave" começava do
     topo e atravessava a conversa inteira). Mensagem nova rola suave, e só se
     a pessoa já estava perto do fim -- quem subiu para ler não é puxado. */
  /* As de antes entram EM CIMA: a tela fica parada na mensagem que a pessoa
     estava lendo (senão o conteúdo novo empurraria tudo para baixo). */
  const antesDeCarregar = useRef<{ altura: number; topo: number; primeira: string } | null>(null)
  const primeiraId = activities[0]?.id
  useLayoutEffect(() => {
    const el = rolagemRef.current
    if (!el || activities.length === 0) return
    if (!jaRolou.current) {
      el.scrollTop = el.scrollHeight
      jaRolou.current = true
      return
    }
    const antes = antesDeCarregar.current
    if (antes && antes.primeira !== primeiraId) {
      el.scrollTop = antes.topo + (el.scrollHeight - antes.altura)
      antesDeCarregar.current = null
      return
    }
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 240) el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' })
  }, [activities.length, primeiraId])

  const aoRolar = () => {
    const perto = rolagemRef.current ? rolagemRef.current.scrollHeight - rolagemRef.current.scrollTop - rolagemRef.current.clientHeight < 300 : true
    if (!perto && !longeDoFim) quantasAoSubir.current = activities.length
    if (perto !== !longeDoFim) setLongeDoFim(!perto)
    const el = rolagemRef.current
    if (!el || !temMais || carregandoAnteriores || !onCarregarAnteriores || !jaRolou.current) return
    if (el.scrollTop > 300) return
    antesDeCarregar.current = { altura: el.scrollHeight, topo: el.scrollTop, primeira: primeiraId || '' }
    onCarregarAnteriores()
  }

  const elements = useMemo(() => {
    if (activities.length === 0) return []

    const normalActivities: LeadActivityWithActor[] = []
    // reação: por mensagem reagida, e de cada pessoa só a última (trocar o
    // emoji substitui; reação vazia é "tirou") -- como no WhatsApp
    const porAlvo = new Map<string, Map<string, LeadActivityWithActor>>()
    activities.forEach((act) => {
      if (act.type === 'system' && act.metadata?.source === 'rename') return
      if (act.metadata?.is_reaction && act.metadata?.target_message_id) {
        const targetId = String(act.metadata.target_message_id)
        const quem = act.metadata?.direction === 'outbound' ? 'nos' : String(act.metadata?.participant_phone || act.metadata?.sender_name || 'contato')
        if (!porAlvo.has(targetId)) porAlvo.set(targetId, new Map())
        porAlvo.get(targetId)!.set(quem, act)
      } else {
        normalActivities.push(act)
      }
    })
    const reactionMap = new Map<string, LeadActivityWithActor[]>()
    porAlvo.forEach((deCadaUm, alvo) => {
      const valendo = Array.from(deCadaUm.values()).filter((r) => !!r.content)
      if (valendo.length) reactionMap.set(alvo, valendo)
    })

    const out: React.ReactNode[] = []
    let lastDateKey = ''
    let lastSenderType = ''
    let lastSenderName = ''

    const divisor = (dateKey: string, date: Date, i: number) => {
      if (dateKey !== lastDateKey) {
        out.push(<DateDivider key={`date-${dateKey}-${i}`} label={getDateLabel(date)} />)
        lastDateKey = dateKey
        lastSenderType = ''
        lastSenderName = ''
      }
    }

    for (let i = 0; i < normalActivities.length; i++) {
      const activity = normalActivities[i]
      const senderType = getSenderType(activity)
      const date = new Date(activity.created_at)
      const dateKey = getDateKey(date)

      if (activity.type === 'note') {
        divisor(dateKey, date, i)
        out.push(
          <div key={activity.id} className="mt-3 flex justify-center">
            <div className="rounded-lg px-3 py-2 max-w-md w-full shadow-sm" style={{ background: '#fff5c4', color: '#3b3200' }}>
              <p className="text-[13px] font-semibold">📝 Nota interna</p>
              <p className="text-[14px] mt-1 whitespace-pre-wrap"><TextoComLinks texto={activity.content} /></p>
              <p className="text-[11px] mt-1.5 text-right opacity-70">
                {activity.actor?.profiles?.full_name || activity.metadata?.de || 'Desconhecido'} · {formatTime(activity.created_at)}
              </p>
            </div>
          </div>
        )
        lastSenderType = 'system_other'
        lastSenderName = ''
        continue
      }

      if (activity.type === 'call' || activity.type === 'email') {
        divisor(dateKey, date, i)
        const durationSecs = activity.metadata?.duration_seconds
        const texto = activity.type === 'call'
          ? `📞 Ligação${durationSecs ? ` · ${Math.floor(durationSecs / 60)}min ${durationSecs % 60}s` : ''}`
          : `📧 E-mail: ${activity.content}`
        out.push(
          <div key={activity.id} className="mt-3 flex justify-center">
            <span className="wa-data !whitespace-pre-wrap max-w-md text-center">{texto} · {formatTime(activity.created_at)}</span>
          </div>
        )
        lastSenderType = 'system_other'
        lastSenderName = ''
        continue
      }

      divisor(dateKey, date, i)

      // sequência: a mesma pessoa falando seguido não repete o "rabinho"
      const currentSenderName = activity.metadata?.sender_name || ''
      const isGroupMsg = activity.metadata?.is_group === true
      const senderChanged = senderType !== lastSenderType || (isGroupMsg && senderType === 'lead' && currentSenderName !== lastSenderName)
      const showHeader = senderChanged
      const needsGap = showHeader && lastSenderType !== '' && lastSenderType !== 'system_other'
      lastSenderType = senderType as string
      lastSenderName = currentSenderName

      // o álbum: 4+ fotos seguidas da mesma pessoa, a menos de 2 min uma da outra
      if (fotoAgrupavel(activity)) {
        const fotos = [activity]
        let j = i + 1
        while (j < normalActivities.length && fotoAgrupavel(normalActivities[j])
               && getSenderType(normalActivities[j]) === senderType
               && getDateKey(new Date(normalActivities[j].created_at)) === dateKey
               && new Date(normalActivities[j].created_at).getTime() - new Date(normalActivities[j - 1].created_at).getTime() <= 120_000) {
          fotos.push(normalActivities[j])
          j++
        }
        if (fotos.length >= 4) {
          const outgoingAlbum = isOutgoing(senderType as SenderType)
          const rotuloAlbum = outgoingAlbum
            ? (showHeader && (senderType === 'ai' || senderType === 'automated') ? (senderType === 'ai' ? 'Nay (IA)' : 'Automático') : null)
            : (showHeader && isGroupMsg ? (currentSenderName || nomeDoLead) : null)
          const urls = fotos.map((f) => String(f.metadata?.media_url))
          out.push(
            <div key={`album-${activity.id}`} id={`activity-${activity.id}`} className={needsGap ? 'mt-3' : 'mt-[2px]'}>
              <AlbumDeFotos fotos={fotos} outgoing={outgoingAlbum} showHeader={showHeader} rotulo={rotuloAlbum}
                            aoAbrir={(indice) => setGaleria({ urls, i: indice })} />
            </div>
          )
          i = j - 1
          continue
        }
      }

      const idDaMensagem = activity.metadata?.message_id || activity.metadata?.zapi_message_id || activity.metadata?.whatsapp_message_id
      const reactionsForThisMessage = idDaMensagem ? reactionMap.get(String(idDaMensagem)) : undefined

      out.push(
        <div key={activity.id} id={`activity-${activity.id}`} className={needsGap ? 'mt-3' : 'mt-[2px]'}>
          <MessageBubble
            activity={activity}
            senderType={senderType as SenderType}
            showHeader={showHeader}
            nomeDoLead={nomeDoLead}
            reactions={reactionsForThisMessage}
            onImageClick={setSelectedImage}
            onReply={onReply}
            onForward={onForward}
            onTogglePin={onTogglePin}
            onRequestDelete={onDelete ? setDeleteTarget : undefined}
            canDelete={canDeleteActivity(activity)}
            isPinned={pinnedActivityIds?.has(activity.id)}
            onToggleSelect={onDelete ? toggleSelect : undefined}
            isSelected={selectedIds.has(activity.id)}
            mostrarTranscricao={mostrarTranscricao}
          />
        </div>
      )
    }

    return out
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activities, nomeDoLead, pinnedActivityIds, selectedIds, onReply, onForward, onTogglePin, onDelete, isOrgAdminUser, currentOrganization?.id, mostrarTranscricao])

  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center relative z-10">
        <LoadingSpinner text="Carregando mensagens..." />
      </div>
    )
  }

  if (activities.length === 0) {
    /* Conversa importada do WhatsApp: ela existe no aparelho, com histórico,
       mas a Z-API não entrega mensagem antiga -- só as que chegam depois. */
    const importada = (lead.custom_attributes as Record<string, unknown> | undefined)?.origem === 'conversa_whatsapp'
    const ultimaNoWhatsapp = lead.last_activity_at
      ? new Date(lead.last_activity_at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
      : null
    return (
      <div className="flex-1 flex items-center justify-center relative z-10 px-6">
        <div className="wa-data !px-5 !py-3 max-w-sm text-center !whitespace-normal">
          {importada ? (
            <>
              <p className="font-semibold" style={{ color: 'var(--wa-text)' }}>O histórico desta conversa está no celular</p>
              <p className="mt-1">Ela já existia no WhatsApp antes do CRM, e a Z-API não traz mensagens antigas. A partir da próxima mensagem — sua ou dele — tudo aparece aqui.</p>
              {ultimaNoWhatsapp && <p className="mt-1.5 opacity-80">Última mensagem no WhatsApp: {ultimaNoWhatsapp}</p>}
            </>
          ) : 'Nenhuma mensagem ainda. Inicie a conversa!'}
        </div>
      </div>
    )
  }

  const novasDesdeQueSubiu = longeDoFim ? Math.max(0, activities.length - quantasAoSubir.current) : 0
  return (
    <>
      <div className="relative flex-1 min-h-0 flex flex-col z-10">
      {longeDoFim && (
        <button type="button" className="wa-descer" title="Ir para a mensagem mais recente" aria-label="Ir para a mensagem mais recente"
                onClick={() => { const el = rolagemRef.current; if (el) el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' }) }}>
          {novasDesdeQueSubiu > 0 && <span className="wa-descer__n">{novasDesdeQueSubiu > 99 ? '99+' : novasDesdeQueSubiu}</span>}
          <CaretDown size={22} weight="bold" />
        </button>
      )}
      <div ref={rolagemRef} onScroll={aoRolar} className="flex-1 overflow-y-auto overflow-x-hidden relative wa-rolagem wa-zoom" style={{ padding: '8px clamp(12px, 6%, 64px) 12px' }}>
        <div className="flex flex-col min-h-full justify-end">
          {temMais && (
            <div className="flex justify-center py-2">
              {carregandoAnteriores ? (
                <span className="wa-data inline-flex items-center gap-2">
                  <span className="inline-block w-3.5 h-3.5 rounded-full border-2 border-current border-t-transparent animate-spin" />
                  Carregando mensagens anteriores…
                </span>
              ) : (
                <button type="button" className="wa-data hover:brightness-95" onClick={() => {
                  const el = rolagemRef.current
                  if (el) antesDeCarregar.current = { altura: el.scrollHeight, topo: el.scrollTop, primeira: primeiraId || '' }
                  onCarregarAnteriores?.()
                }}>
                  Ver mensagens anteriores
                </button>
              )}
            </div>
          )}
          {elements}
        </div>
      </div>
      </div>

      {selectedIds.size > 0 && (
        <div className="flex items-center justify-between gap-3 px-4 py-2.5 relative z-10" style={{ background: 'var(--wa-panel)', borderTop: '1px solid var(--wa-divider)' }}>
          <div className="flex items-center gap-2">
            <button onClick={clearSelection} className="wa-icone-btn !w-8 !h-8" title="Cancelar seleção"><X size={16} weight="bold" /></button>
            <span className="text-[14px]" style={{ color: 'var(--wa-text)' }}>
              {selectedIds.size} {selectedIds.size === 1 ? 'selecionada' : 'selecionadas'}
            </span>
          </div>
          <div className="flex items-center gap-2">
            {selectedIds.size < selectableActivityIds.length && (
              <button onClick={selectAllEligible} className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] hover:bg-[var(--wa-row-hover)]" style={{ color: 'var(--wa-text-2)' }}>
                <Checks size={14} weight="bold" /> Selecionar todas
              </button>
            )}
            <button onClick={() => setBulkDeleteOpen(true)} disabled={bulkDeleting}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-500/10 hover:bg-red-500/20 border border-red-500/30 text-red-500 text-[13px] disabled:opacity-50">
              <Trash size={14} weight="bold" /> {bulkDeleting ? 'Apagando…' : 'Apagar selecionadas'}
            </button>
          </div>
        </div>
      )}

      {galeria && (
        <div className="fixed inset-0 z-[999] flex flex-col items-center justify-center bg-black/90 backdrop-blur-md p-4" onClick={() => setGaleria(null)}>
          {/* o X em alto contraste (Pedro, 29/09): branco com o X preto, no canto de cima à direita */}
          <button type="button" aria-label="Fechar" title="Fechar (Esc)"
                  // a cor vai no style: o tema escuro troca o bg-white por escuro (globals.css)
                  className="wa-fechar-foto fixed top-4 right-4 z-[1000] w-12 h-12 rounded-full flex items-center justify-center"
                  onClick={(e) => { e.stopPropagation(); setGaleria(null) }}>
            <X size={26} weight="bold" />
          </button>
          {galeria.urls.length > 1 && (
            <span className="absolute top-7 left-1/2 -translate-x-1/2 text-white/85 text-[14px] font-medium">{galeria.i + 1} / {galeria.urls.length}</span>
          )}
          <img src={galeria.urls[galeria.i]} alt="Foto" className="max-w-[92vw] max-h-[78vh] object-contain rounded-md shadow-2xl" onClick={(e) => e.stopPropagation()} />
          {galeria.urls.length > 1 && (
            <>
              <button type="button" disabled={galeria.i === 0} onClick={(e) => { e.stopPropagation(); setGaleria((g) => g && { ...g, i: Math.max(0, g.i - 1) }) }}
                      className="absolute left-4 top-1/2 -translate-y-1/2 w-12 h-12 rounded-full bg-black/50 hover:bg-black/80 text-white flex items-center justify-center disabled:opacity-25" aria-label="Foto anterior">
                <CaretLeft size={24} weight="bold" />
              </button>
              <button type="button" disabled={galeria.i === galeria.urls.length - 1} onClick={(e) => { e.stopPropagation(); setGaleria((g) => g && { ...g, i: Math.min(g.urls.length - 1, g.i + 1) }) }}
                      className="absolute right-4 top-1/2 -translate-y-1/2 w-12 h-12 rounded-full bg-black/50 hover:bg-black/80 text-white flex items-center justify-center disabled:opacity-25" aria-label="Próxima foto">
                <CaretRight size={24} weight="bold" />
              </button>
              <div className="mt-3 flex gap-1.5 overflow-x-auto max-w-[92vw] pb-1" onClick={(e) => e.stopPropagation()}>
                {galeria.urls.map((u, k) => (
                  <button key={k} type="button" onClick={() => setGaleria((g) => g && { ...g, i: k })}
                          className={`w-14 h-14 flex-shrink-0 rounded-md overflow-hidden ${k === galeria.i ? 'ring-2 ring-white' : 'opacity-60 hover:opacity-100'}`}>
                    <img src={u} alt="" loading="lazy" className="w-full h-full object-cover" />
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
      )}

      {deleteTarget && (() => {
        // "Para todos" só é real na Evolution; a API Oficial e o Instagram não deixam apagar.
        const supportsEveryone = deleteTarget.metadata?.channel === 'whatsapp_evolution'
        const close = () => setDeleteTarget(null)
        const choose = (deleteForEveryone: boolean) => { onDelete?.(deleteTarget, deleteForEveryone); close() }
        return (
          <div className="fixed inset-0 z-[999] flex items-center justify-center bg-black/60 p-4" onClick={close}>
            <div className="w-full max-w-sm rounded-2xl shadow-2xl p-5" style={{ background: 'var(--wa-menu)', color: 'var(--wa-text)' }} onClick={(e) => e.stopPropagation()}>
              <h3 className="text-[15px] font-semibold mb-1" style={{ fontFamily: 'inherit' }}>Apagar mensagem</h3>
              <p className="text-[13px] mb-4" style={{ color: 'var(--wa-text-2)' }}>
                {supportsEveryone
                  ? 'Escolha se ela também deve sumir do WhatsApp do cliente ou só daqui do CRM.'
                  : 'O WhatsApp não deixa apagar por aqui mensagem que já saiu — ela continua no celular do cliente. Sai só daqui do CRM.'}
              </p>
              <div className="flex flex-col gap-2">
                {supportsEveryone && (
                  <button onClick={() => choose(true)} className="w-full text-left px-3 py-2.5 rounded-lg bg-red-500/10 hover:bg-red-500/20 border border-red-500/30">
                    <span className="block text-[14px] font-medium text-red-500">Apagar para todos</span>
                  </button>
                )}
                <button onClick={() => choose(false)} className="w-full text-left px-3 py-2.5 rounded-lg hover:bg-[var(--wa-row-hover)]" style={{ border: '1px solid var(--wa-divider)' }}>
                  <span className="block text-[14px] font-medium">Apagar apenas para mim</span>
                  <span className="block text-[12px] mt-0.5" style={{ color: 'var(--wa-text-2)' }}>Some só daqui do CRM.</span>
                </button>
                <button onClick={close} className="w-full text-center px-3 py-2 rounded-lg text-[14px]" style={{ color: 'var(--wa-green)' }}>Cancelar</button>
              </div>
            </div>
          </div>
        )
      })()}

      {bulkDeleteOpen && (() => {
        const targets = activities.filter((a) => selectedIds.has(a.id))
        const supportsEveryone = targets.length > 0 && targets.every((a) => a.metadata?.channel === 'whatsapp_evolution')
        const close = () => setBulkDeleteOpen(false)
        const choose = async (deleteForEveryone: boolean) => {
          close()
          setBulkDeleting(true)
          for (const act of targets) await onDelete?.(act, deleteForEveryone)
          setBulkDeleting(false)
          clearSelection()
        }
        return (
          <div className="fixed inset-0 z-[999] flex items-center justify-center bg-black/60 p-4" onClick={close}>
            <div className="w-full max-w-sm rounded-2xl shadow-2xl p-5" style={{ background: 'var(--wa-menu)', color: 'var(--wa-text)' }} onClick={(e) => e.stopPropagation()}>
              <h3 className="text-[15px] font-semibold mb-1" style={{ fontFamily: 'inherit' }}>
                Apagar {targets.length} {targets.length === 1 ? 'mensagem' : 'mensagens'}
              </h3>
              <p className="text-[13px] mb-4" style={{ color: 'var(--wa-text-2)' }}>
                {supportsEveryone
                  ? 'Escolha se elas também devem sumir do WhatsApp do cliente ou só daqui do CRM.'
                  : 'Pelo menos uma delas não pode ser apagada no WhatsApp do cliente. Saem só daqui do CRM.'}
              </p>
              <div className="flex flex-col gap-2">
                {supportsEveryone && (
                  <button onClick={() => choose(true)} className="w-full text-left px-3 py-2.5 rounded-lg bg-red-500/10 hover:bg-red-500/20 border border-red-500/30">
                    <span className="block text-[14px] font-medium text-red-500">Apagar para todos</span>
                  </button>
                )}
                <button onClick={() => choose(false)} className="w-full text-left px-3 py-2.5 rounded-lg hover:bg-[var(--wa-row-hover)]" style={{ border: '1px solid var(--wa-divider)' }}>
                  <span className="block text-[14px] font-medium">Apagar apenas para mim</span>
                </button>
                <button onClick={close} className="w-full text-center px-3 py-2 rounded-lg text-[14px]" style={{ color: 'var(--wa-green)' }}>Cancelar</button>
              </div>
            </div>
          </div>
        )
      })()}
    </>
  )
}
