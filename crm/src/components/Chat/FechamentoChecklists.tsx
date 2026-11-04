'use client'

/**
 * A ABA FECHAMENTO (Pedro, 30/09/2026).
 *
 * Começou como os 2 checklists preenchíveis, aluguel e venda. No mesmo dia ele
 * pediu o resto: "uma aba de modelos, a Rayssa clica em copiar e copia o modelo
 * para mandar para alguém; e uma opção de auto preenchimento: eu escolho um
 * contato que já me mandou as informações e o site auto preenche pra mim; as
 * fotos ou documentos que ele não conseguiu identificar ele abre uma lista
 * para eu identificar o que é ... e envio para o Tel tudo organizado; quero um
 * preview do documento, de poder clicar nele para abrir e checar por ali
 * mesmo; lembrando que tem documentos de corretor e do cliente".
 *
 * A tela é daqui; o banco e as rotas são da sessão nay-ia-1b
 * (/api/parceria/fechamento/{midias, midias/classificar, autopreencher, enviar}).
 * Medido por ela: só 16 de 136 mídias vêm identificadas sozinhas -- a lista
 * suspensa é o caminho principal, o automático é a exceção. Por isso "falta
 * identificar" vem PRIMEIRO na lista de documentos.
 *
 * O rascunho do checklist fica no navegador até ser enviado.
 */
import { useEffect, useMemo, useState } from 'react'
import { ArrowSquareOut, Copy, FileText, MagicWand, PaperPlaneRight, Trash, X } from '@phosphor-icons/react'
import { CHECKLISTS, type Campo, type TipoChecklist } from '@/lib/checklistFechamento'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { formatPhone } from '@/lib/utils'

type Valores = Record<string, string | boolean>
type Papel = 'inquilino' | 'comprador' | 'vendedor' | 'corretor'
type DocDoCatalogo = { chave: string; rotulo: string; papeis: Papel[]; ordem: number; exigido: boolean }
type Item = {
  activityId: string; quando: string; direcao: 'recebida' | 'enviada'
  tipo: string; mime: string | null; nomeArquivo: string | null; legenda: string | null
  url: string; thumb: string | null; bytes: number | null
  documento: { chave: string; rotulo: string } | null
  papel: Papel | null; dono: 'corretor' | 'cliente' | null
  origem: 'automatico' | 'manual' | null; motivo: string | null
}

const RASCUNHO = (t: TipoChecklist) => `crm.fechamento.rascunho.${t}`
const ROTULO_DO_PAPEL: Record<Papel, string> = { inquilino: 'Inquilino', comprador: 'Comprador', vendedor: 'Vendedor', corretor: 'Corretor' }
const PREVIEW_MAXIMO = 15 * 1024 * 1024

