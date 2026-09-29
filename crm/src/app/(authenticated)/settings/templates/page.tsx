'use client'

/**
 * Templates do WhatsApp oficial (Meta).
 *
 * Tel, 26/09/2026: "coloca la no crm nas configurações os templates todos que
 * temos da api oficial para eu acompanhar status se ja aprovou e cadastrar
 * novos por la".
 *
 * O status vem da Meta na hora que a página abre -- não é cópia nossa. Quem
 * aprova, reprova e pausa por qualidade é ela, e sozinha; uma cópia nossa
 * mostraria "aprovado" para algo já derrubado.
 */
import { useCallback, useEffect, useState } from 'react'
import { ArrowClockwise, PaperPlaneTilt, Plus, X } from '@phosphor-icons/react'

interface Template {
  id: string
  nome: string
  status: string
  categoria: string
  idioma: string
  corpo: string
  variaveis: string[]
  componentes: any[]
  qualidade: string | null
  motivoRecusa: string | null
}

const COR_STATUS: Record<string, string> = {
  APPROVED: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30',
  PENDING: 'bg-amber-500/15 text-amber-400 border-amber-500/30',
  REJECTED: 'bg-red-500/15 text-red-400 border-red-500/30',
  PAUSED: 'bg-red-500/15 text-red-400 border-red-500/30',
  IN_APPEAL: 'bg-amber-500/15 text-amber-400 border-amber-500/30',
}
/** Já preenchido na prévia porque é para onde ele pediu para mandar (26/09). */
const NUMERO_DO_TEL = '559294717316'

const NOME_STATUS: Record<string, string> = {
  APPROVED: 'Aprovado', PENDING: 'Em análise', REJECTED: 'Reprovado',
  PAUSED: 'Pausado pela Meta', IN_APPEAL: 'Em recurso',
}

