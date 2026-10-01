'use client'

/**
 * O POPUP DE CADASTRO NO CARD DA CAPTAÇÃO (Pedro, 01/10/2026):
 *
 *   "uma opção de cadastrar novo imóvel que abre um popup. Nesse popup posso
 *    puxar um botão que ele puxa automático todas as fotos que o corretor já
 *    mandou para eu ir selecionando na lista quais vão para esse novo imóvel, e
 *    as características desse imóvel, e aquela API da OLX -- os imóveis que eu
 *    cadastro por lá ficam em pré cadastro, posso puxar da lista. E sobre
 *    condomínio, quero uma lista de condomínios detalhada com os endereços para
 *    selecionar, mas se o corretor já disse eu clico em preencher automático e
 *    ele já identifica o condomínio, ou eu adiciono manualmente. E esse popup
 *    vai ter ali encima uma porcentagem que vai se preenchendo conforme eu vou
 *    adicionando informações."
 *
 * Serve para as duas coisas: CADASTRAR um imóvel novo deste corretor e ALTERAR
 * os dados de um imóvel que já é dele (o mesmo formulário, já preenchido).
 *
 * O que ele NÃO faz: pôr o imóvel no ar. Sai como Rascunho e quem publica é
 * uma pessoa, no editor do site -- o link fica aqui ao terminar.
 *
 * A porcentagem é a régua do banco (244) repetida em `pontuacaoDoCadastro` só
 * para andar enquanto se digita; ao salvar, o site devolve a de verdade.
 */
import { useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import {
  X, CheckCircle, ArrowSquareOut, MagnifyingGlass, Buildings, Sparkle, Images, Plus, CircleNotch,
} from '@phosphor-icons/react'
import { pontuacaoDoCadastro, corDaPontuacao, type CamposDoCadastro } from '@/lib/pontuacaoDoCadastro'
import type { CondominioDaLista, OpcoesDoCadastro, RascunhoParaPuxar } from '@/lib/nayLeitura'

export interface FotoDaConversa { id: string; url: string; em: string }
export interface AlvoDoCadastro {
  /** null = imóvel novo; número = alterar aquele imóvel (dele ou um pré-cadastro puxado) */
  codigo: number | null
  titulo: string
}

const MOBILIAS = ['Mobiliado', 'Semi-Mobiliado', 'Sem mobília']
const SOIS = ['Manhã', 'Tarde']
const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

/* o que o popup manda ao salvar: as mesmas chaves que a API do site conhece */
function paraSalvar(c: CamposDoCadastro): Record<string, unknown> {
  const d: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(c)) {
    if (v === undefined) continue
    if (Array.isArray(v)) { d[k] = v; continue }
    d[k] = v === null ? '' : String(v)
  }
  return d
}

function Campo({ rotulo, children, largo }: { rotulo: string; children: React.ReactNode; largo?: boolean }) {
  return (
    <label className={`flex flex-col gap-1 ${largo ? 'col-span-2' : ''}`}>
      <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-muted)]">{rotulo}</span>
      {children}
    </label>
  )
}

const classeDoCampo =
  'h-8 px-2 rounded-lg text-[13px] bg-[var(--chat-bg-field)] text-[var(--chat-text-primary)] border border-[var(--chat-border)] outline-none focus:border-[var(--chat-accent)]'

