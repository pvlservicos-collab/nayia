'use client'

/**
 * O CARD DO CONTATO NA PARCERIA (Pedro, 29/09/2026): "quero refazer o card do
 * lead la do lado, vai ter uma opção de mandar imóvel direto para o lead la no
 * lado do card dele e tira todas aquelas informações la e faz informações que
 * fazem sentido para a gente, e o historico do que aquele contato já pediu,
 * quero poder também arrastar para o lado o card do lead para aumentar ele".
 *
 * O que fica: quem é a pessoa para a Nay (corretor com CRECI, proprietário e
 * de quais imóveis, o Tel com a conversa), a visita em andamento, mandar um
 * imóvel pelo código (o mesmo envio do "/3050" da caixa de digitar: o card
 * dos grupos e as fotos), o histórico do que ela pediu, recebeu e visitou, e
 * a etiqueta do funil da Parceria. Saiu o que era de loja (pedido, venda,
 * agenda do quiz, campos soltos).
 *
 * A borda da esquerda puxa para alargar; a largura fica guardada neste
 * navegador. Em tela menor que 1280px o card abre por cima da conversa.
 *
 * 29/09 (tarde), pedidos do Pedro: apelido no lugar do nome (lápis), copiar o
 * número sem o 55 ("92 9 8630-1622"), as etiquetas logo embaixo do número
 * (pôr, trocar, criar), uma caixa de observação, e a pasta do corretor com os
 * documentos dele.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import {
  X, User, PaperPlaneRight, CalendarCheck, ChatCircleDots, House, ArrowClockwise, CircleNotch, WarningCircle, CheckCircle,
  PencilSimple, Check, Copy, Plus, FolderSimple, FileText, UploadSimple, Trash, Robot,
} from '@phosphor-icons/react'
import type { LeadWithOwner } from '@/lib/types'
import { formatPhone } from '@/lib/utils'
import { useContatoNay } from '@/hooks/useContatoNay'
import { useParceriaMarcas, recarregarMarcasDaParceria } from '@/hooks/useParceriaMarcas'
import { ESTADO_DA_VISITA, type ItemDoHistorico } from '@/lib/tiposNay'
import TrilhaDaNay from './TrilhaDaNay'
import EscolherImoveis, { useOpcoesDoDisparo, type ImovelParaEnviar } from '@/components/Disparo/EscolherImoveis'
import EtapaDoLead from './EtapaDoLead'
import { escolhaAMao } from '@/lib/etapaDaParceria'

const LARGURA_GUARDADA = 'crm:largura-card-parceria'
const LARGURA_MIN = 300
const LARGURA_MAX = 640
const LARGURA_PADRAO = 360

/** O número para colar em qualquer lugar: sem o 55, "92 9 8630-1622". */
export function numeroParaCopiar(telefone: string | null | undefined): string | null {
  let d = String(telefone || '').replace(/\D/g, '')
  if (d.startsWith('55') && d.length >= 12 && d.length <= 13) d = d.slice(2)
  if (d.length === 11) return `${d.slice(0, 2)} ${d[2]} ${d.slice(3, 7)}-${d.slice(7)}`
  if (d.length === 10) return `${d.slice(0, 2)} ${d.slice(2, 6)}-${d.slice(6)}`
  return null
}

