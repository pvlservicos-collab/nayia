'use client'

/**
 * A ABA CHAT OLX (Pedro, 08/10/2026): "serão 2 contas, esse chat olx vai ser 2 abas, aba Conta proprietários
 * e aba Conta corretores ... quero responder o chat da olx pelo meu crm, enviar e receber mensagens".
 *
 * Em cima, as duas contas. Cada uma tem a sua faixa de estado (conectada à OLX? recebendo mensagens?), a
 * lista de conversas à esquerda e a conversa à direita, com a caixa de resposta. A conversa chega pelo webhook
 * oficial da OLX e a resposta sai por /autoservice/v1/chat/send (ver crm/docs/olx/chat-da-olx.md).
 *
 * A resposta só aparece como enviada quando a OLX aceita. Se ela recusar, o texto continua na caixa e a
 * faixa vermelha diz o motivo.
 *
 * O botão "Consultas do bot" mostra o que o bot da OLX consultou (ChatOlx.tsx, migração 309): não é conta,
 * por isso fica à parte das duas abas.
 *
 * 16/10/2026: o chat ficou igual ao da OLX (ContaOlxAba, mais abaixo; estilos .olx-* em globals.css) e as duas
 * barras de cima viraram uma (conta, Chat / Anúncios / Informações e os atalhos).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ArrowClockwise, ArrowLeft, ArrowSquareOut, CaretRight, ChatsCircle, CheckCircle, CircleNotch, DotsThreeVertical, EnvelopeSimple, House, Info,
  MagnifyingGlass, Megaphone, PaperPlaneRight, Phone, PlugsConnected, Robot, WarningCircle, X,
} from '@phosphor-icons/react'
import { CONTAS_OLX, NOME_DA_CONTA_OLX, type AnuncioOlx, type ChatOlxNaLista, type ContaOlx, type EstadoDaContaOlx, type MensagemOlx, type PainelDosAnunciosOlx } from '@/lib/olxChatTipos'
import ChatOlx from './ChatOlx'

type Visao = ContaOlx | 'bot'
/** o menu de dentro de cada conta (Pedro, 13/10/2026: "o chat, e os anúncios e todas as informações, em uma tab lá
 *  em cima como se fosse um menu próprio dentro daquela aba") */
type Secao = 'chat' | 'anuncios' | 'info'
interface DadosDaConta {
  estado: EstadoDaContaOlx; anuncios: AnuncioOlx[]; daOlx: 'ok' | 'sem_conta' | 'falhou'; aviso: string | null
  painel: PainelDosAnunciosOlx | null
  aplicativo: { redirectUri: string; escopos: string; cadastrado: boolean }
}

const FUSO = 'America/Manaus'
const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
const diaDe = (iso: string) => new Date(iso).toLocaleDateString('en-CA', { timeZone: FUSO })
const horaDe = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' })
function quandoCurto(iso: string | null) {
  if (!iso) return ''
  return diaDe(iso) === diaDe(new Date().toISOString())
    ? horaDe(iso)
    : new Date(iso).toLocaleDateString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit' })
}
const quandoInteiro = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
const nomeDe = (c: ChatOlxNaLista) => c.nome || 'Sem nome'
/** o anúncio na OLX pelo identificador (o formato que a própria OLX usa nas notificações dela) */
const linkDoAnuncio = (listId: string | null) => (listId && /^\d{5,}$/.test(listId) ? `https://www.olx.com.br/vi/${listId}.htm` : null)

async function pedir<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, init)
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j?.error || j?.erro || `Erro ${r.status}`)
  return j as T
}

/* ── a faixa de estado da conta ── */
function EstadoDaConta({ conta, estado, aoLigar, ligando }: {
  conta: ContaOlx; estado: EstadoDaContaOlx | null; aoLigar: () => void; ligando: boolean
}) {
  if (!estado) return null
  const nome = NOME_DA_CONTA_OLX[conta].toLowerCase()
  const linha = 'px-4 py-2 text-[13px] flex flex-wrap items-center gap-x-3 gap-y-1.5'
  // tudo certo: nada em cima do chat, como na OLX (quem é a conta e desde quando está em Informações)
  if (estado.conectada && estado.webhookAtivo) return null
  return (
    <div className={linha} style={{ background: '#FEF3C7', color: '#78350F' }}>
      <WarningCircle size={16} weight="fill" />
      {!estado.aplicativoCadastrado ? (
        <span className="flex-1 min-w-[220px]">
          Falta cadastrar no servidor o aplicativo da OLX (client_id e client_secret). Sem isso não dá para conectar a {nome}.
        </span>
      ) : !estado.conectada ? (
        <>
          <span className="flex-1 min-w-[220px]">
            A {nome} ainda não está conectada à OLX. Antes de clicar, entre na OLX <b>com esta conta</b> neste navegador: vale a conta que estiver aberta lá.
          </span>
          <a href={`/api/olx/conectar?conta=${conta}`} className="wa-chip wa-chip--on inline-flex items-center gap-1.5">
            <PlugsConnected size={15} /> Conectar a conta
          </a>
        </>
      ) : (
        <>
          <span className="flex-1 min-w-[220px]">
            A conta está conectada, mas a OLX não ligou o recebimento das mensagens{estado.webhookResposta ? ` (${estado.webhookResposta})` : ''}.
          </span>
          <button type="button" disabled={ligando} onClick={aoLigar} className="wa-chip wa-chip--on inline-flex items-center gap-1.5">
            {ligando ? <CircleNotch size={15} className="animate-spin" /> : <PlugsConnected size={15} />} Ligar o recebimento
          </button>
        </>
      )}
    </div>
  )
}

/* a situação do anúncio, como a OLX devolve na lista (conferido com a conta conectada em 13/10) */
const SITUACAO_OLX: Record<string, string> = {
  published: 'publicado', deleted: 'excluído', expired: 'expirado', pending_pay: 'aguardando pagamento', pending: 'em análise',
  queue: 'na fila', refused: 'recusado', hidden: 'oculto', paused: 'pausado', accepted: 'aceito', error: 'com erro',
}
const situacaoOlx = (s: string | null) => (s ? SITUACAO_OLX[s] || s : null)

/* ── a publicação automática (Pedro, 13/10/2026: "quero fazer tudo no automático, tanto subir anúncio, quanto responder") ──
   Quem sobe os anúncios é o serviço nay-olx, do cadastro: imóvel nosso, Disponível, no site, com CEP e foto. Aqui se
   liga e desliga, se escolhe a conta e o teto, e se vê o que está pronto, o que falta em cada imóvel e o que já subiu. */
const ESTADO_NOSSO: Record<string, [string, string]> = {
  enviado: ['aguardando a OLX', '#92400E'], publicado: ['no ar', '#166534'], recusado: ['recusado pela OLX', '#991B1B'],
  erro: ['falhou', '#991B1B'], removendo: ['saindo', '#92400E'], removido: ['removido', '#475569'],
}
const dinheiro = (v: number | null) => (v == null ? '' : `R$ ${Number(v).toLocaleString('pt-BR')}`)

