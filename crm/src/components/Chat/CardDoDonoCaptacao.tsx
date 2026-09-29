'use client'

/**
 * O CARD DO PROPRIETÁRIO NA CAPTAÇÃO (Pedro, 29/09/2026): "um botão de
 * cadastrar imóvel pelo card do proprietário, o sistema já puxa as fotos e
 * informações, o resto nós preenchemos"; e depois: "o imóvel do cara já deve
 * aparecer lá, e dar opção de atualizar, e embaixo cadastrar imóvel".
 *
 * Os dois botões abrem a mesma janela: as fotos que ele mandou na conversa
 * (todas marcadas, dá para desmarcar) e o que a ficha da conversa leva. No
 * fim, o link do editor do site -- lá a equipe completa e escolhe a situação.
 * Ver /api/captacao/dono/[id] e nay-site-api/olx_api.py (/api/captacao/crm).
 */
import { useCallback, useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { ArrowSquareOut, CheckCircle, House, Plus, X } from '@phosphor-icons/react'
import type { FichaDoDono, ImovelDoDono } from '@/lib/nayLeitura'
import type { DonoNaLista } from '@/lib/tiposNay'

type Dados = { dono: DonoNaLista | null; imoveis: ImovelDoDono[]; ficha: FichaDoDono | null; fotos: Array<{ id: string; url: string; em: string }> }
type Alvo = { codigo: number | null; titulo: string }
type Resultado = { codigo: number; novo: boolean; usouFicha: boolean; editor: string; fotos: number; fotosFalharam: number }

const reais = (v: number | null) => (v ? v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 }) : null)

const ROTULO_DA_FICHA: Record<string, string> = {
  tipo: 'tipo', condominio: 'condomínio', bairro: 'bairro', quartos: 'quartos', suites: 'suítes', banheiros: 'banheiros',
  vagas: 'vagas', area: 'área', valor: 'valor', condominio_valor: 'taxa de condomínio', iptu: 'IPTU', mobilia: 'mobília',
  incluso: 'incluso', negocio: 'negócio', detalhes: 'detalhes',
}

function resumoDaFicha(dados: Record<string, any>): string {
  return Object.entries(dados)
    .filter(([k, v]) => ROTULO_DA_FICHA[k] && v !== null && v !== '' && String(v).toLowerCase() !== 'nao sabe')
    .map(([k, v]) => `${ROTULO_DA_FICHA[k]}: ${String(v).slice(0, 40)}`)
    .join(' · ')
}