function tamanhoDoArquivo(bytes: number | null | undefined) {
  const b = Number(bytes || 0)
  return b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`
}

type Documento = { id: string; nome: string; url: string; tipo: string | null; tamanho: number | null; criadoEm: string }

let etiquetasGuardadas: Promise<Array<{ id: string; name: string; color: string }>> | null = null
function etiquetasDaOrganizacao() {
  if (!etiquetasGuardadas) {
    etiquetasGuardadas = fetch('/api/tags').then((r) => r.json()).then((j) => j?.data || j?.tags || []).catch(() => {
      etiquetasGuardadas = null
      return []
    })
  }
  return etiquetasGuardadas
}

function dataHora(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  return `${d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`
}

function diaDoHistorico(iso: string): string {
  const d = new Date(iso)
  const hoje = new Date()
  const zero = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
  const dif = Math.round((zero(hoje) - zero(d)) / 86400000)
  if (dif === 0) return 'Hoje'
  if (dif === 1) return 'Ontem'
  return d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' })
}

function Secao({ titulo, children, acao }: { titulo: string; children: React.ReactNode; acao?: React.ReactNode }) {
  return (
    <section className="px-5 py-4" style={{ background: 'var(--wa-panel)' }}>
      <div className="flex items-center justify-between mb-2.5">
        <h3 className="text-[14px]" style={{ color: 'var(--wa-text-2)' }}>{titulo}</h3>
        {acao}
      </div>
      {children}
    </section>
  )
}

type EstadoDoEnvio = { tipo: 'ok' | 'erro' | 'aviso'; texto: string } | null

export default function PainelContatoParceria({ lead, modo, aoFechar, aoVerVisita, onTagsChange, onUpdateLead }: {
  lead: LeadWithOwner
  modo: 'lateral' | 'gaveta'
  aoFechar: () => void
  aoVerVisita?: (visitaId: number) => void
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
  onUpdateLead?: (leadId: string, updates: Partial<LeadWithOwner>) => void
}) {
  const { marca: marcaDoContato, historico, carregando, erro, recarregar } = useContatoNay(lead.id)
  const { marcas, nay } = useParceriaMarcas(true)
  /* com quem está a conversa: a escolha do card manda; senão, a marca da Nay */
  const escolhaDoCard = escolhaAMao(lead as any)
  const marcaDaPessoa = marcas[lead.id]
  const comQuem: 'tel' | 'rayssa' | null =
    escolhaDoCard === 'rayssa' || (escolhaDoCard !== 'tel' && (marcaDaPessoa?.telMotivo || '').startsWith('Rayssa:')) ? 'rayssa'
      : escolhaDoCard === 'tel' || marcaDaPessoa?.telAtendendo ? 'tel' : null
  const [tirando, setTirando] = useState(false)
  async function tirarDaPessoa() {
    if (tirando) return
    setTirando(true)
    try {
      const r = await fetch(`/api/leads/${lead.id}/contato`, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: 'todos' }),
      })
      if (!r.ok) throw new Error('não tirou')
      const depois = { ...((lead as any).custom_attributes || {}) }
      delete depois.etapa_parceria
      onUpdateLead?.(lead.id, { custom_attributes: depois } as any)
      // a marca da Nay muda na hora: sem isto a etiqueta ficaria até o próximo minuto
      void recarregarMarcasDaParceria(true)
    } catch { /* a etiqueta continua ali: é o próprio aviso de que não saiu */ }
    finally { setTirando(false) }
  }
  const marca = marcaDoContato ?? marcas[lead.id] ?? null

  /* ── largura, puxando a borda ── */
  const [largura, setLargura] = useState<number>(LARGURA_PADRAO)
  const [arrastando, setArrastando] = useState(false)
  useEffect(() => {
    try {
      const g = Number(localStorage.getItem(LARGURA_GUARDADA))
      if (g >= LARGURA_MIN && g <= LARGURA_MAX) setLargura(g)
    } catch {}
  }, [])
  const inicio = useRef<{ x: number; largura: number } | null>(null)
  const aoApertarPuxador = (e: React.PointerEvent) => {
    e.preventDefault()
    inicio.current = { x: e.clientX, largura }
    setArrastando(true)
    ;(e.target as HTMLElement).setPointerCapture?.(e.pointerId)
  }
  const aoMoverPuxador = (e: React.PointerEvent) => {
    if (!inicio.current) return
    const nova = Math.min(LARGURA_MAX, Math.max(LARGURA_MIN, inicio.current.largura + (inicio.current.x - e.clientX)))
    setLargura(nova)
  }
  const aoSoltarPuxador = () => {
    if (!inicio.current) return
    inicio.current = null
    setArrastando(false)
    try { localStorage.setItem(LARGURA_GUARDADA, String(largura)) } catch {}
  }

  /* ── mandar imóvel: a mesma escolha do menu, um a um ou por faixa (Pedro,
     29/09: "aqui no Enviar imóvel quero do jeito que tá no menu"), e o mesmo
     envio (/api/disparo): pela fila da Nay, com as regras dela -- parceiro e
     indisponível não saem, fotos do mesmo imóvel 1x a cada 24h por pessoa ── */
  const { opcoes: opcoesDoDisparo, teto: tetoDoDisparo } = useOpcoesDoDisparo()
  const [escolhidos, setEscolhidos] = useState<ImovelParaEnviar[]>([])
  const [pedidoDeCodigo, setPedidoDeCodigo] = useState<{ codigo: string; vez: number } | null>(null)
  const [rodadaDoEnvio, setRodadaDoEnvio] = useState(0)
  const [enviando, setEnviando] = useState(false)
  const [resultado, setResultado] = useState<EstadoDoEnvio>(null)

  const enviar = useCallback(async () => {
    if (!escolhidos.length || enviando) return
    setEnviando(true)
    setResultado(null)
    try {
      const r = await fetch('/api/disparo', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone: lead.phone, integrationId: lead.integration_id, codigos: escolhidos.map((e) => Number(e.codigo)) }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || 'não consegui enviar')
      setResultado({ tipo: 'ok', texto: j.resumo || 'Enviado.' })
      setEscolhidos([])
      setPedidoDeCodigo(null)
      setRodadaDoEnvio((n) => n + 1)
      setTimeout(() => void recarregar(), 4000)
    } catch (e: any) {
      setResultado({ tipo: 'erro', texto: e?.message || 'não consegui enviar' })
    } finally {
      setEnviando(false)
    }
  }, [escolhidos, enviando, lead.phone, lead.integration_id, recarregar])

  /* ── as etiquetas, embaixo do número: pôr, tirar, criar ── */
  const [etiquetas, setEtiquetas] = useState<Array<{ id: string; name: string; color: string }>>([])
  const [menuEtiquetas, setMenuEtiquetas] = useState(false)
  const [novaEtiqueta, setNovaEtiqueta] = useState('')
  useEffect(() => {
    let vivo = true
    etiquetasDaOrganizacao().then((todas) => {
      // as "Nay: ..." são da Nay (a etapa já aparece no quadradinho da lista)
      if (vivo) setEtiquetas(todas.filter((t) => !t.name.startsWith('Nay:')).sort((a, b) => a.name.localeCompare(b.name, 'pt-BR')))
    })
    return () => { vivo = false }
  }, [])
  const temEtiqueta = (id: string) => (lead.lead_tags || []).some((lt) => lt.tag_id === id)
  const alternarEtiqueta = async (t: { id: string; name: string; color: string }) => {
    const tem = temEtiqueta(t.id)
    onTagsChange?.(lead.id, t.id, tem ? 'remove' : 'add', t)
    try {
      const r = await fetch(`/api/leads/${lead.id}/tags`, {
        method: tem ? 'DELETE' : 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tag_id: t.id }),
      })
      if (!r.ok) throw new Error()
    } catch {
      onTagsChange?.(lead.id, t.id, tem ? 'add' : 'remove', t)
    }
  }
  const criarEtiqueta = async () => {
    const nome = novaEtiqueta.trim()
    if (!nome) return
    const existente = etiquetas.find((t) => t.name.toLowerCase() === nome.toLowerCase())
    if (existente) { if (!temEtiqueta(existente.id)) void alternarEtiqueta(existente); setNovaEtiqueta(''); return }
    try {
      const r = await fetch('/api/tags', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: nome, source: 'crm', color: '#64748b' }) })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || !j?.data?.id) throw new Error()
      const t = { id: j.data.id, name: j.data.name, color: j.data.color || '#64748b' }
      etiquetasGuardadas = null
      setEtiquetas((xs) => [...xs, t].sort((a, b) => a.name.localeCompare(b.name, 'pt-BR')))
      setNovaEtiqueta('')
      void alternarEtiqueta(t)
    } catch { /* o nome já existe em outra forma, ou sem rede: fica o texto para tentar de novo */ }
  }
  const etiquetasDoLead = (lead.lead_tags || [])
    .map((lt: any) => lt.tag || etiquetas.find((t) => t.id === lt.tag_id))
    .filter((t: any) => t && !String(t.name).startsWith('Nay:'))

  /* ── apelido (o nome que a lista mostra) ── */
  const [editandoNome, setEditandoNome] = useState(false)
  const [nome, setNome] = useState(lead.title || '')
  useEffect(() => { if (!editandoNome) setNome(lead.title || '') }, [lead.title, editandoNome])
  const salvarNome = async () => {
    const novo = nome.trim()
    if (!novo || novo === lead.title) { setEditandoNome(false); return }
    const r = await fetch(`/api/leads/${lead.id}/contato`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ apelido: novo }) }).catch(() => null)
    if (r?.ok) setEditandoNome(false)
  }

  /* ── copiar o número ── */
  const numero = numeroParaCopiar(lead.phone)
  const [copiado, setCopiado] = useState(false)
  const copiar = async () => {
    if (!numero) return
    try { await navigator.clipboard.writeText(numero) } catch {
      const el = document.createElement('textarea'); el.value = numero; document.body.appendChild(el); el.select()
      try { document.execCommand('copy') } catch {} ; el.remove()
    }
    setCopiado(true)
    setTimeout(() => setCopiado(false), 1600)
  }

  /* ── observação ── */
  const observacaoGuardada = String((lead.custom_attributes as Record<string, unknown> | undefined)?.observacao ?? '')
  const [observacao, setObservacao] = useState(observacaoGuardada)
  const [estadoObs, setEstadoObs] = useState<'' | 'salvando' | 'salvo' | 'erro'>('')
  const obsTocada = useRef(false)
  useEffect(() => { if (!obsTocada.current) setObservacao(observacaoGuardada) }, [observacaoGuardada])
  useEffect(() => { obsTocada.current = false; setObservacao(observacaoGuardada); setEstadoObs('') }, [lead.id]) // eslint-disable-line react-hooks/exhaustive-deps
  const salvarObservacao = async () => {
    if (!obsTocada.current || observacao === observacaoGuardada) return
    setEstadoObs('salvando')
    const r = await fetch(`/api/leads/${lead.id}/contato`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ observacao }) }).catch(() => null)
    setEstadoObs(r?.ok ? 'salvo' : 'erro')
    if (r?.ok) { obsTocada.current = false; setTimeout(() => setEstadoObs(''), 2000) }
  }

  /* ── Parar Nay / Nay voltar a atender (migração 176) ── */
  const [mexendoNaNay, setMexendoNaNay] = useState<'parar' | 'voltar' | null>(null)
  const [avisoDaNay, setAvisoDaNay] = useState<{ ok: boolean; texto: string } | null>(null)
  const pararOuVoltar = async (acao: 'parar' | 'voltar') => {
    setMexendoNaNay(acao); setAvisoDaNay(null)
    try {
      const r = await fetch(`/api/leads/${lead.id}/nay`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ acao }) })
      const j = await r.json().catch(() => ({}))
      setAvisoDaNay({ ok: r.ok && j.ok !== false, texto: j.mensagem || j.error || 'Não consegui falar com a Nay.' })
    } catch {
      setAvisoDaNay({ ok: false, texto: 'Sem conexão com o CRM.' })
    }
    setMexendoNaNay(null)
    void recarregar()
    void recarregarMarcasDaParceria(true)
  }

  /* ── a pasta do corretor ── */
  const ehCorretor = !!marca?.corretor

  /* ── o checklist de documentos (Pedro, 29/09: "no card dos corretores um
     botão enviar checklist, abre a opção venda ou aluguel, e a Nay envia") ── */
  const [checklistAberto, setChecklistAberto] = useState(false)
  const [tipoChecklist, setTipoChecklist] = useState<'locacao' | 'venda'>('locacao')
  const [mandandoChecklist, setMandandoChecklist] = useState(false)
  const [avisoChecklist, setAvisoChecklist] = useState<EstadoDoEnvio>(null)
  const enviarChecklist = async () => {
    if (mandandoChecklist) return
    setMandandoChecklist(true)
    setAvisoChecklist(null)
    try {
      const r = await fetch(`/api/leads/${lead.id}/checklist`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tipo: tipoChecklist }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || 'não consegui')
      setAvisoChecklist({ tipo: 'ok', texto: j.resumo || 'Mandei.' })
      setChecklistAberto(false)
    } catch (e: any) {
      setAvisoChecklist({ tipo: 'erro', texto: e?.message || 'não consegui' })
    } finally {
      setMandandoChecklist(false)
    }
  }
  const [documentos, setDocumentos] = useState<Documento[]>([])
  const [enviandoDoc, setEnviandoDoc] = useState(false)
  const [erroDoc, setErroDoc] = useState<string | null>(null)
  const [apagarDoc, setApagarDoc] = useState<string | null>(null)
  const entradaDeArquivo = useRef<HTMLInputElement>(null)
  const lerDocumentos = useCallback(async () => {
    const r = await fetch(`/api/leads/${lead.id}/documentos`).catch(() => null)
    const j = r?.ok ? await r.json().catch(() => ({})) : {}
    setDocumentos((j.documentos || []) as Documento[])
  }, [lead.id])
  useEffect(() => { if (ehCorretor) void lerDocumentos(); else setDocumentos([]) }, [ehCorretor, lerDocumentos])
  const guardarDocumentos = async (arquivos: FileList | null) => {
    if (!arquivos?.length) return
    setEnviandoDoc(true); setErroDoc(null)
    for (const a of Array.from(arquivos)) {
      const f = new FormData()
      f.append('arquivo', a)
      const r = await fetch(`/api/leads/${lead.id}/documentos`, { method: 'POST', body: f }).catch(() => null)
      if (!r?.ok) {
        const j = r ? await r.json().catch(() => ({})) : {}
        setErroDoc(`${a.name}: ${j?.error || 'não consegui guardar'}`)
      }
    }
    setEnviandoDoc(false)
    if (entradaDeArquivo.current) entradaDeArquivo.current.value = ''
    void lerDocumentos()
  }
  const tirarDocumento = async (id: string) => {
    const r = await fetch(`/api/leads/${lead.id}/documentos/${id}`, { method: 'DELETE' }).catch(() => null)
    setApagarDoc(null)
    if (r?.ok) setDocumentos((ds) => ds.filter((d) => d.id !== id))
  }

  /* ── o histórico, por dia ── */
  const [verTudo, setVerTudo] = useState(false)
  const itens = verTudo ? historico : historico.slice(0, 25)
  const porDia: Array<{ dia: string; itens: ItemDoHistorico[] }> = []
  for (const h of itens) {
    const dia = diaDoHistorico(h.quando)
    const ultimo = porDia[porDia.length - 1]
    if (ultimo && ultimo.dia === dia) ultimo.itens.push(h)
    else porDia.push({ dia, itens: [h] })
  }

  const estadoDaVisita = marca?.visitaEstado ? ESTADO_DA_VISITA[marca.visitaEstado] : null

  const corpo = (
    <div className="flex flex-col h-full min-h-0" style={{ background: 'var(--wa-app)' }}>
      <div className="wa-topo gap-3 flex-shrink-0" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
        <button type="button" className="wa-icone-btn -ml-2" onClick={aoFechar} aria-label="Fechar os dados do contato"><X size={22} /></button>
        <h2 className="text-[16px] font-normal" style={{ color: 'var(--wa-text)', fontFamily: 'inherit' }}>Dados do contato</h2>
        <button type="button" className="wa-icone-btn ml-auto" onClick={() => void recarregar()} title="Atualizar o que a Nay sabe">
          <ArrowClockwise size={18} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto wa-rolagem flex flex-col gap-2">
        {/* quem é */}
        <div className="flex flex-col items-center text-center px-6 pt-6 pb-5" style={{ background: 'var(--wa-panel)' }}>
          <div className="w-[120px] h-[120px] rounded-full overflow-hidden flex items-center justify-center mb-3"
               style={{ backgroundColor: 'var(--wa-row-selected)' }}>
            {lead.avatar_url
              ? <img src={lead.avatar_url} alt="" className="w-full h-full object-cover" />
              : <User size={64} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.5 }} />}
          </div>
          {editandoNome ? (
            <form className="flex items-center gap-1.5 w-full max-w-[320px]" onSubmit={(e) => { e.preventDefault(); void salvarNome() }}>
              <input value={nome} onChange={(e) => setNome(e.target.value)} autoFocus maxLength={120} aria-label="Apelido do contato"
                     className="flex-1 min-w-0 h-9 px-3 rounded-lg text-[16px] text-center"
                     style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }} />
              <button type="submit" className="wa-icone-btn !w-8 !h-8" title="Salvar o apelido" aria-label="Salvar o apelido">
                <Check size={17} weight="bold" style={{ color: 'var(--wa-green)' }} />
              </button>
              <button type="button" className="wa-icone-btn !w-8 !h-8" onClick={() => { setEditandoNome(false); setNome(lead.title || '') }} aria-label="Cancelar">
                <X size={16} />
              </button>
            </form>
          ) : (
            <p className="text-[20px] leading-7 break-words flex items-center justify-center gap-1" style={{ color: 'var(--wa-text)' }}>
              {formatPhone(lead.title)}
              <button type="button" onClick={() => setEditandoNome(true)} className="wa-icone-btn !w-7 !h-7 opacity-70 hover:opacity-100"
                      title="Trocar o nome (apelido)" aria-label="Trocar o nome (apelido)">
                <PencilSimple size={15} />
              </button>
            </p>
          )}
          {numero ? (
            <p className="text-[15px] mt-0.5 flex items-center justify-center gap-1" style={{ color: 'var(--wa-text-2)' }}>
              <span className="select-all">{numero}</span>
              <button type="button" onClick={() => void copiar()} className="wa-icone-btn !w-7 !h-7"
                      title={copiado ? 'Copiado!' : 'Copiar o número (sem o 55)'} aria-label="Copiar o número">
                {copiado ? <Check size={15} weight="bold" style={{ color: 'var(--wa-green)' }} /> : <Copy size={15} />}
              </button>
              {copiado && <span className="text-[12px]" style={{ color: 'var(--wa-green)' }}>copiado</span>}
            </p>
          ) : lead.phone && lead.phone !== lead.title ? (
            <p className="text-[14px] mt-0.5" style={{ color: 'var(--wa-text-2)' }}>{formatPhone(lead.phone)}</p>
          ) : null}

          {/* A ETAPA, logo abaixo do número (Tel, 30/09): "no card dentro do chat,
              quando eu clico no lead". Este é o card que a Parceria usa -- o
              menu tinha ido parar no LeadDetailsSidebar, que o chat da
              Parceria nem desenha. */}
          <div className="mt-3 text-left">
            <EtapaDoLead lead={lead} onUpdateLead={onUpdateLead} />
          </div>

          {/* as etiquetas: embaixo do número (Pedro, 29/09) */}
          <div className="flex flex-wrap justify-center items-center gap-1.5 mt-3 relative">
            {etiquetasDoLead.map((t: any) => (
              <span key={t.id} className="wa-marca !pr-1 inline-flex items-center gap-1" style={{ color: t.color?.startsWith('#') ? t.color : 'var(--wa-text-2)' }}>
                {t.name}
                <button type="button" onClick={() => void alternarEtiqueta(t)} className="rounded-full hover:bg-black/10 p-0.5" title={`Tirar "${t.name}"`} aria-label={`Tirar ${t.name}`}>
                  <X size={10} weight="bold" />
                </button>
              </span>
            ))}
            <button type="button" onClick={() => setMenuEtiquetas((m) => !m)} className="wa-chip !h-7 !px-2.5 !text-[12.5px]"
                    aria-expanded={menuEtiquetas} title="Pôr ou trocar etiqueta">
              <Plus size={12} weight="bold" /> Etiqueta
            </button>
            {menuEtiquetas && (
              <div className="absolute top-full mt-1.5 z-30 w-[260px] max-h-[300px] overflow-y-auto wa-rolagem rounded-xl shadow-2xl p-1.5 text-left"
                   style={{ background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}>
                {etiquetas.map((t) => {
                  const on = temEtiqueta(t.id)
                  return (
                    <button key={t.id} type="button" onClick={() => void alternarEtiqueta(t)}
                            className="w-full flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-[13.5px] hover:bg-[var(--wa-row-hover)]"
                            style={{ color: 'var(--wa-text)' }}>
                      <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ backgroundColor: t.color }} />
                      <span className="flex-1 truncate">{t.name}</span>
                      {on && <Check size={14} weight="bold" style={{ color: 'var(--wa-green)' }} />}
                    </button>
                  )
                })}
                <form className="flex items-center gap-1 mt-1 pt-1.5" style={{ borderTop: '1px solid var(--wa-divider)' }}
                      onSubmit={(e) => { e.preventDefault(); void criarEtiqueta() }}>
                  <input value={novaEtiqueta} onChange={(e) => setNovaEtiqueta(e.target.value)} placeholder="Criar etiqueta…" maxLength={40}
                         className="flex-1 min-w-0 h-8 px-2 rounded-md text-[13px]" style={{ background: 'var(--wa-app)', color: 'var(--wa-text)' }} />
                  <button type="submit" disabled={!novaEtiqueta.trim()} className="wa-icone-btn !w-8 !h-8 disabled:opacity-40" aria-label="Criar etiqueta">
                    <Plus size={15} weight="bold" />
                  </button>
                </form>
                <button type="button" onClick={() => setMenuEtiquetas(false)} className="w-full mt-1 text-[12.5px] py-1" style={{ color: 'var(--wa-text-2)' }}>Fechar</button>
              </div>
            )}
          </div>

          <div className="flex flex-wrap justify-center gap-1.5 mt-2.5">
            {marca?.corretor && (
              <span className="wa-marca" style={{ color: 'var(--wa-tag-corretor)' }}>
                Corretor parceiro{marca.creci ? ` · CRECI ${marca.creci}` : ''}
              </span>
            )}
            {marca?.proprietario && <span className="wa-marca" style={{ color: 'var(--wa-tag-prop)' }}>Proprietário</span>}
            {/* A ETIQUETA DE QUEM ESTÁ COM A CONVERSA, com × (Tel, 30/09): "quero
                tirar a etiqueta de tel ou rayssa lá no card do contato também, e
                aí ele sai da tag deles do chat". Tirar devolve a conversa à Nay
                (crm_etapa_manual 'todos': limpa a marca de humano). */}
            {comQuem && (
              <span className="wa-marca !pr-1 inline-flex items-center gap-1" style={{ color: 'var(--wa-tag-tel)' }} title={marca?.telMotivo || ''}>
                {comQuem === 'rayssa' ? 'Com a Rayssa' : 'Com o Tel'}
                <button type="button" onClick={tirarDaPessoa} disabled={tirando}
                        aria-label={`Tirar a etiqueta ${comQuem === 'rayssa' ? 'da Rayssa' : 'do Tel'}`}
                        title="Tirar: a conversa sai da aba e volta para a Nay"
                        className="rounded-full px-1 leading-none hover:opacity-70">×</button>
              </span>
            )}
            {!marca && carregando && <span className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Perguntando à Nay…</span>}
          </div>
          {/* a trilha da Nay com o contato, ativa ou parada (Pedro, 29/09) */}
          <TrilhaDaNay marca={marca} nay={nay} />
          {/* Parar Nay / Nay voltar a atender (Pedro, 29/09) */}
          <div className="flex flex-wrap justify-center gap-2 mt-3">
            <button type="button" onClick={() => void pararOuVoltar('parar')} disabled={!!mexendoNaNay}
                    className="inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
                    style={marca?.telAtendendo
                      ? { color: 'var(--wa-text-2)', border: '1px solid var(--wa-divider)' }
                      : { color: 'var(--wa-tag-tel)', border: '1px solid color-mix(in srgb, var(--wa-tag-tel) 50%, transparent)' }}
                    title="A Nay para de responder esta pessoa até alguém soltar">
              {mexendoNaNay === 'parar' ? <CircleNotch size={14} className="animate-spin" /> : <Robot size={14} weight="fill" />} Parar Nay
            </button>
            <button type="button" onClick={() => void pararOuVoltar('voltar')} disabled={!!mexendoNaNay}
                    className="inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
                    style={marca?.telAtendendo
                      ? { background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }
                      : { color: 'var(--wa-green)', border: '1px solid color-mix(in srgb, var(--wa-green) 50%, transparent)' }}
                    title="A Nay volta a responder e recebe de novo a última mensagem da pessoa, se ficou sem resposta">
              {mexendoNaNay === 'voltar' ? <CircleNotch size={14} className="animate-spin" /> : <Robot size={14} weight="fill" />} Nay voltar a atender
            </button>
          </div>
          {avisoDaNay && (
            <p className="text-[12.5px] mt-2 leading-4" style={{ color: avisoDaNay.ok ? 'var(--wa-green)' : 'var(--wa-tag-tel)' }}>{avisoDaNay.texto}</p>
          )}
          {erro && !marca && (
            <p className="text-[12.5px] mt-2 flex items-center gap-1" style={{ color: 'var(--wa-tag-tel)' }}>
              <WarningCircle size={14} /> Não consegui ler a Nay agora.
            </p>
          )}

          {/* observação (Pedro, 29/09: "um quadradinho de observação, caixa de mensagem para escrever") */}
          <div className="w-full mt-4 text-left">
            <div className="flex items-center justify-between mb-1">
              <label htmlFor={`obs-${lead.id}`} className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Observação</label>
              <span className="text-[11.5px]" style={{ color: estadoObs === 'erro' ? 'var(--wa-tag-tel)' : 'var(--wa-text-2)' }}>
                {estadoObs === 'salvando' ? 'Salvando…' : estadoObs === 'salvo' ? 'Salvo' : estadoObs === 'erro' ? 'Não salvou — tente de novo' : ''}
              </span>
            </div>
            <textarea id={`obs-${lead.id}`} value={observacao} rows={3} maxLength={4000}
                      onChange={(e) => { obsTocada.current = true; setObservacao(e.target.value) }}
                      onBlur={() => void salvarObservacao()}
                      placeholder="Anote aqui o que a equipe precisa saber deste contato…"
                      className="w-full rounded-lg px-3 py-2 text-[14px] leading-5 resize-y min-h-[72px]"
                      style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }} />
          </div>
        </div>

        {/* mandar imóvel */}
        <Secao titulo="Enviar imóvel">
          <EscolherImoveis key={rodadaDoEnvio} compacto escolhidos={escolhidos}
                           aoMudar={(l) => { setEscolhidos(l); setResultado(null) }}
                           teto={tetoDoDisparo} opcoes={opcoesDoDisparo} pedido={pedidoDeCodigo}
                           aoAvisar={(texto) => setResultado(texto ? { tipo: 'aviso', texto } : null)} />
          <button type="button" onClick={() => void enviar()} disabled={!escolhidos.length || enviando}
                  className="mt-3 w-full h-10 rounded-full text-[14px] font-semibold flex items-center justify-center gap-1.5 disabled:opacity-40"
                  style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
            {enviando ? <CircleNotch size={16} className="animate-spin" /> : <PaperPlaneRight size={16} weight="fill" />}
            {escolhidos.length ? `Enviar ${escolhidos.length} imóve${escolhidos.length === 1 ? 'l' : 'is'}` : 'Enviar'}
          </button>
          {resultado && (
            <p className="text-[13px] mt-2 flex items-start gap-1.5 whitespace-pre-wrap"
               style={{ color: resultado.tipo === 'ok' ? 'var(--wa-green)' : resultado.tipo === 'aviso' ? 'var(--wa-tag-prop)' : 'var(--wa-tag-tel)' }}>
              {resultado.tipo === 'ok' ? <CheckCircle size={16} className="mt-px flex-shrink-0" /> : <WarningCircle size={16} className="mt-px flex-shrink-0" />}
              {resultado.texto}
            </p>
          )}
          {resultado?.tipo === 'ok' && (
            <p className="text-[12px] mt-1" style={{ color: 'var(--wa-text-2)' }}>
              Sai pela fila da Nay em alguns segundos, uma foto de cada vez (entre 6h e 22h; fora disso, às 6h).
            </p>
          )}
        </Secao>

        {/* o checklist de documentos, só para corretor (29/09) */}
        {ehCorretor && (
          <Secao titulo="Checklist de documentos">
            {!checklistAberto ? (
              <button type="button" onClick={() => { setChecklistAberto(true); setAvisoChecklist(null) }}
                      className="w-full h-10 rounded-full text-[14px] font-semibold flex items-center justify-center gap-1.5"
                      style={{ border: '1px solid var(--wa-green)', color: 'var(--wa-green)' }}>
                <FileText size={16} /> Enviar checklist
              </button>
            ) : (
              <div>
                <div className="flex gap-2" role="radiogroup" aria-label="Qual checklist">
                  {([['locacao', 'Aluguel'], ['venda', 'Venda']] as const).map(([v, rotulo]) => (
                    <button key={v} type="button" role="radio" aria-checked={tipoChecklist === v} onClick={() => setTipoChecklist(v)}
                            className="flex-1 h-10 rounded-full text-[14px] font-semibold"
                            style={tipoChecklist === v
                              ? { background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }
                              : { background: 'var(--wa-search)', color: 'var(--wa-text)' }}>
                      {rotulo}
                    </button>
                  ))}
                </div>
                <div className="flex gap-2 mt-2">
                  <button type="button" onClick={() => setChecklistAberto(false)} disabled={mandandoChecklist}
                          className="h-10 px-4 rounded-full text-[14px]" style={{ color: 'var(--wa-text-2)' }}>Cancelar</button>
                  <button type="button" onClick={() => void enviarChecklist()} disabled={mandandoChecklist}
                          className="flex-1 h-10 rounded-full text-[14px] font-semibold flex items-center justify-center gap-1.5 disabled:opacity-50"
                          style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
                    {mandandoChecklist ? <CircleNotch size={16} className="animate-spin" /> : <PaperPlaneRight size={16} weight="fill" />}
                    A Nay envia o de {tipoChecklist === 'venda' ? 'venda' : 'aluguel'}
                  </button>
                </div>
              </div>
            )}
            {avisoChecklist && (
              <p className="text-[13px] mt-2 flex items-start gap-1.5"
                 style={{ color: avisoChecklist.tipo === 'ok' ? 'var(--wa-green)' : 'var(--wa-tag-tel)' }}>
                {avisoChecklist.tipo === 'ok' ? <CheckCircle size={16} className="mt-px flex-shrink-0" /> : <WarningCircle size={16} className="mt-px flex-shrink-0" />}
                {avisoChecklist.texto}
              </p>
            )}
          </Secao>
        )}

        {/* visita */}
        {marca?.visitaAberta && (
          <Secao titulo="Visita em andamento">
            <button type="button" onClick={() => marca.visitaId && aoVerVisita?.(marca.visitaId)}
                    className="w-full flex items-start gap-3 text-left rounded-lg p-2.5 hover:bg-[var(--wa-row-hover)]">
              <CalendarCheck size={22} style={{ color: 'var(--wa-tag-visita)' }} className="flex-shrink-0 mt-0.5" />
              <span className="min-w-0">
                <span className="block text-[15px]" style={{ color: 'var(--wa-text)' }}>
                  {dataHora(marca.visitaQuando)}{marca.visitaCodigo ? ` · código ${marca.visitaCodigo}` : ''}
                </span>
                <span className="block text-[13px]" style={{ color: 'var(--wa-text-2)' }}>
                  {estadoDaVisita?.rotulo || marca.visitaEstado}{marca.visitaPapel === 'proprietario' ? ' · ele é o proprietário' : ''}
                </span>
                {aoVerVisita && <span className="block text-[13px] mt-0.5" style={{ color: 'var(--wa-green)' }}>Ver o andamento em Visitas</span>}
              </span>
            </button>
          </Secao>
        )}

        {/* imóveis do dono */}
        {marca?.proprietario && (
          <Secao titulo={marca.imoveisDoDono.length ? `Imóveis dele (${marca.imoveisDoDono.length})` : 'Proprietário'}>
            {marca.proprietarioNome && (
              <p className="text-[13px] mb-2" style={{ color: 'var(--wa-text-2)' }}>No cadastro: {marca.proprietarioNome}</p>
            )}
            {marca.imoveisDoDono.length > 0 ? (
              <div className="flex flex-wrap gap-1.5">
                {marca.imoveisDoDono.map((c) => (
                  <span key={c} className="inline-flex items-center gap-1 px-2.5 h-7 rounded-full text-[13px]"
                        style={{ background: 'var(--wa-search)', color: 'var(--wa-text)' }}>
                    <House size={13} /> {c}
                  </span>
                ))}
              </div>
            ) : (
              <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>A Nay sabe que é proprietário, mas não tem o código do imóvel.</p>
            )}
          </Secao>
        )}

        {/* a pasta do corretor (Pedro, 29/09: "uma pasta embaixo dos corretores para anexar os documentos";
            e depois: "põe em cima de O que já pediu, recebeu e visitou") */}
        {ehCorretor && (
          <Secao titulo={`Pasta do corretor${documentos.length ? ` (${documentos.length})` : ''}`}
                 acao={
                   <button type="button" onClick={() => entradaDeArquivo.current?.click()} disabled={enviandoDoc}
                           className="inline-flex items-center gap-1 text-[13px] font-semibold disabled:opacity-50" style={{ color: 'var(--wa-green)' }}>
                     {enviandoDoc ? <CircleNotch size={14} className="animate-spin" /> : <UploadSimple size={14} />} Anexar
                   </button>
                 }>
            <input ref={entradaDeArquivo} type="file" multiple className="hidden" onChange={(e) => void guardarDocumentos(e.target.files)} />
            {documentos.length === 0 ? (
              <button type="button" onClick={() => entradaDeArquivo.current?.click()}
                      className="w-full flex flex-col items-center gap-1 py-4 rounded-lg text-[13px]"
                      style={{ border: '1.5px dashed var(--wa-divider)', color: 'var(--wa-text-2)' }}>
                <FolderSimple size={26} />
                Nenhum documento ainda. Toque para anexar (RG, CRECI, contrato…).
              </button>
            ) : (
              <ul className="flex flex-col">
                {documentos.map((d) => (
                  <li key={d.id} className="flex items-center gap-2.5 py-1.5">
                    <FileText size={20} className="flex-shrink-0" style={{ color: 'var(--wa-text-2)' }} />
                    <a href={d.url} target="_blank" rel="noopener noreferrer" className="min-w-0 flex-1 hover:underline">
                      <span className="block text-[14px] truncate" style={{ color: 'var(--wa-text)' }}>{d.nome}</span>
                      <span className="block text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
                        {tamanhoDoArquivo(d.tamanho)} · {new Date(d.criadoEm).toLocaleDateString('pt-BR')}
                      </span>
                    </a>
                    {apagarDoc === d.id ? (
                      <span className="flex items-center gap-1 text-[12.5px]">
                        <button type="button" onClick={() => void tirarDocumento(d.id)} className="font-semibold" style={{ color: 'var(--wa-tag-tel)' }}>Tirar</button>
                        <button type="button" onClick={() => setApagarDoc(null)} style={{ color: 'var(--wa-text-2)' }}>Não</button>
                      </span>
                    ) : (
                      <button type="button" onClick={() => setApagarDoc(d.id)} className="wa-icone-btn !w-7 !h-7" title="Tirar da pasta" aria-label={`Tirar ${d.nome}`}>
                        <Trash size={14} />
                      </button>
                    )}
                  </li>
                ))}
              </ul>
            )}
            {erroDoc && <p className="text-[12.5px] mt-1.5" style={{ color: 'var(--wa-tag-tel)' }}>{erroDoc}</p>}
          </Secao>
        )}
        {/* histórico */}
        <Secao titulo="O que já pediu, recebeu e visitou">
          {carregando && !historico.length ? (
            <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Carregando…</p>
          ) : historico.length === 0 ? (
            <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Nada registrado na Nay para este contato ainda.</p>
          ) : (
            <div className="flex flex-col gap-3">
              {porDia.map((g) => (
                <div key={g.dia}>
                  <p className="text-[12px] font-semibold uppercase tracking-wide mb-1" style={{ color: 'var(--wa-text-2)' }}>{g.dia}</p>
                  <ul className="flex flex-col">
                    {g.itens.map((h, i) => (
                      <li key={i} className="flex gap-2.5 py-1.5">
                        <span className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0"
                              style={{ background: 'var(--wa-search)',
                                       color: h.tipo === 'pediu' ? 'var(--wa-tag-prop)' : h.tipo === 'visita' ? 'var(--wa-tag-visita)' : 'var(--wa-green)' }}>
                          {h.tipo === 'pediu' ? <ChatCircleDots size={15} /> : h.tipo === 'visita' ? <CalendarCheck size={15} /> : <PaperPlaneRight size={14} />}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="block text-[14px] leading-[18px]" style={{ color: 'var(--wa-text)' }}>
                            {h.tipo === 'pediu' ? 'Perguntou do ' : h.tipo === 'recebeu' ? 'Recebeu o ' : 'Visita no '}
                            {h.codigo ? (
                              <button type="button" className="font-semibold hover:underline" style={{ color: 'var(--wa-green)' }}
                                      onClick={() => setPedidoDeCodigo({ codigo: String(h.codigo), vez: Date.now() })} title="Pôr no Enviar imóvel">
                                {h.codigo}
                              </button>
                            ) : 'imóvel'}
                            {h.tipo === 'visita' && h.detalhe ? ` · ${ESTADO_DA_VISITA[h.detalhe]?.rotulo || h.detalhe}` : ''}
                          </span>
                          {h.imovel && <span className="block text-[12.5px] truncate" style={{ color: 'var(--wa-text-2)' }}>{h.imovel.replace(/, código \d+$/, '')}</span>}
                          {h.tipo === 'pediu' && h.detalhe && (
                            <span className="block text-[12.5px] italic line-clamp-2" style={{ color: 'var(--wa-text-2)' }}>“{h.detalhe}”</span>
                          )}
                        </span>
                        <span className="text-[11.5px] flex-shrink-0 pt-0.5" style={{ color: 'var(--wa-text-2)' }}>
                          {new Date(h.quando).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
              {historico.length > 25 && (
                <button type="button" onClick={() => setVerTudo((v) => !v)} className="text-[13px] font-semibold self-start" style={{ color: 'var(--wa-green)' }}>
                  {verTudo ? 'Mostrar menos' : `Ver tudo (${historico.length})`}
                </button>
              )}
            </div>
          )}
        </Secao>

        <div className="h-4 flex-shrink-0" />
      </div>
    </div>
  )

  if (modo === 'gaveta') {
    return (
      <div className="fixed inset-0 z-50 flex justify-end" onClick={aoFechar}>
        <div className="absolute inset-0 bg-black/40" />
        <aside className="relative h-full w-[min(420px,92vw)] shadow-2xl" onClick={(e) => e.stopPropagation()}>
          {corpo}
        </aside>
      </div>
    )
  }

  return (
    <aside className="relative h-full flex-shrink-0" style={{ width: largura, borderLeft: '1px solid var(--wa-divider)' }}>
      <div
        className={`wa-puxador ${arrastando ? 'wa-puxador--arrastando' : ''}`}
        onPointerDown={aoApertarPuxador}
        onPointerMove={aoMoverPuxador}
        onPointerUp={aoSoltarPuxador}
        onPointerCancel={aoSoltarPuxador}
        title="Arraste para alargar"
        role="separator"
        aria-orientation="vertical"
      />
      {corpo}
    </aside>
  )
}