function PublicacaoAutomatica({ painel, aoMudar }: { painel: PainelDosAnunciosOlx; aoMudar: (p: PainelDosAnunciosOlx) => void }) {
  const cfg = painel.config || {}
  const n = painel.contagem
  const [gravando, setGravando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [teto, setTeto] = useState(cfg.teto || '')
  const [aberto, setAberto] = useState<'falta' | 'proximos' | 'nossos' | null>(null)
  useEffect(() => { setTeto(cfg.teto || '') }, [cfg.teto])
  const ligada = cfg.publicar === 'sim'
  const semPermissao = cfg.permissao === 'sem_permissao'

  async function gravar(chave: string, valor: string) {
    setGravando(true); setErro(null)
    try {
      const r = await pedir<{ painel: PainelDosAnunciosOlx }>('/api/olx/anuncios', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chave, valor }),
      })
      aoMudar(r.painel)
    } catch (e: any) { setErro(e.message) } finally { setGravando(false) }
  }
  function ligarOuDesligar() {
    if (ligada) return void gravar('publicar', 'nao')
    const quantos = Math.min(Number(cfg.teto || 0), n.prontos)
    if (!window.confirm(`Ligar a publicação automática? Os anúncios sobem sozinhos na OLX pela ${NOME_DA_CONTA_OLX[cfg.conta_que_publica as ContaOlx] || 'conta escolhida'}, ` +
      `até ${cfg.teto} ao mesmo tempo (${quantos} agora), e saem quando o imóvel deixa de estar Disponível.`)) return
    void gravar('publicar', 'sim')
  }
  const numero = (rotulo: string, v: number, cor?: string) => (
    <div className="rounded-lg px-3 py-2 min-w-[104px]" style={{ background: 'var(--wa-app)', border: '1px solid var(--wa-divider)' }}>
      <p className="text-[20px] font-bold leading-tight" style={{ color: cor || 'var(--wa-text)' }}>{v}</p>
      <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{rotulo}</p>
    </div>
  )
  const dobra = (k: 'falta' | 'proximos' | 'nossos', rotulo: string, quantos: number) => quantos > 0 && (
    <button type="button" onClick={() => setAberto(aberto === k ? null : k)} className={`wa-chip ${aberto === k ? 'wa-chip--on' : ''}`}>{rotulo} ({quantos})</button>
  )

  return (
    <section className="rounded-xl p-3 mb-3 flex flex-col gap-2.5" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="text-[15px] font-semibold mr-1" style={{ color: 'var(--wa-text)' }}>Publicação automática</h3>
        <span className="text-[12.5px] font-bold rounded-full px-2.5 py-0.5" style={{ background: ligada ? '#DCFCE7' : '#E2E8F0', color: ligada ? '#166534' : '#334155' }}>
          {ligada ? 'LIGADA' : 'DESLIGADA'}
        </span>
        <button type="button" disabled={gravando || (!ligada && !cfg.conta_que_publica)} onClick={ligarOuDesligar}
                className={`wa-chip ml-auto inline-flex items-center gap-1.5 ${ligada ? '' : 'wa-chip--on'} disabled:opacity-50`}
                title={!ligada && !cfg.conta_que_publica ? 'Escolha antes a conta que publica' : undefined}>
          {gravando ? <CircleNotch size={15} className="animate-spin" /> : <Megaphone size={15} />} {ligada ? 'Desligar' : 'Ligar a publicação'}
        </button>
      </div>
      {semPermissao && (
        <div className="rounded-lg px-3 py-2 text-[13px]" style={{ background: '#FEF3C7', color: '#78350F' }}>
          <b>A OLX ainda não deixa esta conta publicar pela integração.</b> Ela respondeu &quot;sem permissão&quot;{cfg.permissao_em ? ` em ${cfg.permissao_em}` : ''}:
          a conta precisa de um plano profissional habilitado para integração de anúncios. Enquanto isso, mesmo ligada, nada sobe;
          o serviço pergunta de novo a cada 6 horas e começa sozinho quando a OLX liberar.
        </div>
      )}
      {cfg.permissao && !['ok', 'sem_permissao', ''].includes(cfg.permissao) && (
        <div className="rounded-lg px-3 py-2 text-[13px]" style={{ background: '#FEF3C7', color: '#78350F' }}>{cfg.permissao_detalhe || cfg.permissao}</div>
      )}
      {erro && <div className="rounded-lg px-3 py-2 text-[13px]" style={{ background: '#FEE2E2', color: '#7F1D1D' }}>{erro}</div>}
      <div className="flex flex-wrap gap-2">
        {numero('prontos para subir', n.prontos, 'var(--wa-green)')}
        {numero('faltando dado', n.faltando_dados, n.faltando_dados ? '#B45309' : undefined)}
        {numero('aguardando a OLX', n.enviados)}
        {numero('no ar', n.publicados, n.publicados ? '#166534' : undefined)}
        {numero('recusados', n.recusados, n.recusados ? '#991B1B' : undefined)}
      </div>
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-[13px]" style={{ color: 'var(--wa-text-2)' }}>
        <label className="inline-flex items-center gap-1.5">Conta que publica
          <select value={cfg.conta_que_publica || ''} disabled={gravando} onChange={(e) => void gravar('conta_que_publica', e.target.value)}
                  className="rounded-md px-2 py-1 text-[13px]" style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}>
            <option value="">(escolha)</option>
            {CONTAS_OLX.map((c) => <option key={c} value={c}>{NOME_DA_CONTA_OLX[c]}</option>)}
          </select>
        </label>
        <label className="inline-flex items-center gap-1.5">No máximo
          <input value={teto} onChange={(e) => setTeto(e.target.value.replace(/\D/g, '').slice(0, 4))} onBlur={() => { if (teto && teto !== cfg.teto) void gravar('teto', teto) }}
                 onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} inputMode="numeric" aria-label="Máximo de anúncios ao mesmo tempo"
                 className="w-[64px] rounded-md px-2 py-1 text-[13px]" style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }} />
          anúncios ao mesmo tempo
        </label>
        <label className="inline-flex items-center gap-1.5 cursor-pointer">
          <input type="checkbox" checked={cfg.mostrar_telefone === 'sim'} disabled={gravando} onChange={(e) => void gravar('mostrar_telefone', e.target.checked ? 'sim' : 'nao')} />
          Mostrar o telefone no anúncio{cfg.telefone ? ` (${cfg.telefone})` : ''}
        </label>
      </div>
      <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
        Sobe sozinho o imóvel nosso que está Disponível e no site, com CEP e foto; atualiza quando o cadastro muda e sai quando o imóvel deixa de estar Disponível.
        Imóvel de parceiro nunca sobe. Com o telefone oculto, o contato vem pelo chat, que cai aqui.
      </p>
      <div className="flex flex-wrap gap-1.5">
        {dobra('proximos', 'Próximos a subir', painel.proximos.length)}
        {dobra('falta', 'O que falta', painel.falta.length)}
        {dobra('nossos', 'Os que já subiram', painel.nossos.length)}
      </div>
      {aberto === 'proximos' && (
        <ul className="text-[13px] flex flex-col gap-1 max-h-[260px] overflow-y-auto wa-rolagem" style={{ color: 'var(--wa-text)' }}>
          {painel.proximos.map((x) => (
            <li key={`${x.codigo}${x.negocio}`}>
              <a href={`/${x.codigo}`} target="_blank" rel="noopener noreferrer" className="underline">#{x.codigo}</a> {x.titulo}
              <span style={{ color: 'var(--wa-text-2)' }}> · {dinheiro(x.preco)} · {x.fotos} foto{x.fotos === 1 ? '' : 's'}</span>
            </li>
          ))}
        </ul>
      )}
      {aberto === 'falta' && (
        <ul className="text-[13px] flex flex-col gap-1.5 max-h-[260px] overflow-y-auto wa-rolagem" style={{ color: 'var(--wa-text)' }}>
          {painel.falta.map((f) => (
            <li key={f.motivo}><b>{f.n}</b> {f.motivo}:{' '}
              {f.codigos.map((c) => <a key={c} href={`/${c}`} target="_blank" rel="noopener noreferrer" className="underline mr-1.5">#{c}</a>)}
              {f.n > f.codigos.length ? '…' : ''}
            </li>
          ))}
        </ul>
      )}
      {aberto === 'nossos' && (
        <ul className="text-[13px] flex flex-col gap-1.5 max-h-[300px] overflow-y-auto wa-rolagem" style={{ color: 'var(--wa-text)' }}>
          {painel.nossos.map((x) => {
            const [rotulo, cor] = ESTADO_NOSSO[x.estado] || [x.estado, '#475569']
            return (
              <li key={x.ad_id}>
                <span className="font-bold" style={{ color: cor }}>{rotulo}</span>{' '}
                <a href={`/${x.codigo}`} target="_blank" rel="noopener noreferrer" className="underline">#{x.codigo}</a> {x.titulo || x.ad_id}
                <span style={{ color: 'var(--wa-text-2)' }}>{x.preco ? ` · ${dinheiro(x.preco)}` : ''}{x.olx_status ? ` · na OLX: ${situacaoOlx(x.olx_status)}` : ''}{x.mensagem ? ` · ${x.mensagem}` : ''}</span>
                {x.url && <a href={x.url} target="_blank" rel="noopener noreferrer" className="underline ml-1.5">abrir</a>}
              </li>
            )
          })}
        </ul>
      )}
    </section>
  )
}