export default function CardDoDonoCaptacao({ leadId }: { leadId: string }) {
  const [dados, setDados] = useState<Dados | null>(null)
  const [alvo, setAlvo] = useState<Alvo | null>(null)
  const [marcadas, setMarcadas] = useState<Set<string>>(new Set())
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [feito, setFeito] = useState<Resultado | null>(null)

  const ler = useCallback(async () => {
    try {
      const r = await fetch(`/api/captacao/dono/${leadId}`)
      const j = await r.json()
      if (r.ok) setDados(j)
    } catch { /* o card só não aparece */ }
  }, [leadId])
  useEffect(() => { void ler() }, [ler])

  if (!dados?.dono) return null
  const { dono, imoveis, ficha, fotos } = dados
  const fichaServe = (codigo: number | null) =>
    !!ficha && (codigo === null ? ficha.tipo !== 'atualizar' : ficha.tipo === 'atualizar' && (ficha.codigo ?? codigo) === codigo)

  const abrir = (a: Alvo) => {
    setAlvo(a); setErro(null); setFeito(null)
    setMarcadas(new Set(fotos.map((f) => f.id)))
  }
  const alternar = (id: string) => setMarcadas((m) => {
    const n = new Set(m)
    if (n.has(id)) n.delete(id); else n.add(id)
    return n
  })
  const confirmar = async () => {
    if (!alvo) return
    setEnviando(true); setErro(null)
    try {
      const r = await fetch(`/api/captacao/dono/${leadId}/imovel`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ codigo: alvo.codigo, fotos: Array.from(marcadas) }),
      })
      const j = await r.json()
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      setFeito(j)
      void ler()
    } catch (e: any) {
      setErro(e?.message || 'Não consegui.')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <section className="rounded-xl border border-[var(--chat-border)] bg-[var(--chat-bg-field)] p-3 text-left space-y-3">
      <div>
        <p className="text-[11px] font-bold tracking-wider uppercase text-[var(--chat-text-muted)]">Proprietário</p>
        <p className="text-sm font-semibold text-[var(--chat-text-primary)] truncate" title={dono.nome || ''}>{dono.nome || 'Sem nome'}</p>
      </div>

      <div className="space-y-2">
        <p className="text-[11px] font-bold tracking-wider uppercase text-[var(--chat-text-muted)]">Imóveis dele</p>
        {imoveis.length === 0 && <p className="text-xs text-[var(--chat-text-muted)]">Nenhum imóvel dele no catálogo.</p>}
        {imoveis.map((i) => (
          <div key={i.codigo} className="flex gap-2 items-start">
            <div className="w-12 h-12 rounded-lg overflow-hidden flex-shrink-0 bg-[var(--chat-bg-hover)] flex items-center justify-center">
              {i.capa ? <img src={i.capa} alt="" className="w-full h-full object-cover" loading="lazy" />
                      : <House size={20} className="text-[var(--chat-text-muted)]" />}
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[13px] font-medium text-[var(--chat-text-primary)] truncate" title={i.condominio || i.tipo || ''}>
                {i.condominio || i.tipo || `Imóvel ${i.codigo}`}
              </p>
              <p className="text-[11.5px] text-[var(--chat-text-muted)] truncate">
                #{i.codigo}{i.status ? ` · ${i.status}` : ''}{reais(i.aluguel) ? ` · ${reais(i.aluguel)}` : ''} · {i.fotos} foto{i.fotos === 1 ? '' : 's'}
                {i.daCampanha ? ' · da campanha' : ''}
              </p>
              <button type="button" onClick={() => abrir({ codigo: i.codigo, titulo: `Atualizar o #${i.codigo}${i.condominio ? ` · ${i.condominio}` : ''}` })}
                      className="mt-1 text-[12px] font-semibold px-2.5 py-1 rounded-full border border-[var(--chat-border)] text-[var(--chat-accent)] hover:bg-[var(--chat-bg-hover)]">
                Atualizar
              </button>
            </div>
          </div>
        ))}
      </div>

      {ficha && (
        <p className="text-[11.5px] text-[var(--chat-text-secondary)] leading-4">
          <span className="font-semibold">Ficha da conversa{ficha.tipo === 'novo' ? ' (imóvel novo)' : ficha.codigo ? ` (#${ficha.codigo})` : ''}:</span>{' '}
          {resumoDaFicha(ficha.dados) || 'ainda vazia'}
        </p>
      )}

      <button type="button" onClick={() => abrir({ codigo: null, titulo: 'Cadastrar imóvel novo' })}
              className="w-full flex items-center justify-center gap-1.5 text-[13px] font-semibold py-2 rounded-lg bg-[var(--chat-accent)] text-[var(--chat-bg-conversation,#fff)] hover:opacity-90">
        <Plus size={15} weight="bold" /> Cadastrar imóvel
      </button>
      <p className="text-[11px] text-[var(--chat-text-muted)] -mt-1">{fotos.length} foto{fotos.length === 1 ? '' : 's'} que ele mandou na conversa</p>

      {alvo && createPortal(
        <div className="chat-theme fixed inset-0 z-[120] flex items-center justify-center p-4 bg-black/60" onClick={() => !enviando && setAlvo(null)}>
          <div role="dialog" aria-label={alvo.titulo} onClick={(e) => e.stopPropagation()}
               className="w-full max-w-lg max-h-[88vh] flex flex-col rounded-2xl border border-[var(--chat-border)] bg-[var(--chat-bg-base)] shadow-2xl">
            <div className="flex items-start justify-between gap-3 p-4 pb-2">
              <div className="min-w-0">
                <h2 className="text-base font-bold text-[var(--chat-text-primary)] truncate">{alvo.titulo}</h2>
                <p className="text-xs text-[var(--chat-text-muted)] mt-0.5">
                  {alvo.codigo === null
                    ? `Cria um rascunho ligado a ${dono.nome || 'este proprietário'}, fora do site e da Nay.`
                    : 'Os dados da ficha entram só onde o cadastro está vazio; a situação não muda.'}
                  {' '}Depois você completa no editor.
                </p>
              </div>
              <button type="button" onClick={() => setAlvo(null)} disabled={enviando} aria-label="Fechar"
                      className="wa-fechar-foto flex-shrink-0 w-9 h-9 rounded-full flex items-center justify-center">
                <X size={20} weight="bold" />
              </button>
            </div>

            <div className="px-4 pb-2 overflow-y-auto">
              <p className="text-[12px] text-[var(--chat-text-secondary)] mb-2">
                {fichaServe(alvo.codigo) ? `Da ficha: ${resumoDaFicha(ficha!.dados) || '—'}` : 'Nenhuma ficha da conversa para este imóvel: vão só as fotos.'}
              </p>
              {fotos.length === 0 ? (
                <p className="text-[13px] text-[var(--chat-text-muted)] py-4">Ele não mandou foto nesta conversa.</p>
              ) : (
                <>
                  <p className="text-[12px] font-semibold text-[var(--chat-text-primary)] mb-1.5">
                    Fotos da conversa: {marcadas.size} de {fotos.length} marcadas
                  </p>
                  <div className="grid grid-cols-4 gap-1.5">
                    {fotos.map((f) => {
                      const on = marcadas.has(f.id)
                      return (
                        <button key={f.id} type="button" onClick={() => alternar(f.id)} aria-pressed={on}
                                className={`relative aspect-square rounded-lg overflow-hidden border-2 ${on ? 'border-[var(--chat-accent)]' : 'border-transparent opacity-45'}`}>
                          <img src={f.url} alt="" className="w-full h-full object-cover" loading="lazy" />
                          {on && <CheckCircle size={20} weight="fill" className="absolute top-1 right-1 text-white drop-shadow" />}
                        </button>
                      )
                    })}
                  </div>
                </>
              )}
            </div>

            <div className="p-4 pt-2 space-y-2">
              {erro && <p className="text-[13px] text-red-500">{erro}</p>}
              {feito ? (
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[13px] text-[var(--chat-text-primary)]">
                    <CheckCircle size={16} weight="fill" className="inline -mt-0.5 mr-1 text-emerald-500" />
                    {feito.novo ? `Rascunho #${feito.codigo} criado` : `#${feito.codigo} atualizado`} · {feito.fotos} foto{feito.fotos === 1 ? '' : 's'}
                    {feito.fotosFalharam ? ` (${feito.fotosFalharam} não foram)` : ''}
                  </span>
                  <a href={feito.editor} target="_blank" rel="noreferrer"
                     className="flex items-center gap-1 text-[13px] font-semibold px-3 py-2 rounded-lg bg-[var(--chat-accent)] text-[var(--chat-bg-conversation,#fff)]">
                    Abrir no editor <ArrowSquareOut size={14} />
                  </a>
                </div>
              ) : (
                <div className="flex justify-end gap-2">
                  <button type="button" onClick={() => setAlvo(null)} disabled={enviando}
                          className="px-3 py-2 text-[13px] rounded-lg text-[var(--chat-text-secondary)] hover:bg-[var(--chat-bg-hover)]">Cancelar</button>
                  <button type="button" onClick={confirmar} disabled={enviando}
                          className="px-3 py-2 text-[13px] font-semibold rounded-lg bg-[var(--chat-accent)] text-[var(--chat-bg-conversation,#fff)] disabled:opacity-60">
                    {enviando ? 'Enviando…' : alvo.codigo === null ? 'Cadastrar' : 'Atualizar'}
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>,
        document.body,
      )}
    </section>
  )
}