export default function TemplatesPage() {
  const [templates, setTemplates] = useState<Template[]>([])
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [fonte, setFonte] = useState<string | null>(null)
  const [novo, setNovo] = useState(false)
  const [enviando, setEnviando] = useState<string | null>(null)
  const [recado, setRecado] = useState<string | null>(null)
  const [leadDaConversa, setLeadDaConversa] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    setCarregando(true); setErro(null)
    try {
      const res = await fetch('/api/whatsapp-templates')
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'não consegui ler os templates')
      setTemplates(j.templates || [])
      setAviso(j.aviso || null)
      setFonte(j.fonte || null)
    } catch (e: any) {
      setErro(e?.message || 'não consegui ler os templates')
    } finally {
      setCarregando(false)
    }
  }, [])

  useEffect(() => { carregar() }, [carregar])

  async function enviarPreviaPara(t: Template) {
    const para = window.prompt(
      `Mandar "${t.nome}" para qual número? (com 55 e DDD)`,
      NUMERO_DO_TEL,
    )
    if (!para) return
    setEnviando(t.nome); setRecado(null)
    try {
      const res = await fetch('/api/whatsapp-templates/enviar', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nome: t.nome, idioma: t.idioma, componentes: t.componentes }),
      })
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'a Meta não aceitou')
      // A conversa no CRM é metade do que ele pediu: dizer que saiu sem dizer
      // onde ela apareceu deixa a pessoa procurando na aba errada.
      const onde = j.conversa
        ? ` A conversa ${j.conversa.criouLead ? 'foi criada' : 'está'} na aba ${
            ({ oficial: 'WhatsApp Oficial', parceria: 'WhatsApp Parceria', captacao: 'WhatsApp Captação' } as Record<string, string>)[j.conversa.linha] || 'WhatsApp Oficial'}.`
        : j.erroRegistro
          ? ` Mas não gravou no CRM: ${j.erroRegistro}`
          : ''
      setRecado(`"${t.nome}" saiu para ${j.para} (${j.status}).${onde}`)
      setLeadDaConversa(j.conversa?.leadId || null)
    } catch (e: any) {
      setRecado(`"${t.nome}" não saiu: ${e?.message || 'erro'}`)
    } finally {
      setEnviando(null)
    }
  }

  const porStatus = templates.reduce<Record<string, number>>((acc, t) => {
    acc[t.status] = (acc[t.status] || 0) + 1
    return acc
  }, {})

  return (
    <div className="max-w-5xl pb-12">
      <div className="flex items-start flex-wrap gap-3 justify-between mb-6 pb-5 border-b border-line">
        <div>
          <h1 className="text-2xl font-bold text-ink">Templates do WhatsApp oficial</h1>
          <p className="text-sm text-muted mt-1">
            O que a Nay pode mandar pela API oficial (número 92 8456-0874). Quem aprova é a Meta —
            o status aqui é o que ela está dizendo agora.
          </p>
        </div>
        <div className="flex gap-2">
          <button type="button" onClick={carregar}
                  className="btn-icon px-3 py-2 rounded-lg text-sm text-muted hover:text-ink flex items-center gap-2">
            <ArrowClockwise size={16} /> Atualizar
          </button>
          <button type="button" onClick={() => setNovo(true)}
                  className="bg-accent text-black font-bold px-4 py-2 rounded-lg text-sm flex items-center gap-2">
            <Plus size={16} /> Novo template
          </button>
        </div>
      </div>

      {aviso && (
        <div className="bg-amber-500/10 border border-amber-500/30 text-amber-300 text-sm rounded-xl px-4 py-3 mb-5">
          {aviso}
        </div>
      )}
      {erro && (
        <div className="bg-red-500/10 border border-red-500/30 text-red-400 text-sm rounded-xl px-4 py-3 mb-5">
          {erro}
        </div>
      )}
      {recado && (
        <div className="bg-panel-2 border border-line text-ink text-sm rounded-xl px-4 py-3 mb-5 flex flex-wrap items-center gap-3">
          <span>{recado}</span>
          {leadDaConversa && (
            <a href={`/chat?leadId=${leadDaConversa}&abrir=${Date.now()}`}
               className="text-accent-2 underline whitespace-nowrap">abrir a conversa</a>
          )}
        </div>
      )}

      {!carregando && templates.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-5 text-xs">
          {Object.entries(porStatus).map(([s, n]) => (
            <span key={s} className={`px-3 py-1 rounded-full border ${COR_STATUS[s] || 'bg-panel-2 border-line text-muted'}`}>
              {NOME_STATUS[s] || s}: {n}
            </span>
          ))}
          {fonte && <span className="px-3 py-1 rounded-full border border-line text-muted">credencial: {fonte}</span>}
        </div>
      )}

      {carregando ? (
        <p className="text-sm text-muted">Lendo da Meta…</p>
      ) : templates.length === 0 ? (
        <p className="text-sm text-muted">Nenhum template nesta conta ainda.</p>
      ) : (
        <div className="space-y-3">
          {templates.map((t) => (
            <div key={t.id} className="panel rounded-xl p-4 border border-line">
              <div className="flex items-start justify-between gap-3 flex-wrap">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-ink">{t.nome}</span>
                    <span className={`text-[11px] px-2 py-0.5 rounded-full border ${COR_STATUS[t.status] || 'bg-panel-2 border-line text-muted'}`}>
                      {NOME_STATUS[t.status] || t.status}
                    </span>
                    <span className="text-[11px] text-muted">{t.idioma} · {t.categoria}</span>
                    {t.qualidade && t.qualidade !== 'UNKNOWN' && (
                      <span className="text-[11px] text-muted">qualidade: {t.qualidade}</span>
                    )}
                  </div>
                  <p className="text-sm text-muted mt-2 whitespace-pre-wrap break-words">{t.corpo}</p>
                  {t.variaveis.length > 0 && (
                    <p className="text-[11px] text-muted mt-1">
                      preenche na hora: {t.variaveis.map((v) => `{{${v}}}`).join(', ')}
                    </p>
                  )}
                  {t.motivoRecusa && (
                    <p className="text-[11px] text-red-400 mt-1">Meta recusou: {t.motivoRecusa}</p>
                  )}
                </div>
                {t.status === 'APPROVED' && (
                  <button type="button" disabled={enviando === t.nome}
                          onClick={() => enviarPreviaPara(t)}
                          title="Mandar este template para um número, para ver como chega"
                          className="flex-shrink-0 text-xs px-3 py-1.5 rounded-lg border border-line text-muted hover:text-ink hover:bg-white/[0.06] flex items-center gap-1.5 disabled:opacity-50">
                    <PaperPlaneTilt size={14} /> {enviando === t.nome ? 'enviando…' : 'Enviar prévia'}
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {novo && <NovoTemplate onClose={() => setNovo(false)} onCriado={() => { setNovo(false); carregar() }} />}
    </div>
  )
}

/* ---------------------------------------------------------------------------
   O cadastro de template novo.

   O NOME não aceita maiúscula nem espaço (regra da Meta), então o campo já
   conserta enquanto digita em vez de deixar a Meta recusar depois.
   --------------------------------------------------------------------------- */
function NovoTemplate({ onClose, onCriado }: { onClose: () => void; onCriado: () => void }) {
  const [f, setF] = useState({
    nome: '', categoria: 'UTILITY', idioma: 'pt_BR',
    cabecalho: '', corpo: '', rodape: '', botoes: '', exemplos: '',
  })
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  const variaveis = Array.from(
    new Set([...f.corpo.matchAll(/\{\{\s*([^}\s]+)\s*\}\}/g)].map((m) => m[1])),
  )

  async function salvar(e: React.FormEvent) {
    e.preventDefault()
    setErro(null); setSalvando(true)
    try {
      const res = await fetch('/api/whatsapp-templates', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...f, exemplos: f.exemplos.split('|').map((x) => x.trim()) }),
      })
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'a Meta não aceitou')
      onCriado()
    } catch (e: any) {
      setErro(e?.message || 'a Meta não aceitou')
    } finally {
      setSalvando(false)
    }
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60" onClick={onClose}>
      <form onClick={(e) => e.stopPropagation()} onSubmit={salvar}
            className="w-full max-w-lg bg-panel border border-line rounded-2xl p-5 space-y-3 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-bold text-ink">Novo template</h2>
          <button type="button" onClick={onClose} className="text-muted hover:text-ink"><X size={18} /></button>
        </div>

        <p className="text-xs text-muted">
          Vai para a fila de aprovação da Meta — costuma sair em minutos. Enquanto estiver
          “Em análise” não dá para usar. Criar template não manda mensagem para ninguém.
        </p>

        {erro && (
          <div className="bg-red-500/10 border border-red-500/30 text-red-400 text-xs rounded-lg px-3 py-2">{erro}</div>
        )}

        <label className="block">
          <span className="block text-xs text-muted mb-1">Nome (sem maiúscula e sem espaço)</span>
          <input value={f.nome}
                 onChange={(e) => setF({ ...f, nome: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_') })}
                 className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
                 placeholder="visita_confirmada" autoFocus />
        </label>

        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <span className="block text-xs text-muted mb-1">Categoria</span>
            <select value={f.categoria} onChange={(e) => setF({ ...f, categoria: e.target.value })}
                    className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink">
              <option value="UTILITY">Utilidade (aviso, confirmação)</option>
              <option value="MARKETING">Marketing (oferta, retomada)</option>
            </select>
          </label>
          <label className="block">
            <span className="block text-xs text-muted mb-1">Idioma</span>
            <select value={f.idioma} onChange={(e) => setF({ ...f, idioma: e.target.value })}
                    className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink">
              <option value="pt_BR">Português (pt_BR)</option>
              <option value="en_US">Inglês (en_US)</option>
            </select>
          </label>
        </div>

        <label className="block">
          <span className="block text-xs text-muted mb-1">Título (opcional)</span>
          <input value={f.cabecalho} onChange={(e) => setF({ ...f, cabecalho: e.target.value })}
                 className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
                 placeholder="Visita confirmada" />
        </label>

        <label className="block">
          <span className="block text-xs text-muted mb-1">
            Texto — use {'{{1}}'}, {'{{2}}'} onde entra nome, imóvel, hora
          </span>
          <textarea value={f.corpo} onChange={(e) => setF({ ...f, corpo: e.target.value })} rows={4}
                    className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
                    placeholder="Olá, {{1}}! A visita ao imóvel {{2}} está confirmada para {{3}}." />
        </label>

        {variaveis.length > 0 && (
          <label className="block">
            <span className="block text-xs text-muted mb-1">
              Um exemplo por variável, separados por | (a Meta exige)
            </span>
            <input value={f.exemplos} onChange={(e) => setF({ ...f, exemplos: e.target.value })}
                   className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
                   placeholder={variaveis.map((v) => `valor de ${v}`).join(' | ')} />
          </label>
        )}

        <label className="block">
          <span className="block text-xs text-muted mb-1">Rodapé (opcional)</span>
          <input value={f.rodape} onChange={(e) => setF({ ...f, rodape: e.target.value })}
                 className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
                 placeholder="Imob Easy" />
        </label>

        <label className="block">
          <span className="block text-xs text-muted mb-1">Botões de resposta rápida (um por linha, até 3)</span>
          <textarea value={f.botoes} onChange={(e) => setF({ ...f, botoes: e.target.value })} rows={3}
                    className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
                    placeholder={'Confirmar\nRemarcar'} />
        </label>

        <button type="submit" disabled={salvando}
                className="w-full bg-accent text-black font-bold py-2.5 rounded-lg text-sm disabled:opacity-50">
          {salvando ? 'Enviando para a Meta…' : 'Enviar para aprovação'}
        </button>
      </form>
    </div>
  )
}