/* ── AS MÉTRICAS DOS ANÚNCIOS (Pedro, 14/10/2026: "uma lista com os anúncios e várias colunas, com os dados que a OLX
   compartilha, número de mensagens, número de visualizações ... a lista vai se atualizando por número maior de mensagens
   no topo, mas eu clicando em cada coluna consigo ver ordenado por esse dado") ──
   Os números vêm de `crm_olx_metricas` (migração 369): o chat que cai no CRM e os contatos que a OLX avisa (WhatsApp,
   telefone, chat). VISUALIZAÇÕES a OLX não fornece pela integração: nenhuma rota da documentação traz esse número. */
type LinhaMetrica = {
  list_id: string; codigo: number | null; negocio: string | null; situacao: string | null; url: string | null; titulo: string | null
  preco: number | null; dias_no_ar: number | null; conversas: number; recebidas: number; enviadas: number; da_nay: number
  sem_resposta: number; recebidas_7d: number; ultima_do_cliente: string | null; leads: number; leads_whatsapp: number
  leads_telefone: number; leads_chat: number; ultimo_lead: string | null; bairro: string | null
}
type Plano = { conta: string; plano: { nome: string; total: number; usados: number; livres: number; renova_em: string | null } }
const COLUNAS: { k: keyof LinhaMetrica; rotulo: string; dica: string; numero?: boolean }[] = [
  { k: 'codigo', rotulo: 'Imóvel', dica: 'Código e título do anúncio' },
  { k: 'preco', rotulo: 'Valor', dica: 'Preço no anúncio', numero: true },
  { k: 'dias_no_ar', rotulo: 'Dias no ar', dica: 'Dias desde que a OLX publicou', numero: true },
  { k: 'recebidas', rotulo: 'Mensagens', dica: 'Mensagens de clientes no chat do anúncio', numero: true },
  { k: 'recebidas_7d', rotulo: '7 dias', dica: 'Mensagens de clientes nos últimos 7 dias', numero: true },
  { k: 'conversas', rotulo: 'Conversas', dica: 'Pessoas diferentes que escreveram', numero: true },
  { k: 'sem_resposta', rotulo: 'Sem resposta', dica: 'Conversas em que a última mensagem é do cliente', numero: true },
  { k: 'enviadas', rotulo: 'Respostas', dica: 'Mensagens nossas (equipe e Nay)', numero: true },
  { k: 'leads', rotulo: 'Contatos', dica: 'Todos os contatos que a OLX avisou (chat, WhatsApp, telefone, financiamento)', numero: true },
  { k: 'leads_whatsapp', rotulo: 'WhatsApp', dica: 'Cliques no WhatsApp do anúncio', numero: true },
  { k: 'leads_telefone', rotulo: 'Telefone', dica: 'Pedidos para ver o telefone', numero: true },
  { k: 'leads_chat', rotulo: 'Chat', dica: 'Contatos pelo chat que a OLX contou', numero: true },
  { k: 'ultima_do_cliente', rotulo: 'Última msg', dica: 'Quando o cliente escreveu por último' },
  { k: 'situacao', rotulo: 'Na OLX', dica: 'Situação do anúncio na OLX' },
]