function ler(t: TipoChecklist): Valores {
  try { return JSON.parse(localStorage.getItem(RASCUNHO(t)) || '{}') } catch { return {} }
}
function guardar(t: TipoChecklist, v: Valores) {
  try { localStorage.setItem(RASCUNHO(t), JSON.stringify(v)) } catch { /* sem rascunho: segue */ }
}
function tamanho(bytes: number | null) {
  if (!bytes) return ''
  return bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`
}
async function copiarTexto(texto: string): Promise<boolean> {
  try { await navigator.clipboard.writeText(texto); return true } catch { /* sem permissão: tenta o jeito antigo */ }
  try {
    const t = document.createElement('textarea')
    t.value = texto; t.style.position = 'fixed'; t.style.opacity = '0'
    document.body.appendChild(t); t.select()
    const ok = document.execCommand('copy')
    document.body.removeChild(t)
    return ok
  } catch { return false }
}

/** O modelo em branco: os mesmos rótulos do checklist, porque é por "rótulo: valor" que o autopreenchimento lê a resposta. */
function modeloEmBranco(tipo: TipoChecklist): string {
  const def = CHECKLISTS[tipo]
  const linhas = [`*${def.titulo.toUpperCase()}*`, 'Preencha e devolva nesta conversa, por favor:']
  for (const s of def.secoes) {
    linhas.push('', `*${s.titulo}*`)
    for (const c of s.campos) linhas.push(c.tipo === 'marca' ? `( ) ${c.rotulo}` : `${c.rotulo}: `)
  }
  return linhas.join('\n')
}

function CampoDoChecklist({ c, valor, mudar }: { c: Campo; valor: string | boolean | undefined; mudar: (v: string | boolean) => void }) {
  if (c.tipo === 'marca') {
    return (
      <label className="flex items-start gap-2 text-sm py-1 cursor-pointer">
        <input type="checkbox" checked={valor === true} onChange={(e) => mudar(e.target.checked)} className="mt-0.5" />
        <span>{c.rotulo}</span>
      </label>
    )
  }
  const comum = {
    value: String(valor ?? ''), onChange: (e: any) => mudar(e.target.value), 'aria-label': c.rotulo,
    className: 'w-full rounded-md border px-2 py-1.5 text-sm fechamento__campo',
  }
  return (
    <label className="block text-xs py-1">
      <span className="block mb-0.5 opacity-80">{c.rotulo}</span>
      {c.tipo === 'longo' ? <textarea rows={3} {...comum} /> : <input {...comum} />}
    </label>
  )
}

/* ── Modelos: copiar e mandar ─────────────────────────────────────────────── */
function Modelos() {
  const [copiado, setCopiado] = useState<TipoChecklist | null>(null)
  return (
    <div className="grid gap-4 md:grid-cols-2">
      {(['locacao', 'venda'] as const).map((t) => {
        const texto = modeloEmBranco(t)
        return (
          <section key={t} className="rounded-lg border p-3 flex flex-col">
            <div className="flex items-center justify-between gap-2 mb-2">
              <h3 className="text-sm font-semibold">{t === 'locacao' ? 'Modelo de aluguel' : 'Modelo de venda'}</h3>
              <button type="button" className="wa-botao-principal"
                      onClick={async () => { if (await copiarTexto(texto)) { setCopiado(t); setTimeout(() => setCopiado(null), 2000) } }}>
                <Copy size={14} /> {copiado === t ? 'Copiado!' : 'Copiar'}
              </button>
            </div>
            <pre className="text-xs whitespace-pre-wrap rounded-md border p-2 overflow-y-auto max-h-[52vh] fechamento__campo">{texto}</pre>
          </section>
        )
      })}
    </div>
  )
}

/* ── DOCUMENTAÇÃO (v3, Pedro, 04/11: "troca o Fechamento por Documentação e põe lá os checklists para a pessoa copiar, e
   esses forms que tem lá deixa como checklist também, sem campos para preencher, só esses checklists modelos") ──────────
   Os mesmos itens dos checklists de aluguel e de venda (lib/checklistFechamento), cada um como um item de checklist, para
   ler e copiar. Nada é preenchido nem guardado aqui. */
function checklistParaCopiar(tipo: TipoChecklist): string {
  const def = CHECKLISTS[tipo]
  const linhas = [`*${def.titulo.toUpperCase()}*`]
  for (const s of def.secoes) {
    linhas.push('', `*${s.titulo}*`)
    for (const c of s.campos) linhas.push(`☐ ${c.rotulo}`)
  }
  return linhas.join('\n')
}

export function DocumentacaoChecklists() {
  const [copiado, setCopiado] = useState<TipoChecklist | null>(null)
  return (
    <div className="p-4 grid gap-4 md:grid-cols-2 items-start">
      {(['locacao', 'venda'] as const).map((t) => {
        const def = CHECKLISTS[t]
        return (
          <section key={t} className="rounded-xl p-4 flex flex-col gap-3" style={{ border: '1px solid var(--wa-divider)', background: 'var(--wa-panel)' }}>
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-[15px] font-medium" style={{ color: 'var(--wa-text)' }}>{t === 'locacao' ? 'Checklist de aluguel' : 'Checklist de venda'}</h3>
              <button type="button" className="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-[13px] font-medium"
                      style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}
                      onClick={async () => { if (await copiarTexto(checklistParaCopiar(t))) { setCopiado(t); setTimeout(() => setCopiado(null), 2000) } }}>
                <Copy size={14} /> {copiado === t ? 'Copiado!' : 'Copiar checklist'}
              </button>
            </div>
            {def.secoes.map((s) => (
              <div key={s.titulo}>
                <p className="text-[12px] font-medium mb-1" style={{ color: 'var(--wa-text-2)' }}>{s.titulo}</p>
                <ul className="flex flex-col gap-1">
                  {s.campos.map((c) => (
                    <li key={c.chave} className="flex items-start gap-2 text-[13px] leading-[18px]" style={{ color: 'var(--wa-text)' }}>
                      <span className="mt-[3px] w-3 h-3 rounded-[3px] flex-shrink-0" style={{ border: '1.5px solid var(--wa-text-2)' }} />
                      {c.rotulo}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </section>
        )
      })}
    </div>
  )
}

/* ── O preview: clicar no documento e conferir ali mesmo ──────────────────── */
function Preview({ item, fechar }: { item: Item; fechar: () => void }) {
  const grande = (item.bytes ?? 0) > PREVIEW_MAXIMO
  const pdf = (item.mime || '').includes('pdf') || /\.pdf$/i.test(item.nomeArquivo || '')
  return (
    <div className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4" onClick={fechar}>
      <div className="relative bg-white rounded-lg shadow-2xl w-full max-w-4xl max-h-[92dvh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-3 px-3 py-2 border-b text-sm text-black">
          <span className="font-semibold truncate">{item.documento?.rotulo || item.nomeArquivo || 'Documento'}</span>
          <span className="opacity-60 whitespace-nowrap">{tamanho(item.bytes)}</span>
          <a href={item.url} target="_blank" rel="noopener" className="ml-auto flex items-center gap-1 underline whitespace-nowrap">
            <ArrowSquareOut size={14} /> Abrir em outra aba
          </a>
          <button type="button" onClick={fechar} aria-label="Fechar"><X size={18} /></button>
        </div>
        <div className="flex-1 min-h-0 overflow-auto flex items-center justify-center bg-neutral-100">
          {grande ? (
            <p className="p-8 text-sm text-black">Arquivo grande ({tamanho(item.bytes)}). Use "Abrir em outra aba".</p>
          ) : item.tipo === 'image' ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={item.url} alt={item.nomeArquivo || 'documento'} className="max-w-full max-h-[80vh] object-contain" />
          ) : pdf ? (
            <iframe src={item.url} title={item.nomeArquivo || 'documento'} className="w-full h-[80vh]" />
          ) : item.tipo === 'video' ? (
            <video src={item.url} controls className="max-w-full max-h-[80vh]" />
          ) : item.tipo === 'audio' ? (
            <audio src={item.url} controls className="m-8" />
          ) : (
            <p className="p-8 text-sm text-black">Este tipo de arquivo não abre aqui. Use "Abrir em outra aba".</p>
          )}
        </div>
      </div>
    </div>
  )
}

/* ── Uma linha da lista de documentos ─────────────────────────────────────── */
function LinhaDoDocumento({ item, catalogo, marcado, alternar, classificar, abrir, salvando }: {
  item: Item; catalogo: DocDoCatalogo[]; marcado: boolean; salvando: boolean
  alternar: () => void; abrir: () => void
  classificar: (documento: string | null, papel: Papel | null) => void
}) {
  const doc = catalogo.find((d) => d.chave === item.documento?.chave)
  const papeis: Papel[] = doc?.papeis?.length ? doc.papeis : ['inquilino', 'comprador', 'vendedor', 'corretor']
  return (
    <li className="flex items-center gap-3 py-2 border-b last:border-b-0">
      <input type="checkbox" checked={marcado} onChange={alternar} disabled={!item.documento}
             title={item.documento ? 'Vai junto para o Tel' : 'Diga primeiro que documento é'} />
      <button type="button" onClick={abrir} title="Clique para abrir e conferir"
              className="w-14 h-14 flex-shrink-0 rounded-md border overflow-hidden flex items-center justify-center bg-neutral-100">
        {item.thumb
          // eslint-disable-next-line @next/next/no-img-element
          ? <img src={item.thumb} alt="" className="w-full h-full object-cover" loading="lazy" />
          : <FileText size={26} className="text-neutral-500" />}
      </button>
      <div className="flex-1 min-w-0">
        <button type="button" onClick={abrir} className="block max-w-full text-left text-sm font-medium truncate underline-offset-2 hover:underline">
          {item.nomeArquivo || item.legenda || (item.tipo === 'image' ? 'Foto' : 'Arquivo')}
        </button>
        <p className="text-[11px] opacity-70 truncate">
          {new Date(item.quando).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}
          {item.bytes ? ` · ${tamanho(item.bytes)}` : ''}
          {item.direcao === 'enviada' ? ' · enviado por nós' : ''}
          {item.origem === 'automatico' && item.motivo ? ` · identificado pela ${item.motivo}` : ''}
        </p>
      </div>
      <select className="rounded-md border px-2 py-1 text-xs max-w-[190px] fechamento__campo" disabled={salvando}
              value={item.documento?.chave || ''} aria-label="Que documento é"
              onChange={(e) => {
                const chave = e.target.value || null
                const novo = catalogo.find((d) => d.chave === chave)
                // o papel só continua se o documento novo aceita ele
                const papel = chave ? (item.papel && novo?.papeis.includes(item.papel) ? item.papel : novo?.papeis[0] ?? null) : null
                classificar(chave, papel)
              }}>
        <option value="">O que é este documento?</option>
        {catalogo.map((d) => <option key={d.chave} value={d.chave}>{d.rotulo}</option>)}
      </select>
      <select className="rounded-md border px-2 py-1 text-xs fechamento__campo" disabled={salvando || !item.documento}
              value={item.papel || ''} aria-label="De quem é"
              onChange={(e) => classificar(item.documento?.chave || null, (e.target.value || null) as Papel | null)}>
        <option value="">De quem?</option>
        {papeis.map((p) => <option key={p} value={p}>{ROTULO_DO_PAPEL[p]}</option>)}
      </select>
    </li>
  )
}

export default function FechamentoChecklists() {
  const [aba, setAba] = useState<'checklist' | 'modelos'>('checklist')
  const [tipo, setTipo] = useState<TipoChecklist>('locacao')
  const [valores, setValores] = useState<Valores>({})
  const [estado, setEstado] = useState<{ ok: boolean; msg: string } | null>(null)
  const [enviando, setEnviando] = useState(false)

  // o contato que já mandou as informações
  const { leads } = useLeadsContext()
  const { marcas } = useParceriaMarcas(true)
  const [busca, setBusca] = useState('')
  const [leadId, setLeadId] = useState<string | null>(null)
  const [itens, setItens] = useState<Item[]>([])
  const [catalogo, setCatalogo] = useState<DocDoCatalogo[]>([])
  const [carregando, setCarregando] = useState(false)
  const [avisoDoContato, setAvisoDoContato] = useState<string | null>(null)
  const [paraEnviar, setParaEnviar] = useState<Set<string>>(new Set())
  const [salvandoItem, setSalvandoItem] = useState<string | null>(null)
  const [previa, setPrevia] = useState<Item | null>(null)
  const [preenchendo, setPreenchendo] = useState(false)

  useEffect(() => { setValores(ler(tipo)); setEstado(null) }, [tipo])

  const daParceria = useMemo(
    () => (leads || []).filter((l: any) => getLinhaWhatsapp(l) === 'parceria' && !l.is_group),
    [leads])
  const lead = useMemo(() => daParceria.find((l: any) => l.id === leadId) ?? null, [daParceria, leadId])
  const sugestoes = useMemo(() => {
    const t = busca.trim().toLowerCase()
    const digitos = t.replace(/\D/g, '')
    const achou = (l: any) => !t
      ? marcas[l.id]?.fechamentoId != null            // sem busca: quem já está em Fechamento
      : String(l.title || '').toLowerCase().includes(t) || (digitos.length >= 4 && String(l.phone || '').includes(digitos))
    return daParceria.filter(achou).slice(0, 8)
  }, [busca, daParceria, marcas])

  const mudar = (chave: string, v: string | boolean) => {
    setValores((atual) => { const novo = { ...atual, [chave]: v }; guardar(tipo, novo); return novo })
  }

  // as mídias da conversa do contato escolhido
  useEffect(() => {
    if (!leadId) { setItens([]); setCatalogo([]); setParaEnviar(new Set()); return }
    let vivo = true
    setCarregando(true); setAvisoDoContato(null)
    fetch(`/api/parceria/fechamento/midias?lead=${encodeURIComponent(leadId)}&tipo=${tipo}`)
      .then(async (r) => { const j = await r.json().catch(() => ({})); if (!r.ok) throw new Error(j?.error || 'Não consegui ler os documentos.'); return j })
      .then((j) => {
        if (!vivo) return
        const lista: Item[] = j.itens || []
        setItens(lista)
        setCatalogo(j.catalogo || [])
        // o que já está identificado vai marcado; o resto espera a Rayssa dizer o que é
        setParaEnviar(new Set(lista.filter((i) => i.documento).map((i) => i.activityId)))
      })
      .catch((e) => { if (vivo) setAvisoDoContato(e?.message || 'Não consegui ler os documentos.') })
      .finally(() => { if (vivo) setCarregando(false) })
    return () => { vivo = false }
  }, [leadId, tipo])

  async function autopreencher() {
    if (!leadId) return
    setPreenchendo(true); setAvisoDoContato(null)
    try {
      const r = await fetch(`/api/parceria/fechamento/autopreencher?lead=${encodeURIComponent(leadId)}&tipo=${tipo}`)
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || 'Não consegui ler as mensagens.')
      const vindos: Valores = j.valores || {}
      let postos = 0
      setValores((atual) => {
        // SÓ PREENCHE O QUE ESTÁ VAZIO: o que ela já digitou vale mais que o que o site leu
        const novo = { ...atual }
        for (const [k, v] of Object.entries(vindos)) {
          const tem = novo[k] !== undefined && novo[k] !== '' && novo[k] !== false
          if (!tem) { novo[k] = v as any; postos++ }
        }
        guardar(tipo, novo)
        return novo
      })
      const rotulos = new Map(CHECKLISTS[tipo].secoes.flatMap((s) => s.campos).map((c) => [c.chave, c.rotulo]))
      const faltam = ((j.faltam || []) as string[]).map((c) => rotulos.get(c) || c)
      setAvisoDoContato(`Preenchi ${postos} campo${postos === 1 ? '' : 's'} pelo que ele mandou. Confira antes de enviar.` +
        (faltam.length ? ` Ainda falta: ${faltam.slice(0, 8).join(', ')}${faltam.length > 8 ? '…' : ''}.` : ''))
    } catch (e: any) {
      setAvisoDoContato(e?.message || 'Não consegui ler as mensagens.')
    } finally {
      setPreenchendo(false)
    }
  }

  async function classificar(item: Item, documento: string | null, papel: Papel | null) {
    setSalvandoItem(item.activityId)
    try {
      const r = await fetch('/api/parceria/fechamento/midias/classificar', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ activityId: item.activityId, documento, papel }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || !j.item) throw new Error(j?.error || 'Não gravou.')
      setItens((atual) => atual.map((i) => (i.activityId === item.activityId ? j.item : i)))
      setParaEnviar((atual) => {
        const novo = new Set(atual)
        if (j.item.documento) novo.add(item.activityId); else novo.delete(item.activityId)
        return novo
      })
    } catch (e: any) {
      setAvisoDoContato(e?.message || 'Não gravou a escolha.')
    } finally {
      setSalvandoItem(null)
    }
  }

  async function enviar() {
    setEnviando(true)
    setEstado(null)
    try {
      // com contato escolhido vai tudo junto (checklist + documentos separados); sem contato, só o checklist
      const r = await fetch(leadId ? '/api/parceria/fechamento/enviar' : '/api/parceria/fechamento/checklist', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(leadId ? { lead: leadId, tipo, valores, documentos: Array.from(paraEnviar) } : { tipo, valores }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui mandar.')
      const n = j.enviados ? `${j.enviados.corretor} do corretor e ${j.enviados.cliente} do cliente` : null
      const falhou = (j.semLink || []).length
      setEstado({
        ok: !falhou,
        msg: (j.mensagem || 'Enviado ao Tel.') + (n ? ` Documentos: ${n}.` : '') +
          (falhou ? ` ATENÇÃO: ${falhou} documento${falhou === 1 ? '' : 's'} ficou sem link e não foi.` : ''),
      })
    } catch (e: any) {
      setEstado({ ok: false, msg: e?.message || 'Não consegui mandar.' })
    } finally {
      setEnviando(false)
    }
  }

  function limpar() {
    setValores({})
    guardar(tipo, {})
    setEstado(null)
  }

  const def = CHECKLISTS[tipo]
  const semIdentificar = itens.filter((i) => !i.documento)
  const doCorretor = itens.filter((i) => i.documento && i.dono === 'corretor')
  const doCliente = itens.filter((i) => i.documento && i.dono !== 'corretor')
  const exigidosQueFaltam = catalogo.filter((d) => d.exigido && !itens.some((i) => i.documento?.chave === d.chave))
  const grupo = (titulo: string, lista: Item[], nota?: string) => lista.length > 0 && (
    <div className="mb-3">
      <h4 className="text-xs font-semibold uppercase tracking-wide opacity-80 mb-1">{titulo} ({lista.length}){nota ? ` · ${nota}` : ''}</h4>
      <ul className="rounded-lg border px-3">
        {lista.map((i) => (
          <LinhaDoDocumento key={i.activityId} item={i} catalogo={catalogo} salvando={salvandoItem === i.activityId}
            marcado={paraEnviar.has(i.activityId)}
            alternar={() => setParaEnviar((atual) => { const n = new Set(atual); if (n.has(i.activityId)) n.delete(i.activityId); else n.add(i.activityId); return n })}
            abrir={() => setPrevia(i)}
            classificar={(d, p) => classificar(i, d, p)} />
        ))}
      </ul>
    </div>
  )

  return (
    <div className="flex-1 min-h-0 overflow-y-auto p-4 fechamento">
      <div className="max-w-4xl mx-auto">
        <div className="flex items-center gap-2 mb-4" role="tablist" aria-label="Fechamento">
          <button type="button" role="tab" aria-selected={aba === 'checklist'} onClick={() => setAba('checklist')}
                  className={`wa-chip ${aba === 'checklist' ? 'wa-chip--on' : ''}`}>Checklist</button>
          <button type="button" role="tab" aria-selected={aba === 'modelos'} onClick={() => setAba('modelos')}
                  className={`wa-chip ${aba === 'modelos' ? 'wa-chip--on' : ''}`}>Modelos</button>
          <span className="mx-1 opacity-40">|</span>
          {aba === 'checklist' && (['locacao', 'venda'] as const).map((t) => (
            <button key={t} type="button" role="tab" aria-selected={tipo === t} onClick={() => setTipo(t)}
                    className={`wa-chip ${tipo === t ? 'wa-chip--on' : ''}`}>
              {t === 'locacao' ? 'Aluguel' : 'Venda'}
            </button>
          ))}
        </div>

        {aba === 'modelos' ? <Modelos /> : (
          <>
            {/* o contato que já mandou as informações */}
            <fieldset className="mb-4 rounded-lg border p-3">
              <legend className="px-1 text-sm font-semibold">Preencher pelo contato</legend>
              {lead ? (
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium">{(lead as any).title || formatPhone((lead as any).phone)}</span>
                  <span className="text-xs opacity-70">{formatPhone((lead as any).phone)}</span>
                  <button type="button" className="wa-botao-principal" onClick={autopreencher} disabled={preenchendo}>
                    <MagicWand size={14} /> {preenchendo ? 'Lendo as mensagens…' : 'Preencher sozinho'}
                  </button>
                  <button type="button" className="text-xs underline opacity-80" onClick={() => { setLeadId(null); setBusca(''); setAvisoDoContato(null) }}>trocar contato</button>
                </div>
              ) : (
                <>
                  <input className="w-full rounded-md border px-2 py-1.5 text-sm fechamento__campo" value={busca}
                         onChange={(e) => setBusca(e.target.value)} placeholder="Nome ou número de quem mandou as informações" />
                  <ul className="mt-2 flex flex-wrap gap-2">
                    {sugestoes.map((l: any) => (
                      <li key={l.id}>
                        <button type="button" className="wa-chip" onClick={() => setLeadId(l.id)}>
                          {l.title || formatPhone(l.phone)}
                        </button>
                      </li>
                    ))}
                    {!sugestoes.length && (
                      <li className="text-xs opacity-70">{busca.trim() ? 'Ninguém com esse nome ou número.' : 'Ninguém em Fechamento agora. Procure pelo nome ou número.'}</li>
                    )}
                  </ul>
                </>
              )}
              {avisoDoContato && <p className="mt-2 text-xs">{avisoDoContato}</p>}
            </fieldset>

            {/* os documentos da conversa */}
            {lead && (
              <fieldset className="mb-4 rounded-lg border p-3">
                <legend className="px-1 text-sm font-semibold">Documentos que ele mandou</legend>
                {carregando ? <p className="text-sm opacity-70">Lendo a conversa…</p>
                  : !itens.length ? <p className="text-sm opacity-70">Nenhuma foto ou arquivo nesta conversa.</p>
                  : (
                    <>
                      {exigidosQueFaltam.length > 0 && (
                        <p className="text-xs mb-2 text-amber-600">Falta chegar: {exigidosQueFaltam.map((d) => d.rotulo).join(', ')}.</p>
                      )}
                      {grupo('Falta identificar', semIdentificar, 'escolha na lista o que é cada um')}
                      {grupo('Documentos do cliente', doCliente)}
                      {grupo('Documentos do corretor', doCorretor)}
                      <p className="text-[11px] opacity-70">Marcado = vai junto para o Tel. Clique na miniatura ou no nome para abrir e conferir.</p>
                    </>
                  )}
              </fieldset>
            )}

            <h2 className="text-lg font-semibold mb-3">{def.titulo}</h2>
            {def.secoes.map((s) => (
              <fieldset key={s.titulo} className="mb-4 rounded-lg border p-3">
                <legend className="px-1 text-sm font-semibold">{s.titulo}</legend>
                <div className="grid gap-x-4 sm:grid-cols-2">
                  {s.campos.map((c) => (
                    <div key={c.chave} className={c.tipo === 'longo' || c.tipo === 'marca' ? 'sm:col-span-2' : ''}>
                      <CampoDoChecklist c={c} valor={valores[c.chave]} mudar={(v) => mudar(c.chave, v)} />
                    </div>
                  ))}
                </div>
              </fieldset>
            ))}
            <div className="flex flex-wrap items-center gap-3 pb-6">
              <button type="button" onClick={enviar} disabled={enviando} className="wa-botao-principal">
                <PaperPlaneRight size={16} />
                {enviando ? 'Enviando…' : lead ? `Enviar ao Tel com ${paraEnviar.size} documento${paraEnviar.size === 1 ? '' : 's'}` : 'Enviar ao Tel'}
              </button>
              <button type="button" onClick={limpar} className="flex items-center gap-1 text-sm opacity-80">
                <Trash size={14} /> Limpar
              </button>
              {estado && <span className={`text-sm ${estado.ok ? 'text-green-600' : 'text-red-500'}`}>{estado.msg}</span>}
            </div>
          </>
        )}
      </div>
      {previa && <Preview item={previa} fechar={() => setPrevia(null)} />}
    </div>
  )
}