export default function CadastroDeImovel({ leadId, donoNome, temProprietario, alvo, fotos, condominiosCitados, aoFechar, aoPronto }: {
  leadId: string
  donoNome: string | null
  /** o corretor já tem proprietário no cadastro? é o que decide se o imóvel sai com dono */
  temProprietario: boolean
  alvo: AlvoDoCadastro
  fotos: FotoDaConversa[]
  condominiosCitados: Array<{ id: number; nome: string; bairro: string | null }>
  aoFechar: () => void
  aoPronto: () => void
}) {
  const [opcoes, setOpcoes] = useState<OpcoesDoCadastro | null>(null)
  const [codigo, setCodigo] = useState<number | null>(alvo.codigo)
  const [campos, setCampos] = useState<CamposDoCadastro>({})
  const [fotosJa, setFotosJa] = useState(0)
  const [temDono, setTemDono] = useState(temProprietario)
  const [marcadas, setMarcadas] = useState<Set<string>>(new Set())
  const [carregando, setCarregando] = useState(true)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [feito, setFeito] = useState<any>(null)
  const [aviso, setAviso] = useState<string | null>(null)

  const [buscaCondo, setBuscaCondo] = useState('')
  const [listaDeCondos, setListaDeCondos] = useState(false)
  const [buscaRascunho, setBuscaRascunho] = useState('')
  const [listaDeRascunhos, setListaDeRascunhos] = useState(false)
  const [novaCarac, setNovaCarac] = useState('')

  const mudar = (p: Partial<CamposDoCadastro>) => setCampos((c) => ({ ...c, ...p }))

  /* as opções (condomínios, características, pré-cadastro) -- uma vez */
  useEffect(() => {
    let vivo = true
    fetch('/api/captacao/cadastro-opcoes')
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error('não consegui ler as opções'))))
      .then((d) => { if (vivo) setOpcoes(d) })
      .catch((e) => { if (vivo) setErro(e?.message || 'não consegui ler as opções') })
    return () => { vivo = false }
  }, [])

  /* quando é "alterar", abre preenchido com o que está no banco hoje */
  useEffect(() => {
    let vivo = true
    setCarregando(true)
    setMarcadas(new Set(fotos.map((f) => f.id)))
    if (codigo === null) {
      setCampos({ cidade: 'Manaus', estado: 'AM' })
      setFotosJa(0); setTemDono(temProprietario); setCarregando(false)
      return
    }
    fetch(`/api/captacao/dono/${leadId}/imovel/${codigo}`)
      .then((r) => r.json().then((j) => (r.ok ? j : Promise.reject(new Error(j?.error || `HTTP ${r.status}`)))))
      .then((j) => {
        if (!vivo) return
        const i = j.imovel || {}
        const t = (v: any) => (v === null || v === undefined ? '' : String(v))
        setCampos({
          tipo: t(i.tipo), bairro: t(i.bairro), condominio: t(i.condominio),
          logradouro: t(i.logradouro), numero: t(i.numero), complemento: t(i.complemento),
          cidade: t(i.cidade) || 'Manaus', estado: t(i.estado) || 'AM',
          quartos: t(i.quartos), suites: t(i.suites), banheiros: t(i.banheiros),
          vagas: t(i.vagas), vagasCobertas: t(i.vagasCobertas),
          areaUtil: t(i.areaUtil), areaTotal: t(i.areaTotal),
          andar: t(i.andar), sol: t(i.sol), mobilia: t(i.mobilia),
          taxaCondominio: t(i.taxaCondominio), iptu: t(i.iptu),
          aluguel: t(i.aluguel), venda: t(i.venda),
          caracteristicas: Array.isArray(i.caracteristicas) ? i.caracteristicas.map(String) : [],
          descricao: t(i.descricao), inclusoNoAluguel: t(i.inclusoNoAluguel),
        })
        setFotosJa(Number(i.fotos || 0))
        setTemDono(!!i.temDono || temProprietario)
      })
      .catch((e) => { if (vivo) setErro(e?.message || 'não consegui ler o imóvel') })
      .finally(() => { if (vivo) setCarregando(false) })
    return () => { vivo = false }
  }, [codigo, leadId])

  /* A BARRA DE CIMA: anda a cada tecla. As fotos marcadas contam, porque vão
     junto no mesmo salvar. */
  const pont = useMemo(() => pontuacaoDoCadastro(campos, fotosJa + marcadas.size, temDono), [campos, fotosJa, marcadas, temDono])

  const condos = opcoes?.condominios || []
  const condosFiltrados = useMemo(() => {
    const q = sem(buscaCondo.trim())
    const base = q ? condos.filter((c) => sem(`${c.nome} ${c.bairro || ''} ${c.endereco || ''}`).includes(q)) : condos
    return base.slice(0, 60)
  }, [condos, buscaCondo])

  const rascunhos = opcoes?.rascunhos || []
  const rascunhosFiltrados = useMemo(() => {
    const q = sem(buscaRascunho.trim())
    const base = q ? rascunhos.filter((r) => sem(`${r.codigo} ${r.tipo} ${r.bairro} ${r.condominio} ${r.origem} ${r.dono || ''}`).includes(q)) : rascunhos
    return base.slice(0, 40)
  }, [rascunhos, buscaRascunho])

  /** O condomínio escolhido na lista preenche endereço, bairro, cidade e estado. */
  function usarCondominio(c: CondominioDaLista) {
    mudar({
      condominio: c.nome,
      bairro: campos.bairro?.trim() ? campos.bairro : (c.bairro || ''),
      logradouro: campos.logradouro?.trim() ? campos.logradouro : (c.endereco || ''),
      cidade: c.cidade || 'Manaus',
      estado: c.estado || 'AM',
    })
    setListaDeCondos(false)
    setBuscaCondo('')
    setAviso(c.endereco
      ? `${c.nome}: endereço ${c.enderecoDe === 'ficha' ? 'da ficha do condomínio' : `visto em ${c.base} imóvel${c.base === 1 ? '' : 's'} dele`}.`
      : `${c.nome}: não temos o endereço deste condomínio -- preencha a rua à mão.`)
  }

  /** "Preencher automático": o condomínio que o corretor citou na conversa. */
  function preencherAutomatico() {
    const citado = condominiosCitados[0]
    if (!citado) { setAviso('Ele não citou nenhum condomínio que esteja no cadastro. Escolha na lista ou escreva o nome.'); return }
    const c = condos.find((x) => x.id === citado.id)
    if (c) usarCondominio(c)
    else { mudar({ condominio: citado.nome, bairro: campos.bairro || citado.bairro || '' }); setAviso(`${citado.nome}, do que ele falou na conversa.`) }
  }

  /** As características do condomínio (lazer da ficha) entram nas do imóvel. */
  function usarLazerDoCondominio() {
    const c = condos.find((x) => sem(x.nome) === sem(String(campos.condominio || '')))
    const lazer = (c?.lazer || []).filter(Boolean)
    if (!lazer.length) { setAviso('Não temos as características deste condomínio na ficha.'); return }
    const juntas = Array.from(new Set([...(campos.caracteristicas || []), ...lazer]))
    mudar({ caracteristicas: juntas })
    setAviso(`${lazer.length} característica${lazer.length === 1 ? '' : 's'} do condomínio ${c!.nome}.`)
  }

  function puxarRascunho(r: RascunhoParaPuxar) {
    setListaDeRascunhos(false)
    setBuscaRascunho('')
    setFeito(null)
    setErro(null)
    setAviso(`Pré-cadastro #${r.codigo}${r.origem ? ` (${r.origem})` : ''}: o que você preencher aqui entra nele, e ele passa a ser deste corretor.`)
    setCodigo(r.codigo)   // o efeito acima recarrega os campos
  }

  const alternarFoto = (id: string) => setMarcadas((m) => {
    const n = new Set(m)
    if (n.has(id)) n.delete(id); else n.add(id)
    return n
  })

  const alternarCarac = (nome: string) => setCampos((c) => {
    const tem = (c.caracteristicas || []).includes(nome)
    return { ...c, caracteristicas: tem ? (c.caracteristicas || []).filter((x) => x !== nome) : [...(c.caracteristicas || []), nome] }
  })

  async function salvar() {
    if (salvando) return
    setSalvando(true); setErro(null)
    try {
      const r = await fetch(`/api/captacao/dono/${leadId}/imovel`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ codigo, fotos: Array.from(marcadas), dados: paraSalvar(campos) }),
      })
      const j = await r.json()
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      setFeito(j)
      aoPronto()
    } catch (e: any) {
      setErro(e?.message || 'Não consegui salvar.')
    } finally {
      setSalvando(false)
    }
  }

  const caracUsadas = campos.caracteristicas || []
  const sugeridas = (opcoes?.caracteristicas || []).slice(0, 28).map((x) => x.nome)
  const chips = Array.from(new Set([...caracUsadas, ...sugeridas]))

  return createPortal(
    <div className="chat-theme fixed inset-0 z-[120] flex items-center justify-center p-4 bg-black/60" onClick={() => !salvando && aoFechar()}>
      <div role="dialog" aria-label={alvo.titulo} onClick={(e) => e.stopPropagation()}
           className="w-full max-w-2xl max-h-[92vh] flex flex-col rounded-2xl border border-[var(--chat-border)] bg-[var(--chat-bg-base)] shadow-2xl">

        {/* ── cabeçalho e a porcentagem que vai se preenchendo ── */}
        <div className="p-4 pb-3 border-b border-[var(--chat-border)]">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <h2 className="text-base font-bold text-[var(--chat-text-primary)] truncate">
                {codigo === null ? 'Cadastrar imóvel novo' : `Imóvel #${codigo}`}
              </h2>
              <p className="text-[11.5px] text-[var(--chat-text-muted)] mt-0.5">
                {donoNome ? `de ${donoNome}` : 'deste contato'} · sai como Rascunho; quem põe no ar é você, no editor
              </p>
            </div>
            <button type="button" onClick={aoFechar} disabled={salvando} aria-label="Fechar"
                    className="wa-fechar-foto flex-shrink-0 w-9 h-9 rounded-full flex items-center justify-center">
              <X size={20} weight="bold" />
            </button>
          </div>
          <div className="mt-3 flex items-center gap-2">
            <div className="flex-1 h-2.5 rounded-full bg-[var(--chat-bg-hover)] overflow-hidden">
              <div className="h-full rounded-full transition-[width] duration-200"
                   style={{ width: `${pont.pct}%`, background: corDaPontuacao(pont.pct) }} />
            </div>
            <b className="text-[13px] tabular-nums" style={{ color: corDaPontuacao(pont.pct) }}>{pont.pct}%</b>
          </div>
          <p className="text-[11px] text-[var(--chat-text-muted)] mt-1 leading-4">
            {pont.falta.length === 0
              ? 'Cadastro completo pela régua da aba Imóveis.'
              : <>Falta: {pont.falta.join(', ')}.</>}
          </p>
        </div>

        <div className="px-4 py-3 overflow-y-auto space-y-4">
          {carregando && <p className="text-[13px] text-[var(--chat-text-muted)]">Lendo…</p>}

          {/* ── puxar um pré-cadastro (é onde a OLX deixa o que foi capturado) ── */}
          {alvo.codigo === null && (
            <section>
              <button type="button" onClick={() => setListaDeRascunhos((v) => !v)}
                      className="text-[12.5px] font-semibold px-2.5 py-1.5 rounded-full border border-[var(--chat-border)] text-[var(--chat-accent)] hover:bg-[var(--chat-bg-hover)]">
                {listaDeRascunhos ? 'Fechar a lista' : `Puxar do pré-cadastro (${rascunhos.length})`}
              </button>
              {listaDeRascunhos && (
                <div className="mt-2 rounded-xl border border-[var(--chat-border)] overflow-hidden">
                  <div className="flex items-center gap-1.5 px-2 py-1.5 border-b border-[var(--chat-border)]">
                    <MagnifyingGlass size={14} className="text-[var(--chat-text-muted)]" />
                    <input value={buscaRascunho} onChange={(e) => setBuscaRascunho(e.target.value)} placeholder="código, condomínio, bairro, OLX…"
                           className="flex-1 bg-transparent text-[13px] text-[var(--chat-text-primary)] outline-none" />
                  </div>
                  <div className="max-h-52 overflow-y-auto">
                    {rascunhosFiltrados.length === 0 && <p className="p-3 text-[12.5px] text-[var(--chat-text-muted)]">Nada aqui.</p>}
                    {rascunhosFiltrados.map((r) => (
                      <button key={r.codigo} type="button" onClick={() => puxarRascunho(r)}
                              className="w-full text-left px-3 py-2 hover:bg-[var(--chat-bg-hover)] border-b border-[var(--chat-border)] last:border-0">
                        <p className="text-[13px] text-[var(--chat-text-primary)] truncate">
                          #{r.codigo} · {r.condominio || r.tipo || 'sem nome'}
                        </p>
                        <p className="text-[11.5px] text-[var(--chat-text-muted)] truncate">
                          {[r.tipo, r.bairro, r.origem && `origem ${r.origem}`, `${r.fotos} foto${r.fotos === 1 ? '' : 's'}`,
                            r.dono && `dono: ${r.dono}`].filter(Boolean).join(' · ')}
                        </p>
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </section>
          )}

          {/* ── condomínio: lista com endereço, automático, ou à mão ── */}
          <section>
            <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-muted)] mb-1.5">Condomínio</p>
            <div className="flex flex-wrap items-center gap-1.5">
              <input value={campos.condominio ?? ''} onChange={(e) => mudar({ condominio: e.target.value })}
                     placeholder="nome do condomínio (ou deixe vazio se é imóvel de rua)"
                     className={`${classeDoCampo} flex-1 min-w-[180px]`} />
              <button type="button" onClick={() => setListaDeCondos((v) => !v)} title="Escolher na lista, com os endereços"
                      className="inline-flex items-center gap-1 text-[12.5px] font-semibold px-2.5 py-1.5 rounded-full border border-[var(--chat-border)] text-[var(--chat-text-secondary)] hover:bg-[var(--chat-bg-hover)]">
                <Buildings size={14} /> Lista ({condos.length})
              </button>
              <button type="button" onClick={preencherAutomatico} title={condominiosCitados[0] ? `Ele falou do ${condominiosCitados[0].nome}` : 'Procura na conversa o condomínio que ele citou'}
                      className="inline-flex items-center gap-1 text-[12.5px] font-semibold px-2.5 py-1.5 rounded-full border border-[var(--chat-border)] text-[var(--chat-accent)] hover:bg-[var(--chat-bg-hover)]">
                <Sparkle size={14} weight="fill" /> Preencher automático
              </button>
            </div>
            {!!condominiosCitados.length && (
              <p className="text-[11.5px] text-[var(--chat-text-muted)] mt-1">
                Na conversa ele citou: {condominiosCitados.map((c) => c.nome).join(', ')}.
              </p>
            )}
            {listaDeCondos && (
              <div className="mt-2 rounded-xl border border-[var(--chat-border)] overflow-hidden">
                <div className="flex items-center gap-1.5 px-2 py-1.5 border-b border-[var(--chat-border)]">
                  <MagnifyingGlass size={14} className="text-[var(--chat-text-muted)]" />
                  <input value={buscaCondo} onChange={(e) => setBuscaCondo(e.target.value)} placeholder="nome, bairro ou rua"
                         className="flex-1 bg-transparent text-[13px] text-[var(--chat-text-primary)] outline-none" autoFocus />
                </div>
                <div className="max-h-56 overflow-y-auto">
                  {condosFiltrados.map((c) => (
                    <button key={c.id} type="button" onClick={() => usarCondominio(c)}
                            className="w-full text-left px-3 py-2 hover:bg-[var(--chat-bg-hover)] border-b border-[var(--chat-border)] last:border-0">
                      <p className="text-[13px] text-[var(--chat-text-primary)] truncate">{c.nome}</p>
                      <p className="text-[11.5px] text-[var(--chat-text-muted)] truncate">
                        {[c.endereco, c.bairro, c.imoveis ? `${c.imoveis} imóvel${c.imoveis === 1 ? '' : 'is'} nosso${c.imoveis === 1 ? '' : 's'}` : null]
                          .filter(Boolean).join(' · ') || 'sem endereço no cadastro'}
                      </p>
                    </button>
                  ))}
                  {condosFiltrados.length === 0 && <p className="p-3 text-[12.5px] text-[var(--chat-text-muted)]">Nenhum condomínio com esse nome. Escreva à mão no campo de cima.</p>}
                </div>
              </div>
            )}
            {aviso && <p className="text-[11.5px] text-[var(--chat-accent)] mt-1.5">{aviso}</p>}
          </section>

          {/* ── os campos ── */}
          <section className="grid grid-cols-2 gap-x-3 gap-y-2.5">
            <Campo rotulo="Tipo">
              <input list="cad-tipos" value={campos.tipo ?? ''} onChange={(e) => mudar({ tipo: e.target.value })} className={classeDoCampo} placeholder="Apartamento, Casa…" />
              <datalist id="cad-tipos">{(opcoes?.tipos || []).map((t) => <option key={t} value={t} />)}</datalist>
            </Campo>
            <Campo rotulo="Bairro">
              <input list="cad-bairros" value={campos.bairro ?? ''} onChange={(e) => mudar({ bairro: e.target.value })} className={classeDoCampo} />
              <datalist id="cad-bairros">{(opcoes?.bairros || []).map((b) => <option key={b} value={b} />)}</datalist>
            </Campo>
            <Campo rotulo="Aluguel (R$)"><input value={campos.aluguel ?? ''} onChange={(e) => mudar({ aluguel: e.target.value })} className={classeDoCampo} inputMode="decimal" /></Campo>
            <Campo rotulo="Venda (R$)"><input value={campos.venda ?? ''} onChange={(e) => mudar({ venda: e.target.value })} className={classeDoCampo} inputMode="decimal" /></Campo>
            <Campo rotulo="Quartos"><input value={campos.quartos ?? ''} onChange={(e) => mudar({ quartos: e.target.value })} className={classeDoCampo} inputMode="numeric" /></Campo>
            <Campo rotulo="Suítes"><input value={campos.suites ?? ''} onChange={(e) => mudar({ suites: e.target.value })} className={classeDoCampo} inputMode="numeric" /></Campo>
            <Campo rotulo="Banheiros"><input value={campos.banheiros ?? ''} onChange={(e) => mudar({ banheiros: e.target.value })} className={classeDoCampo} inputMode="numeric" /></Campo>
            <Campo rotulo="Vagas"><input value={campos.vagas ?? ''} onChange={(e) => mudar({ vagas: e.target.value })} className={classeDoCampo} inputMode="numeric" /></Campo>
            <Campo rotulo="Vagas cobertas"><input value={campos.vagasCobertas ?? ''} onChange={(e) => mudar({ vagasCobertas: e.target.value })} className={classeDoCampo} inputMode="numeric" /></Campo>
            <Campo rotulo="Área útil (m²)"><input value={campos.areaUtil ?? ''} onChange={(e) => mudar({ areaUtil: e.target.value })} className={classeDoCampo} inputMode="decimal" /></Campo>
            <Campo rotulo="Área total (m²)"><input value={campos.areaTotal ?? ''} onChange={(e) => mudar({ areaTotal: e.target.value })} className={classeDoCampo} inputMode="decimal" /></Campo>
            <Campo rotulo="Andar"><input value={campos.andar ?? ''} onChange={(e) => mudar({ andar: e.target.value })} className={classeDoCampo} /></Campo>
            <Campo rotulo="Mobília">
              <select value={campos.mobilia ?? ''} onChange={(e) => mudar({ mobilia: e.target.value })} className={classeDoCampo}>
                <option value="">—</option>{MOBILIAS.map((m) => <option key={m} value={m}>{m}</option>)}
              </select>
            </Campo>
            <Campo rotulo="Sol">
              <select value={campos.sol ?? ''} onChange={(e) => mudar({ sol: e.target.value })} className={classeDoCampo}>
                <option value="">—</option>{SOIS.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Campo>
            <Campo rotulo="Taxa de condomínio (R$)"><input value={campos.taxaCondominio ?? ''} onChange={(e) => mudar({ taxaCondominio: e.target.value })} className={classeDoCampo} inputMode="decimal" /></Campo>
            <Campo rotulo="IPTU (R$)"><input value={campos.iptu ?? ''} onChange={(e) => mudar({ iptu: e.target.value })} className={classeDoCampo} inputMode="decimal" /></Campo>
            <Campo rotulo="Incluso no aluguel" largo>
              <input value={campos.inclusoNoAluguel ?? ''} onChange={(e) => mudar({ inclusoNoAluguel: e.target.value })} className={classeDoCampo}
                     placeholder="ex.: condomínio e IPTU" />
            </Campo>
            <Campo rotulo="Rua" largo><input value={campos.logradouro ?? ''} onChange={(e) => mudar({ logradouro: e.target.value })} className={classeDoCampo} /></Campo>
            <Campo rotulo="Número"><input value={campos.numero ?? ''} onChange={(e) => mudar({ numero: e.target.value })} className={classeDoCampo} /></Campo>
            <Campo rotulo="Complemento (torre, apto)"><input value={campos.complemento ?? ''} onChange={(e) => mudar({ complemento: e.target.value })} className={classeDoCampo} /></Campo>
            <Campo rotulo="Cidade"><input value={campos.cidade ?? ''} onChange={(e) => mudar({ cidade: e.target.value })} className={classeDoCampo} /></Campo>
            <Campo rotulo="Estado"><input value={campos.estado ?? ''} onChange={(e) => mudar({ estado: e.target.value })} className={classeDoCampo} maxLength={2} /></Campo>
            <Campo rotulo="Descrição" largo>
              <textarea value={campos.descricao ?? ''} onChange={(e) => mudar({ descricao: e.target.value })} rows={3}
                        className="px-2 py-1.5 rounded-lg text-[13px] bg-[var(--chat-bg-field)] text-[var(--chat-text-primary)] border border-[var(--chat-border)] outline-none focus:border-[var(--chat-accent)] resize-y" />
            </Campo>
          </section>

          {/* ── características ── */}
          <section>
            <div className="flex items-center justify-between gap-2 mb-1.5">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-muted)]">
                Características ({caracUsadas.length})
              </p>
              <button type="button" onClick={usarLazerDoCondominio}
                      className="text-[12px] font-semibold text-[var(--chat-accent)] hover:underline">usar as do condomínio</button>
            </div>
            <div className="flex flex-wrap gap-1.5">
              {chips.map((n) => {
                const on = caracUsadas.includes(n)
                return (
                  <button key={n} type="button" onClick={() => alternarCarac(n)} aria-pressed={on}
                          className={`text-[12px] px-2 py-1 rounded-full border ${on
                            ? 'border-[var(--chat-accent)] text-[var(--chat-accent)] bg-[var(--chat-bg-hover)]'
                            : 'border-[var(--chat-border)] text-[var(--chat-text-secondary)]'}`}>
                    {n}
                  </button>
                )
              })}
            </div>
            <form className="flex items-center gap-1.5 mt-2" onSubmit={(e) => {
              e.preventDefault()
              const n = novaCarac.trim()
              if (!n) return
              if (!caracUsadas.includes(n)) mudar({ caracteristicas: [...caracUsadas, n] })
              setNovaCarac('')
            }}>
              <input value={novaCarac} onChange={(e) => setNovaCarac(e.target.value)} placeholder="outra característica"
                     className={`${classeDoCampo} flex-1`} />
              <button type="submit" className="w-8 h-8 rounded-lg flex items-center justify-center border border-[var(--chat-border)] text-[var(--chat-text-secondary)]" aria-label="Adicionar característica">
                <Plus size={14} weight="bold" />
              </button>
            </form>
          </section>

          {/* ── as fotos que ele já mandou ── */}
          <section>
            <div className="flex items-center justify-between gap-2 mb-1.5">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-muted)]">
                <Images size={13} className="inline -mt-0.5 mr-1" />
                Fotos da conversa: {marcadas.size} de {fotos.length}
                {fotosJa > 0 && <span className="normal-case font-normal"> · o imóvel já tem {fotosJa}</span>}
              </p>
              {fotos.length > 0 && (
                <button type="button" onClick={() => setMarcadas(marcadas.size === fotos.length ? new Set() : new Set(fotos.map((f) => f.id)))}
                        className="text-[12px] font-semibold text-[var(--chat-accent)] hover:underline">
                  {marcadas.size === fotos.length ? 'desmarcar todas' : 'marcar todas'}
                </button>
              )}
            </div>
            {fotos.length === 0 ? (
              <p className="text-[12.5px] text-[var(--chat-text-muted)]">Ele não mandou foto nesta conversa.</p>
            ) : (
              <div className="grid grid-cols-6 gap-1.5">
                {fotos.map((f) => {
                  const on = marcadas.has(f.id)
                  return (
                    <button key={f.id} type="button" onClick={() => alternarFoto(f.id)} aria-pressed={on}
                            className={`relative aspect-square rounded-lg overflow-hidden border-2 ${on ? 'border-[var(--chat-accent)]' : 'border-transparent opacity-45'}`}>
                      <img src={f.url} alt="" className="w-full h-full object-cover" loading="lazy" />
                      {on && <CheckCircle size={16} weight="fill" className="absolute top-0.5 right-0.5 text-white drop-shadow" />}
                    </button>
                  )
                })}
              </div>
            )}
          </section>
        </div>

        {/* ── salvar ── */}
        <div className="p-4 pt-3 border-t border-[var(--chat-border)] space-y-2">
          {erro && <p className="text-[13px] text-red-500">{erro}</p>}
          {feito ? (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[13px] text-[var(--chat-text-primary)]">
                <CheckCircle size={16} weight="fill" className="inline -mt-0.5 mr-1 text-emerald-500" />
                {feito.novo ? `Rascunho #${feito.codigo} criado` : `#${feito.codigo} atualizado`}
                {feito.pontuacao ? ` · ${feito.pontuacao.pct}% preenchido` : ''}
                {feito.fotos ? ` · ${feito.fotos} foto${feito.fotos === 1 ? '' : 's'}` : ''}
                {feito.fotosFalharam ? ` (${feito.fotosFalharam} não foram)` : ''}
              </span>
              <a href={feito.editor} target="_blank" rel="noreferrer"
                 className="flex items-center gap-1 text-[13px] font-semibold px-3 py-2 rounded-lg bg-[var(--chat-accent)] text-[var(--chat-bg-conversation,#fff)]">
                Abrir no editor <ArrowSquareOut size={14} />
              </a>
            </div>
          ) : (
            <div className="flex items-center justify-end gap-2">
              {!temDono && <span className="text-[11.5px] text-[var(--chat-text-muted)] mr-auto">Este contato ainda não tem proprietário no cadastro: o imóvel sai sem dono.</span>}
              <button type="button" onClick={aoFechar} disabled={salvando}
                      className="px-3 py-2 text-[13px] rounded-lg text-[var(--chat-text-secondary)] hover:bg-[var(--chat-bg-hover)]">Cancelar</button>
              <button type="button" onClick={salvar} disabled={salvando || carregando}
                      className="inline-flex items-center gap-1.5 px-3.5 py-2 text-[13px] font-semibold rounded-lg bg-[var(--chat-accent)] text-[var(--chat-bg-conversation,#fff)] disabled:opacity-60">
                {salvando && <CircleNotch size={14} className="animate-spin" />}
                {salvando ? 'Salvando…' : codigo === null ? 'Cadastrar' : 'Salvar no imóvel'}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>,
    document.body,
  )
}