function MetricasOlx() {
  const [linhas, setLinhas] = useState<LinhaMetrica[] | null>(null)
  const [planos, setPlanos] = useState<Plano[]>([])
  const [leadsLigados, setLeadsLigados] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [ordem, setOrdem] = useState<{ k: keyof LinhaMetrica; desc: boolean }>({ k: 'recebidas', desc: true })
  const [aberta, setAberta] = useState(true)
  const carregar = useCallback(() => {
    pedir<{ linhas: LinhaMetrica[]; planos: Plano[]; leads_ligados: boolean }>('/api/olx/metricas')
      .then((d) => { setLinhas(d.linhas); setPlanos(d.planos || []); setLeadsLigados(!!d.leads_ligados); setErro(null) })
      .catch((e) => setErro(e.message))
  }, [])
  // a lista se atualiza sozinha (a cada minuto)
  useEffect(() => { carregar(); const t = setInterval(carregar, 60_000); return () => clearInterval(t) }, [carregar])

  const ordenadas = useMemo(() => {
    const v = (l: LinhaMetrica) => {
      const x = l[ordem.k]
      if (ordem.k === 'ultima_do_cliente') return x ? Date.parse(String(x)) : -Infinity
      if (typeof x === 'number') return x
      if (x == null) return ordem.desc ? -Infinity : Infinity
      return String(x).toLowerCase()
    }
    return [...(linhas || [])].sort((a, b) => {
      const va = v(a), vb = v(b)
      const c = va < vb ? -1 : va > vb ? 1 : 0
      // empate: quem tem mais mensagens fica em cima
      return (ordem.desc ? -c : c) || (b.recebidas - a.recebidas)
    })
  }, [linhas, ordem])
  const total = (k: keyof LinhaMetrica) => (linhas || []).reduce((n, l) => n + (Number(l[k]) || 0), 0)
  const celula = (l: LinhaMetrica, k: keyof LinhaMetrica) => {
    const x = l[k]
    if (k === 'codigo') {
      return (
        <span className="flex flex-col min-w-[220px] max-w-[340px]">
          <span className="truncate" style={{ color: 'var(--wa-text)' }} title={l.titulo || ''}>
            {l.codigo ? <a href={`/${l.codigo}`} target="_blank" rel="noopener noreferrer" className="underline mr-1">#{l.codigo}</a> : null}
            {l.titulo || `Anúncio ${l.list_id}`}
          </span>
          {l.url && <a href={l.url} target="_blank" rel="noopener noreferrer" className="text-[11.5px] underline" style={{ color: 'var(--wa-text-2)' }}>abrir na OLX</a>}
        </span>
      )
    }
    if (k === 'preco') return x == null ? '—' : dinheiro(Number(x))
    if (k === 'ultima_do_cliente') return x ? quandoCurto(String(x)) : '—'
    if (k === 'situacao') return situacaoOlx(x as string | null) || '—'
    if (k === 'sem_resposta' && Number(x) > 0) return <b style={{ color: '#B45309' }}>{String(x)}</b>
    return x == null ? '—' : String(x)
  }

  return (
    <section className="rounded-xl p-3 mb-3 flex flex-col gap-2" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
      <div className="flex flex-wrap items-center gap-2">
        <button type="button" onClick={() => setAberta((v) => !v)} className="text-[15px] font-semibold" style={{ color: 'var(--wa-text)' }}>
          {aberta ? '▾' : '▸'} Métricas dos anúncios
        </button>
        {linhas && <span className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
          {linhas.length} anúncios · {total('recebidas')} mensagens · {total('leads')} contatos · {total('sem_resposta')} sem resposta
        </span>}
        <button type="button" className="wa-icone-btn ml-auto" onClick={carregar} title="Atualizar agora"><ArrowClockwise size={18} /></button>
      </div>
      {planos.map((p) => (
        <p key={p.conta} className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
          <b style={{ color: 'var(--wa-text)' }}>{p.plano.nome}</b> ({NOME_DA_CONTA_OLX[p.conta as ContaOlx] || p.conta}): {p.plano.usados} de {p.plano.total} anúncios usados,
          {' '}<b style={{ color: 'var(--wa-green)' }}>{p.plano.livres} livres</b>{p.plano.renova_em ? `, renova em ${new Date(p.plano.renova_em).toLocaleDateString('pt-BR', { timeZone: FUSO })}` : ''}
        </p>
      ))}
      {aberta && (
        <>
          <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
            Clique no nome de uma coluna para ordenar por ela (clique de novo para inverter). Visualizações a OLX não fornece pela integração.
            {!leadsLigados && ' Os contatos por WhatsApp e telefone ainda não estão chegando.'}
          </p>
          {erro && <p className="text-[13px] text-red-500">{erro}</p>}
          {!linhas && !erro && <p className="text-[13px] flex items-center gap-2" style={{ color: 'var(--wa-text-2)' }}><CircleNotch size={16} className="animate-spin" /> Lendo…</p>}
          {linhas && (
            <div className="overflow-auto wa-rolagem max-h-[60vh] rounded-lg" style={{ border: '1px solid var(--wa-divider)' }}>
              <table className="w-full text-[13px] border-collapse">
                <thead className="sticky top-0 z-10" style={{ background: 'var(--wa-app)' }}>
                  <tr>
                    {COLUNAS.map((c) => (
                      <th key={c.k} title={c.dica} onClick={() => setOrdem((o) => ({ k: c.k, desc: o.k === c.k ? !o.desc : true }))}
                          className={`px-2 py-2 font-semibold cursor-pointer select-none whitespace-nowrap ${c.numero ? 'text-right' : 'text-left'}`}
                          style={{ color: ordem.k === c.k ? 'var(--wa-green)' : 'var(--wa-text-2)', borderBottom: '1px solid var(--wa-divider)' }}>
                        {c.rotulo}{ordem.k === c.k ? (ordem.desc ? ' ↓' : ' ↑') : ''}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {ordenadas.map((l) => (
                    <tr key={l.list_id} style={{ borderBottom: '1px solid var(--wa-divider)' }}>
                      {COLUNAS.map((c) => (
                        <td key={c.k} className={`px-2 py-1.5 align-top ${c.numero ? 'text-right tabular-nums' : ''}`} style={{ color: 'var(--wa-text)' }}>
                          {celula(l, c.k)}
                        </td>
                      ))}
                    </tr>
                  ))}
                  {!ordenadas.length && <tr><td colSpan={COLUNAS.length} className="px-2 py-4 text-center" style={{ color: 'var(--wa-text-2)' }}>Nenhum anúncio ainda.</td></tr>}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </section>
  )
}

/* ── os anúncios da conta ── */
function AnunciosDaConta({ conta, aoVerConversas }: { conta: ContaOlx; aoVerConversas: (listId: string) => void }) {
  const [d, setD] = useState<DadosDaConta | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  // a OLX devolve também os anúncios excluídos (a maior parte da lista): ficam escondidos até pedir
  const [comExcluidos, setComExcluidos] = useState(false)
  const carregar = useCallback(() => {
    pedir<DadosDaConta>(`/api/olx/anuncios?conta=${conta}`).then((x) => { setD(x); setErro(null) }).catch((e) => setErro(e.message))
  }, [conta])
  useEffect(() => { carregar() }, [carregar])
  const excluidos = useMemo(() => (d?.anuncios || []).filter((a) => a.situacao === 'deleted' && !a.conversas).length, [d])
  const lista = useMemo(() => {
    const q = sem(busca.trim())
    const ordem = (a: AnuncioOlx) => (a.situacao === 'published' ? 0 : a.situacao === 'deleted' ? 2 : 1)
    return (d?.anuncios || [])
      .filter((a) => comExcluidos || a.situacao !== 'deleted' || a.conversas > 0)
      .filter((a) => !q || sem([a.listId, a.titulo, a.situacao, situacaoOlx(a.situacao)].filter(Boolean).join(' ')).includes(q))
      .sort((a, b) => ordem(a) - ordem(b))
  }, [d, busca, comExcluidos])

  return (
    <div className="flex-1 min-h-0 flex flex-col" style={{ background: 'var(--wa-conv-bg)' }}>
      <div className="px-3 py-2 flex items-center gap-2" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        <label className="wa-busca flex-1 max-w-[420px]"><MagnifyingGlass size={18} />
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Procurar anúncio (código ou título)" aria-label="Procurar anúncio" />
          {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} /></button>}
        </label>
        <span className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{d ? `${lista.length} anúncio${lista.length === 1 ? '' : 's'}` : ''}</span>
        {excluidos > 0 && (
          <button type="button" onClick={() => setComExcluidos((v) => !v)} className={`wa-chip ${comExcluidos ? 'wa-chip--on' : ''}`}>
            {comExcluidos ? 'Esconder os excluídos' : `Mostrar os ${excluidos} excluídos`}
          </button>
        )}
        <button type="button" className="wa-icone-btn ml-auto" onClick={carregar} title="Atualizar agora"><ArrowClockwise size={20} /></button>
      </div>
      {d?.aviso && <div className="px-4 py-2 text-[13px]" style={{ background: '#FEF3C7', color: '#78350F' }}>{d.aviso} Abaixo, os anúncios que conhecemos pelas conversas.</div>}
      {d && d.daOlx === 'sem_conta' && (
        <div className="px-4 py-2 text-[13px]" style={{ background: '#FEF3C7', color: '#78350F' }}>
          A conta ainda não está conectada à OLX: a lista dos anúncios publicados aparece depois de conectar (menu Informações).
        </div>
      )}
      <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-3">
        <MetricasOlx />
        {d?.painel && <PublicacaoAutomatica painel={d.painel} aoMudar={(p) => setD((v) => (v ? { ...v, painel: p } : v))} />}
        {d && <h3 className="text-[13px] font-bold uppercase tracking-wide mb-2" style={{ color: 'var(--wa-text-2)' }}>Na conta da OLX</h3>}
        {!d && !erro && <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}><CircleNotch size={18} className="animate-spin" /> Lendo os anúncios…</p>}
        {erro && <p className="text-center text-[14px] mt-10 text-red-500">{erro}</p>}
        {d && !lista.length && (
          <p className="text-center text-[14px] mt-10" style={{ color: 'var(--wa-text-2)' }}>
            {d.anuncios.length ? 'Nenhum anúncio assim.' : 'Nenhum anúncio para mostrar ainda.'}
          </p>
        )}
        <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
          {lista.map((a) => {
            const link = linkDoAnuncio(a.listId)
            return (
              <div key={a.listId} className="rounded-xl p-3 flex flex-col gap-1.5" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
                <div className="flex items-start gap-2">
                  <Megaphone size={18} className="mt-0.5 flex-shrink-0" style={{ color: 'var(--wa-icon)' }} />
                  <div className="flex-1 min-w-0">
                    <p className="text-[14.5px] font-semibold break-words" style={{ color: 'var(--wa-text)' }}>{a.titulo || `Anúncio ${a.listId}`}</p>
                    <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
                      código {a.listId}{a.situacao ? ` · ${situacaoOlx(a.situacao)}` : ''}{a.daOlx ? '' : ' · só pelas conversas'}
                    </p>
                  </div>
                  {a.naoLidas > 0 && <span className="wa-badge">{a.naoLidas > 99 ? '99+' : a.naoLidas}</span>}
                </div>
                <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>
                  {a.conversas ? `${a.conversas} conversa${a.conversas === 1 ? '' : 's'}${a.ultimaEm ? ` · última mensagem ${quandoInteiro(a.ultimaEm)}` : ''}` : 'Nenhuma conversa neste anúncio ainda'}
                </p>
                <div className="flex flex-wrap gap-1.5 mt-1">
                  {a.conversas > 0 && (
                    <button type="button" onClick={() => aoVerConversas(a.listId)} className="wa-chip wa-chip--on inline-flex items-center gap-1.5"><ChatsCircle size={15} /> Ver as conversas</button>
                  )}
                  {link && <a href={link} target="_blank" rel="noopener noreferrer" className="wa-chip inline-flex items-center gap-1.5"><ArrowSquareOut size={15} /> Abrir na OLX</a>}
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}

/* ── as informações da conta e da ligação com a OLX ── */
function InformacoesDaConta({ conta, aoLigar, ligando }: { conta: ContaOlx; aoLigar: () => void; ligando: boolean }) {
  const [d, setD] = useState<DadosDaConta | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const carregar = useCallback(() => {
    pedir<DadosDaConta>(`/api/olx/anuncios?conta=${conta}`).then((x) => { setD(x); setErro(null) }).catch((e) => setErro(e.message))
  }, [conta])
  useEffect(() => { carregar() }, [carregar, ligando])
  const e = d?.estado
  const linha = (rotulo: string, valor: React.ReactNode) => (
    <div className="flex flex-wrap gap-x-3 gap-y-0.5 py-2" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
      <span className="w-[210px] flex-shrink-0 text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{rotulo}</span>
      <span className="flex-1 min-w-[200px] text-[14px] break-words" style={{ color: 'var(--wa-text)' }}>{valor}</span>
    </div>
  )
  const sim = (v: boolean, s: string, n: string) => (
    <span className="inline-flex items-center gap-1.5">
      {v ? <CheckCircle size={16} weight="fill" style={{ color: 'var(--wa-green)' }} /> : <WarningCircle size={16} weight="fill" style={{ color: '#B45309' }} />}{v ? s : n}
    </span>
  )
  return (
    <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-4" style={{ background: 'var(--wa-conv-bg)' }}>
      {!d && !erro && <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}><CircleNotch size={18} className="animate-spin" /> Lendo…</p>}
      {erro && <p className="text-center text-[14px] mt-10 text-red-500">{erro}</p>}
      {d && e && (
        <div className="max-w-[820px] mx-auto flex flex-col gap-4">
          <section className="rounded-xl px-4 py-2" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
            <h3 className="text-[15px] font-semibold py-2" style={{ color: 'var(--wa-text)' }}>{NOME_DA_CONTA_OLX[conta]}</h3>
            {linha('Conectada à OLX', sim(e.conectada, 'Sim', 'Ainda não'))}
            {linha('Conta na OLX', e.olxNome || e.olxEmail ? [e.olxNome, e.olxEmail].filter(Boolean).join(' · ') : '—')}
            {linha('Conectada em', e.conectadaEm ? `${quandoInteiro(e.conectadaEm)}${e.conectadaPor ? ` por ${e.conectadaPor}` : ''}` : '—')}
            {linha('Recebimento das mensagens', sim(e.webhookAtivo, `Ligado${e.webhookAtivadoEm ? ` desde ${quandoInteiro(e.webhookAtivadoEm)}` : ''}`, 'Desligado'))}
            {linha('Última resposta da OLX', e.webhookResposta || '—')}
            {linha('Conversas guardadas', String(e.conversas))}
            {linha('Última mensagem', e.ultimaMensagemEm ? quandoInteiro(e.ultimaMensagemEm) : '—')}
            {linha('Anúncios', `${d.anuncios.length}${d.daOlx === 'ok' ? ' (lista da OLX + conversas)' : ' (só os das conversas)'}`)}
            <div className="flex flex-wrap gap-2 py-3">
              {d.aplicativo.cadastrado && (
                <a href={`/api/olx/conectar?conta=${conta}`} className="wa-chip wa-chip--on inline-flex items-center gap-1.5">
                  <PlugsConnected size={15} /> {e.conectada ? 'Conectar de novo' : 'Conectar a conta'}
                </a>
              )}
              {e.conectada && (
                <button type="button" disabled={ligando} onClick={aoLigar} className="wa-chip inline-flex items-center gap-1.5">
                  {ligando ? <CircleNotch size={15} className="animate-spin" /> : <PlugsConnected size={15} />} {e.webhookAtivo ? 'Religar o recebimento' : 'Ligar o recebimento'}
                </button>
              )}
              <button type="button" onClick={carregar} className="wa-chip inline-flex items-center gap-1.5"><ArrowClockwise size={15} /> Atualizar</button>
            </div>
            <p className="text-[12.5px] pb-3" style={{ color: 'var(--wa-text-2)' }}>
              Antes de conectar, entre na OLX <b>com esta conta</b> neste navegador: vale a conta que estiver aberta lá.
            </p>
          </section>
          <section className="rounded-xl px-4 py-2" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
            <h3 className="text-[15px] font-semibold py-2" style={{ color: 'var(--wa-text)' }}>Aplicativo na OLX</h3>
            {linha('Credenciais no servidor', sim(d.aplicativo.cadastrado, 'Cadastradas', 'Faltam o client_id e o client_secret'))}
            {linha('Endereço de retorno', d.aplicativo.redirectUri)}
            {linha('Permissões pedidas', d.aplicativo.escopos.split(/\s+/).map((x) => x === 'chat' ? 'chat' : x === 'autoupload' ? 'anúncios' : x === 'basic_user_info' ? 'identificação da conta' : x).join(', '))}
            <p className="text-[12.5px] py-3" style={{ color: 'var(--wa-text-2)' }}>
              A OLX avisou em 13/10 que a ativação da integração de chat está instável: se o recebimento não ligar na primeira vez, tente de novo mais tarde pelo botão acima.
            </p>
          </section>
        </div>
      )}
    </div>
  )
}

/* ── o chat de uma conta, IGUAL AO CHAT DA OLX (Pedro, 16/10/2026: "quero que refaça o chat da olx do crm para ser
   igual o da olx normal em estrutura, e informações, só deixe o toggle de claro e escuro para o fundo e texto") ──
   À esquerda: "Chat", a busca por produto ou usuário, Todas / Vendendo / Comprando e as conversas (a capa do anúncio
   com a inicial de quem escreveu no canto, o título do anúncio, o nome, a última mensagem e a hora); embaixo, as
   conversas inativas. À direita: a capa, o título e o preço do anúncio e o nome no topo, o perfil, as mensagens por
   dia ("Você 10:28" em cima do balão lilás) e, embaixo, as respostas rápidas e a caixa "Responder <nome>".
   O que a OLX mostra e NÃO chega pela integração fica de fora: "X anos na OLX", o online e o "Lida". No lugar dos
   anos vão o telefone e o e-mail que o webhook traz; no lugar de "Lida", "Enviada" (a OLX aceitou a mensagem). */
type Filtro = 'todas' | 'vendendo' | 'comprando'
/* a OLX tira da lista principal a conversa parada; aqui: anúncio que saiu do ar ou 60 dias sem mensagem */
const INATIVA_MS = 60 * 24 * 3600 * 1000
const inativa = (c: ChatOlxNaLista) => (c.anuncio ? !c.anuncio.noAr : false) || (!!c.ultimaEm && Date.now() - Date.parse(c.ultimaEm) > INATIVA_MS)
/* as respostas rápidas do lado de quem anuncia (as da OLX, "Aceita oferta?", são do comprador). Só preenchem a caixa:
   quem manda é o Enter, para nada sair por um clique sem querer. */
const RESPOSTAS_RAPIDAS = ['Sim, ainda está disponível!', 'Me passa o seu WhatsApp?', 'Quer agendar uma visita?', 'Posso te ligar?']
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']
const ontemEmManaus = () => diaDe(new Date(Date.now() - 864e5).toISOString())
function rotuloDoDia(iso: string) {
  const d = diaDe(iso)
  const [a, m, dd] = d.split('-').map(Number)
  const data = `${dd} de ${MESES[m - 1]} de ${a}`
  return d === diaDe(new Date().toISOString()) ? `Hoje, ${data}` : d === ontemEmManaus() ? `Ontem, ${data}` : data
}
function quandoNaLista(iso: string | null) {
  if (!iso) return ''
  const d = diaDe(iso)
  if (d === diaDe(new Date().toISOString())) return horaDe(iso)
  if (d === ontemEmManaus()) return 'Ontem'
  return new Date(iso).toLocaleDateString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit' })
}
const inicialDe = (c: ChatOlxNaLista) => ((c.nome || '').match(/\p{L}/u)?.[0] || '?').toUpperCase()
function primeiroNome(c: ChatOlxNaLista) {
  const p = (c.nome || '').trim().split(/\s+/)[0] || ''
  return p ? p.charAt(0).toUpperCase() + p.slice(1).toLowerCase() : 'cliente'
}
const tituloDe = (c: ChatOlxNaLista) => c.anuncio?.titulo || (c.listId ? `Anúncio ${c.listId}` : 'Anúncio')

/** a capa do anúncio com a inicial de quem escreveu no canto, como na lista da OLX */
function Capa({ c, tamanho }: { c: ChatOlxNaLista; tamanho: 'p' | 'm' }) {
  const [falhou, setFalhou] = useState(false)
  const foto = c.anuncio?.foto
  return (
    <span className={`olx-capa ${tamanho === 'm' ? 'olx-capa--m' : ''}`}>
      <span className="olx-capa__foto">
        {foto && !falhou ? <img src={foto} alt="" loading="lazy" onError={() => setFalhou(true)} /> : <House size={tamanho === 'm' ? 20 : 24} />}
      </span>
      <span className={`olx-inicial ${tamanho === 'm' ? 'olx-inicial--m' : 'olx-inicial--p'}`}>{inicialDe(c)}</span>
    </span>
  )
}

function ContaOlxAba({ conta, secao, aoMudarSecao, aoContar }: {
  conta: ContaOlx; secao: Secao; aoMudarSecao: (s: Secao) => void; aoContar: (n: number) => void
}) {
  const [estado, setEstado] = useState<EstadoDaContaOlx | null>(null)
  const [chats, setChats] = useState<ChatOlxNaLista[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [filtro, setFiltro] = useState<Filtro>('todas')
  const [verInativas, setVerInativas] = useState(false)
  const [selId, setSelId] = useState<number | null>(null)
  const [msgs, setMsgs] = useState<MensagemOlx[] | null>(null)
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [aviso, setAviso] = useState<{ texto: string; erro?: boolean } | null>(null)
  const [ligando, setLigando] = useState(false)
  const [menuAberto, setMenuAberto] = useState(false)
  const [copiado, setCopiado] = useState<string | null>(null)
  const fim = useRef<HTMLDivElement>(null)
  const caixa = useRef<HTMLTextAreaElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  const carregar = useCallback(() => {
    pedir<{ estado: EstadoDaContaOlx; chats: ChatOlxNaLista[] }>(`/api/olx/chat?conta=${conta}`)
      .then((d) => { setEstado(d.estado); setChats(d.chats); setErro(null) })
      .catch((e) => setErro(e.message))
  }, [conta])
  useEffect(() => { carregar(); const t = setInterval(carregar, 15_000); return () => clearInterval(t) }, [carregar])
  useEffect(() => { aoContar((chats || []).reduce((n, c) => n + c.naoLidas, 0)) }, [chats, aoContar])

  const lerConversa = useCallback((id: number) => {
    pedir<{ mensagens: MensagemOlx[] }>(`/api/olx/chat/${id}?conta=${conta}`)
      .then((d) => setMsgs(d.mensagens))
      .catch((e) => setAviso({ texto: e.message, erro: true }))
  }, [conta])
  useEffect(() => {
    setMsgs(null); setTexto(''); setAviso(null); setMenuAberto(false); setCopiado(null)
    if (!selId) return
    lerConversa(selId)
    const t = setInterval(() => lerConversa(selId), 8_000)
    return () => clearInterval(t)
  }, [selId, lerConversa])
  // a conversa desce até a última mensagem quando chega uma nova
  const quantas = msgs?.length ?? 0
  useEffect(() => { fim.current?.scrollIntoView({ block: 'end' }) }, [quantas, selId])
  // o menu dos três pontinhos fecha com um clique fora dele
  useEffect(() => {
    if (!menuAberto) return
    const fora = (e: MouseEvent) => { if (!menuRef.current?.contains(e.target as Node)) setMenuAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [menuAberto])

  const nInativas = useMemo(() => (chats || []).filter(inativa).length, [chats])
  const filtrados = useMemo(() => {
    const q = sem(busca.trim())
    return (chats || [])
      // procurando, vale a conversa ativa e a inativa (como na busca da OLX)
      .filter((c) => q || inativa(c) === verInativas)
      // toda conversa que chega pela integração é num anúncio DESTA conta (a OLX só avisa quem vende):
      // nenhuma é "Comprando"
      .filter(() => filtro !== 'comprando')
      .filter((c) => !q || sem([c.nome, c.email, c.telefone, c.ultimaTexto, c.listId, c.anuncio?.titulo, c.anuncio?.codigo ? String(c.anuncio.codigo) : null]
        .filter(Boolean).join(' ')).includes(q))
  }, [chats, busca, filtro, verInativas])
  const sel = useMemo(() => (chats || []).find((c) => c.id === selId) || null, [chats, selId])
  const podeResponder = !!estado?.conectada

  async function mandar() {
    const t = texto.trim()
    if (!t || !selId || enviando) return
    setEnviando(true); setAviso(null)
    try {
      await pedir(`/api/olx/chat/${selId}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ conta, texto: t }) })
      setTexto('')
      lerConversa(selId); carregar()
    } catch (e: any) {
      setAviso({ texto: e.message, erro: true })
    } finally {
      setEnviando(false)
    }
  }

  async function ligarRecebimento() {
    setLigando(true); setAviso(null)
    try {
      const r = await pedir<{ ok: boolean; resposta: string }>('/api/olx/conectar', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ conta }),
      })
      setAviso({ texto: `Recebimento ligado na OLX (${r.resposta}).` })
    } catch (e: any) {
      setAviso({ texto: e.message, erro: true })
    } finally {
      setLigando(false); carregar()
    }
  }

  async function copiar(valor: string, qual: string) {
    try { await navigator.clipboard.writeText(valor); setCopiado(qual) } catch { setCopiado(null) }
  }

  const faixaDeAviso = aviso && (
    <div className={`olx-aviso ${aviso.erro ? 'olx-aviso--erro' : 'olx-aviso--ok'}`}>
      <span className="flex-1">{aviso.texto}</span><button type="button" onClick={() => setAviso(null)} aria-label="Fechar"><X size={14} /></button>
    </div>
  )

  if (secao !== 'chat') {
    return (
      <div className="flex-1 min-h-0 flex flex-col">
        {faixaDeAviso}
        {secao === 'anuncios'
          ? <AnunciosDaConta conta={conta} aoVerConversas={(listId) => { setBusca(listId); setSelId(null); aoMudarSecao('chat') }} />
          : <InformacoesDaConta conta={conta} aoLigar={() => void ligarRecebimento()} ligando={ligando} />}
      </div>
    )
  }

  const q = busca.trim()
  const vazio = !chats ? null
    : filtro === 'comprando' ? (
      <>As conversas em que esta conta escreve no anúncio de outra pessoa não chegam pela integração da OLX: elas ficam no{' '}
        <a href="https://chat.olx.com.br/" target="_blank" rel="noopener noreferrer" className="underline">chat do site da OLX</a>.</>
    )
    : q ? <>Nenhuma conversa com &quot;{q}&quot;.</>
    : verInativas ? 'Nenhuma conversa inativa. Aqui ficam as conversas de anúncio que saiu do ar ou sem mensagem há 60 dias.'
    : chats.length && nInativas === chats.length ? 'Todas as conversas estão nas inativas.'
    : estado?.conectada && estado.webhookAtivo ? 'Nenhuma mensagem chegou ainda. Quando alguém escrever no chat da OLX desta conta, a conversa aparece aqui.'
    : 'As conversas aparecem aqui depois que a conta for conectada à OLX.'

  const lista = (
    <aside className={`olx-lado ${selId ? 'hidden md:flex' : 'flex'}`}>
      <div className="olx-lado__topo">
        {verInativas && !q ? (
          <h1 className="olx-titulo">
            <button type="button" className="olx-icone -ml-2" onClick={() => setVerInativas(false)} aria-label="Voltar para as conversas"><ArrowLeft size={22} /></button>
            Conversas inativas
          </h1>
        ) : <h1 className="olx-titulo">Chat</h1>}
        <label className="olx-busca"><MagnifyingGlass size={20} />
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Busque por produto ou usuário..." aria-label="Busque por produto ou usuário"
                 className="bg-transparent" />
          {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} /></button>}
        </label>
        <div className="olx-filtros" role="group" aria-label="Filtrar conversas">
          {([['todas', 'Todas'], ['vendendo', 'Vendendo'], ['comprando', 'Comprando']] as [Filtro, string][]).map(([f, r]) => (
            <button key={f} type="button" onClick={() => setFiltro(f)} aria-pressed={filtro === f} className={`olx-chip ${filtro === f ? 'olx-chip--on' : ''}`}>{r}</button>
          ))}
        </div>
      </div>
      <div className="olx-lista">
        {!chats && !erro && (
          <p className="olx-vazio flex items-center justify-center gap-2"><CircleNotch size={18} className="animate-spin" /> Lendo as conversas…</p>
        )}
        {erro && <p className="olx-vazio text-red-500">{erro}</p>}
        {filtrados.map((c) => (
          <button key={c.id} type="button" onClick={() => setSelId(c.id)}
                  className={`olx-linha ${selId === c.id ? 'olx-linha--sel' : ''} ${c.naoLidas ? 'olx-linha--nova' : ''}`}>
            {c.naoLidas > 0 && <span className="olx-linha__ponto" aria-label={`${c.naoLidas} não lida${c.naoLidas === 1 ? '' : 's'}`} />}
            <Capa key={c.anuncio?.foto || c.id} c={c} tamanho="p" />
            <span className="olx-linha__texto">
              <span className="olx-linha__anuncio">{tituloDe(c)}</span>
              <span className="olx-linha__nome">{nomeDe(c)}</span>
              <span className="olx-linha__ultima">
                <span>{c.ultimaDe === 'nos' ? 'Você: ' : ''}{c.ultimaTexto || '—'}</span>
                <span className="olx-linha__hora">{quandoNaLista(c.ultimaEm)}</span>
              </span>
            </span>
          </button>
        ))}
        {chats && !filtrados.length && vazio && <p className="olx-vazio">{vazio}</p>}
      </div>
      {!verInativas && (
        <button type="button" className="olx-inativas" onClick={() => { setVerInativas(true); setSelId(null) }}>
          <span>Conversas inativas <span className="olx-inativas__n">({nInativas})</span></span>
          <CaretRight size={20} />
        </button>
      )}
    </aside>
  )

  const anuncioUrl = sel ? (sel.anuncio?.url || linkDoAnuncio(sel.listId)) : null
  const itens: React.ReactNode[] = []
  if (sel && msgs) {
    let diaAnterior = ''
    let antes: MensagemOlx | null = null
    for (const m of msgs) {
      const dia = diaDe(m.quando)
      if (dia !== diaAnterior) { itens.push(<p key={`d${m.id}`} className="olx-dia">{rotuloDoDia(m.quando)}</p>); diaAnterior = dia; antes = null }
      if (m.de === 'sistema') {
        itens.push(<p key={m.id} className="olx-sistema">{m.texto} · {horaDe(m.quando)}</p>)
        antes = null
        continue
      }
      // "Você 10:28" em cima do primeiro balão de cada sequência (mesma pessoa, menos de 10 minutos)
      const novaSequencia = !antes || antes.de !== m.de || (antes.enviadaPor || '') !== (m.enviadaPor || '')
        || Date.parse(m.quando) - Date.parse(antes.quando) > 10 * 60_000
      if (novaSequencia) {
        itens.push(
          <p key={`q${m.id}`} className={`olx-quem ${m.de === 'nos' ? 'olx-quem--nos' : ''}`}>
            <b>{m.de === 'nos' ? 'Você' : primeiroNome(sel)}</b>
            {m.de === 'nos' && m.enviadaPor ? <span>{m.enviadaPor}</span> : null}
            <span>{horaDe(m.quando)}</span>
          </p>,
        )
      }
      itens.push(
        <div key={m.id} className={`olx-balao ${m.de === 'nos' ? 'olx-balao--nos' : 'olx-balao--dele'}`} title={quandoInteiro(m.quando)}>{m.texto}</div>,
      )
      antes = m
    }
    if (msgs.length && msgs[msgs.length - 1].de === 'nos') itens.push(<p key="enviada" className="olx-lida">Enviada</p>)
  }

  const conversa = !sel ? (
    <section className="olx-conversa hidden md:flex items-center justify-center text-center px-8">
      <ChatsCircle size={56} style={{ color: 'var(--olx-roxo)' }} />
      <p className="text-[18px] font-bold mt-3">Selecione uma conversa</p>
      <p className="text-[14px] mt-1 max-w-md" style={{ color: 'var(--olx-texto-2)' }}>
        O que você responder aqui sai no chat da OLX, pela {NOME_DA_CONTA_OLX[conta].toLowerCase()}.
      </p>
    </section>
  ) : (
    <section className="olx-conversa flex">
      <header className="olx-conv__topo">
        <span className="md:hidden -ml-2">
          <button type="button" className="olx-icone" onClick={() => setSelId(null)} aria-label="Voltar"><ArrowLeft size={22} /></button>
        </span>
        {anuncioUrl
          ? <a href={anuncioUrl} target="_blank" rel="noopener noreferrer" title="Abrir o anúncio na OLX"><Capa key={sel.anuncio?.foto || sel.id} c={sel} tamanho="m" /></a>
          : <Capa key={sel.anuncio?.foto || sel.id} c={sel} tamanho="m" />}
        <div className="flex-1 min-w-0">
          <p className="olx-conv__anuncio">
            {anuncioUrl
              ? <a href={anuncioUrl} target="_blank" rel="noopener noreferrer" title="Abrir o anúncio na OLX">{tituloDe(sel)}</a>
              : <span className="truncate">{tituloDe(sel)}</span>}
            {sel.anuncio?.preco != null && <><span className="olx-conv__sep">|</span><span className="olx-conv__preco">{dinheiro(sel.anuncio.preco)}</span></>}
          </p>
          <p className="olx-conv__nome">{nomeDe(sel)}</p>
        </div>
        <div className="relative" ref={menuRef}>
          <button type="button" className="olx-icone" onClick={() => setMenuAberto((v) => !v)} aria-label="Mais opções" aria-expanded={menuAberto}>
            <DotsThreeVertical size={24} weight="bold" />
          </button>
          {menuAberto && (
            <div className="olx-menu" role="menu">
              {anuncioUrl && <a href={anuncioUrl} target="_blank" rel="noopener noreferrer" role="menuitem"><ArrowSquareOut size={18} /> Ver o anúncio na OLX</a>}
              {sel.anuncio?.codigo && (
                <a href={`/${sel.anuncio.codigo}`} target="_blank" rel="noopener noreferrer" role="menuitem"><House size={18} /> Abrir o imóvel #{sel.anuncio.codigo}</a>
              )}
              {sel.telefone && (
                <button type="button" role="menuitem" onClick={() => void copiar(sel.telefone!, 'telefone')}>
                  <Phone size={18} /> {copiado === 'telefone' ? 'Telefone copiado' : `Copiar o telefone (${sel.telefone})`}
                </button>
              )}
              {sel.email && (
                <button type="button" role="menuitem" onClick={() => void copiar(sel.email!, 'email')}>
                  <EnvelopeSimple size={18} /> {copiado === 'email' ? 'E-mail copiado' : 'Copiar o e-mail'}
                </button>
              )}
              {!anuncioUrl && !sel.anuncio?.codigo && !sel.telefone && !sel.email && <p className="px-4 py-2 text-[13px]" style={{ color: 'var(--olx-texto-2)' }}>Nada a mostrar.</p>}
            </div>
          )}
        </div>
      </header>
      {faixaDeAviso}
      <div className="olx-conv__rolagem">
        <div className="olx-perfil">
          <span className="olx-inicial olx-inicial--g">{inicialDe(sel)}</span>
          <p className="olx-perfil__nome">{nomeDe(sel)}</p>
          <p className="olx-perfil__info">{[sel.telefone, sel.email].filter(Boolean).join(' · ') || 'sem telefone nem e-mail'}</p>
          <p className="olx-perfil__info">
            <b>{sel.mensagens}</b> mensage{sel.mensagens === 1 ? 'm' : 'ns'} desde {new Date(sel.criadoEm).toLocaleDateString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit' })}
          </p>
        </div>
        {msgs === null && <p className="olx-sistema">carregando…</p>}
        {itens}
        <div ref={fim} />
      </div>
      <footer className="olx-conv__rodape">
        {podeResponder && (
          <div className="olx-rapidas">
            {RESPOSTAS_RAPIDAS.map((t) => (
              <button key={t} type="button" className="olx-chip olx-chip--p"
                      onClick={() => { setTexto((v) => (v.trim() ? `${v.trimEnd()} ${t}` : t)); caixa.current?.focus() }}>{t}</button>
            ))}
          </div>
        )}
        <div className="olx-caixa">
          <textarea
            ref={caixa}
            value={texto}
            onChange={(e) => setTexto(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void mandar() } }}
            disabled={!podeResponder || enviando}
            rows={Math.min(5, Math.max(1, texto.split('\n').length))}
            maxLength={2000}
            placeholder={podeResponder ? `Responder ${primeiroNome(sel)}` : 'Conecte a conta à OLX para responder por aqui'}
            aria-label="Mensagem"
            // a classe bg-[...] tira o campo da regra escura geral (globals.css, ".dark textarea"), que pintaria outro fundo
            className="bg-[var(--olx-fundo-2)]"
          />
          <button type="button" className="olx-enviar" onClick={() => void mandar()} disabled={!podeResponder || enviando || !texto.trim()} title="Enviar" aria-label="Enviar">
            {enviando ? <CircleNotch size={22} className="animate-spin" /> : <PaperPlaneRight size={24} weight="fill" />}
          </button>
        </div>
      </footer>
    </section>
  )

  return (
    <div className="flex-1 min-h-0 flex flex-col">
      <EstadoDaConta conta={conta} estado={estado} aoLigar={() => void ligarRecebimento()} ligando={ligando} />
      {!sel && faixaDeAviso}
      <div className="flex flex-1 min-h-0">
        {lista}
        {conversa}
      </div>
    </div>
  )
}

export default function ChatOlxContas() {
  const [visao, setVisao] = useState<Visao>('proprietarios')
  const [secao, setSecao] = useState<Secao>('chat')
  const [naoLidas, setNaoLidas] = useState(0)
  const [aviso, setAviso] = useState<string | null>(null)

  // ?conta= e ?aviso= (a volta da OLX). Lido do window, não do useSearchParams: o hook obrigaria a envolver
  // a página em <Suspense> (o mesmo motivo do LoginForm).
  useEffect(() => {
    const q = new URLSearchParams(window.location.search)
    const conta = q.get('conta')
    if (conta && (CONTAS_OLX as readonly string[]).includes(conta)) setVisao(conta as ContaOlx)
    const a = q.get('aviso')
    if (a) {
      setAviso(a.slice(0, 400))
      // o aviso não fica na barra de endereço (recarregar a página não o repete)
      window.history.replaceState(null, '', window.location.pathname + (conta ? `?conta=${encodeURIComponent(conta)}` : ''))
    }
  }, [])

  return (
    <div className="flex flex-col flex-1 min-h-0 h-full">
      {/* uma barra só, como o topo do site da OLX: a conta, o menu da conta e os atalhos */}
      <div className="olx-barra">
        <span className="olx-barra__nome">Chat OLX</span>
        {CONTAS_OLX.map((c) => (
          <button key={c} type="button" onClick={() => { setVisao(c); setNaoLidas(0) }}
                  className={`olx-chip olx-chip--p ${visao === c ? 'olx-chip--on' : ''}`}>{NOME_DA_CONTA_OLX[c]}</button>
        ))}
        {visao !== 'bot' && (
          <nav className="olx-abas" role="tablist" aria-label="Menu da conta">
            {([['chat', 'Chat', ChatsCircle], ['anuncios', 'Anúncios', Megaphone], ['info', 'Informações', Info]] as const).map(([k, rotulo, Icone]) => (
              <button key={k} type="button" role="tab" aria-selected={secao === k} onClick={() => setSecao(k)} className={`olx-aba ${secao === k ? 'olx-aba--on' : ''}`}>
                <Icone size={17} /> {rotulo}
                {k === 'chat' && naoLidas > 0 && <span className="olx-aba__n">{naoLidas > 99 ? '99+' : naoLidas}</span>}
              </button>
            ))}
          </nav>
        )}
        <span className="ml-auto flex items-center gap-2 flex-wrap">
          <a href="https://chat.olx.com.br/" target="_blank" rel="noopener noreferrer" className="olx-chip olx-chip--p"
             title="Abre o chat da própria OLX em outra aba do navegador"><ArrowSquareOut size={15} /> <span className="hidden sm:inline">Chat no site da OLX</span></a>
          <button type="button" onClick={() => setVisao('bot')} title="Os anúncios que o bot da OLX consultou e a mensagem que saiu para cada um"
                  className={`olx-chip olx-chip--p ${visao === 'bot' ? 'olx-chip--on' : ''}`}>
            <Robot size={15} /> <span className="hidden sm:inline">Consultas do bot</span>
          </button>
        </span>
      </div>
      {aviso && (
        <div className="olx-aviso olx-aviso--ok">
          <span className="flex-1">{aviso}</span><button type="button" onClick={() => setAviso(null)} aria-label="Fechar"><X size={14} /></button>
        </div>
      )}
      {visao === 'bot' ? <ChatOlx /> : <ContaOlxAba key={visao} conta={visao} secao={secao} aoMudarSecao={setSecao} aoContar={setNaoLidas} />}
    </div>
  )
}
