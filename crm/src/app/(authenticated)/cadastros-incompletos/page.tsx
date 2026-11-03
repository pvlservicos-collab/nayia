'use client'

/**
 * CADASTROS INCOMPLETOS (Pedro, 03/11/2026): "pega esses cadastros incompletos e põe no CRM a lista dessas conversas lá no
 * menu + (Mais), com o número e as mensagens dele e um botão ir para a conversa, e classifique os imóveis que eles estavam
 * cadastrando com uma nota baseada no que nossos clientes estão pedindo, e tenha certeza de que não vamos falar com alguém
 * que já falamos em outro número recentemente e cadastramos esse imóvel".
 *
 * Três grupos (a rota decide): Livres (o cadastro parou e dá para continuar), Com a equipe (alguém assumiu a conversa) e
 * Não chamar (já cadastramos o imóvel, já falamos em outro número ou ele pediu para sair; o motivo está em cada cartão).
 * Lê /api/cadastros-incompletos. A nota (0-100) mede a procura pelo imóvel: pedidos dos grupos (30 dias) e buscas de
 * clientes nossos que ele atenderia.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowsClockwise, ChatCircleText, CircleNotch, Warning, CaretDown, CaretUp, ClipboardText } from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'

interface Mensagem { texto: string; direcao: string | null; origem: string | null; quando: string }
interface Item {
  cadastro_id: number; tipo: string; codigo: number | null; dados: Record<string, any>; fotos: number
  atualizado_em: string; nome: string | null; telefone: string; canal: string; perfil_nay: string | null; status: string
  humano: boolean; nota: number | null; pedidos_90: number | null; pedidos_70: number | null; clientes: number | null
  melhor: { faltou?: string[]; assumido?: Record<string, any>; corretores?: { nota: number; texto: string }[]; clientes?: { nota: number; nome: string }[] } | null
  calculada_em: string | null
  grupo: 'livre' | 'com_equipe' | 'nao_chamar'; motivos: string[]; linha: string; leadId: string | null; titulo: string | null
  ultimaMensagem: string | null; mensagens: Mensagem[]
}

const GRUPOS = [
  { k: 'livre', r: 'Livres para continuar', dica: 'O cadastro parou e ninguém falou com o dono em outro número.' },
  { k: 'com_equipe', r: 'Com a equipe', dica: 'O Tel ou alguém da equipe assumiu a conversa: a Nay não retoma.' },
  { k: 'nao_chamar', r: 'Não chamar', dica: 'Já cadastramos o imóvel, já falamos em outro número ou ele pediu para sair.' },
] as const

const CAMPOS: [string, string][] = [['tipo', 'Tipo'], ['negocio', 'Negócio'], ['bairro', 'Bairro'], ['condominio', 'Condomínio'], ['quartos', 'Quartos'],
  ['suites', 'Suítes'], ['vagas', 'Vagas'], ['area', 'Área'], ['valor', 'Valor'], ['iptu', 'IPTU']]

function fone(v: string) {
  const d = (v || '').replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  return d.length === 11 ? `${d.slice(0, 2)} ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `${d.slice(0, 2)} ${d.slice(2, 6)}-${d.slice(6)}` : v
}
function quando(iso: string | null) {
  return iso ? new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Manaus', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : ''
}
const corDaNota = (n: number | null) => (n === null ? 'var(--muted)' : n >= 60 ? '#16a34a' : n >= 25 ? '#d97706' : '#64748b')

function Cartao({ i }: { i: Item }) {
  const [aberto, setAberto] = useState(false)
  const campos = CAMPOS.filter(([k]) => i.dados?.[k]).map(([k, r]) => [r, String(i.dados[k])] as const)
  const detalhes = i.dados?.detalhes ? String(i.dados.detalhes) : ''
  return (
    <div className="rounded-lg border border-line bg-panel p-3 flex flex-col gap-2">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div className="min-w-0">
          <div className="font-semibold truncate">{i.titulo || i.nome || 'Sem nome'}</div>
          <div className="text-xs text-muted">{fone(i.telefone)} · {i.linha}{i.perfil_nay ? ` · Nay ${i.perfil_nay}` : ''}</div>
        </div>
        <div className="flex items-center gap-2">
          <span title={i.melhor ? `${i.pedidos_90 || 0} pedidos de corretores 90+, ${i.pedidos_70 || 0} de 70 a 89 e ${i.clientes || 0} clientes nossos (calculada ${quando(i.calculada_em)})` : 'Nota ainda não calculada'}
                className="px-2.5 py-1 rounded-full text-xs font-bold"
                style={{ color: corDaNota(i.nota), background: `color-mix(in srgb, ${corDaNota(i.nota)} 14%, transparent)`, border: `1px solid color-mix(in srgb, ${corDaNota(i.nota)} 35%, transparent)` }}>
            Nota {i.nota ?? '—'}
          </span>
          {i.leadId ? (
            <Link href={linkDaConversa(i.leadId)} className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-accent text-white text-sm font-medium hover:opacity-90">
              <ChatCircleText size={16} weight="bold" /> Ir para a conversa
            </Link>
          ) : (
            <span className="text-xs text-muted px-2 py-1 rounded border border-line">sem conversa no CRM</span>
          )}
        </div>
      </div>

      {i.motivos.length > 0 && (
        <div className="rounded-md border px-2.5 py-1.5 text-xs flex flex-col gap-0.5" style={{ borderColor: '#dc262655', background: '#dc262612', color: '#dc2626' }}>
          {i.motivos.map((m, k) => <span key={k} className="flex items-start gap-1"><Warning size={13} weight="fill" className="mt-0.5 shrink-0" />{m}</span>)}
        </div>
      )}

      <div className="flex flex-wrap gap-1.5 text-xs">
        <span className="px-2 py-0.5 rounded bg-black/5 dark:bg-white/10">{i.tipo === 'atualizar' ? `Atualizar o #${i.codigo}` : 'Imóvel novo'}</span>
        {campos.map(([r, v]) => <span key={r} className="px-2 py-0.5 rounded border border-line"><b>{r}:</b> {v.length > 40 ? v.slice(0, 40) + '…' : v}</span>)}
        <span className="px-2 py-0.5 rounded border border-line">{i.fotos} foto(s)</span>
        {i.melhor?.faltou && i.melhor.faltou.length > 0 && <span className="px-2 py-0.5 rounded border border-line text-muted">falta: {i.melhor.faltou.join(', ')}</span>}
      </div>
      {detalhes && <div className="text-xs text-muted">{detalhes.length > 220 ? detalhes.slice(0, 220) + '…' : detalhes}</div>}

      {i.melhor && (i.melhor.corretores?.length || i.melhor.clientes?.length) ? (
        <div className="text-xs text-muted">
          Procura: {i.pedidos_90 || 0} pedido(s) de corretores 90+, {i.pedidos_70 || 0} de 70 a 89, {i.clientes || 0} cliente(s) nosso(s).
          {i.melhor.corretores?.[0] && <> Melhor: {i.melhor.corretores[0].nota} — {i.melhor.corretores[0].texto}</>}
        </div>
      ) : null}

      <button type="button" onClick={() => setAberto((v) => !v)} className="self-start flex items-center gap-1 text-xs text-accent hover:underline">
        {aberto ? <CaretUp size={12} /> : <CaretDown size={12} />} {aberto ? 'Esconder' : 'Ver'} as mensagens ({i.mensagens.length}){i.ultimaMensagem ? ` · última em ${quando(i.ultimaMensagem)}` : ''}
      </button>
      {aberto && (
        <div className="flex flex-col gap-1.5 max-h-80 overflow-y-auto rounded-md bg-black/5 dark:bg-white/5 p-2">
          {i.mensagens.length === 0 && <span className="text-xs text-muted">Nenhuma mensagem no CRM.</span>}
          {i.mensagens.map((m, k) => (
            <div key={k} className={`max-w-[85%] rounded-lg px-2.5 py-1.5 text-sm whitespace-pre-wrap ${m.direcao === 'outbound' ? 'self-end bg-accent/15' : 'self-start bg-panel border border-line'}`}>
              {m.texto || '(mídia)'}
              <div className="text-[10px] text-muted mt-0.5">{m.direcao === 'outbound' ? (m.origem === 'human' ? 'equipe' : 'Nay') : 'ele'} · {quando(m.quando)}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

export default function CadastrosIncompletosPage() {
  const [itens, setItens] = useState<Item[] | null>(null)
  const [erro, setErro] = useState('')
  const [grupo, setGrupo] = useState<string>('livre')
  const [carregando, setCarregando] = useState(false)

  const carregar = useCallback(() => {
    setCarregando(true); setErro('')
    fetch('/api/cadastros-incompletos').then(async (r) => {
      const j = await r.json()
      if (!r.ok) throw new Error(j.error || j.message || 'Erro')
      setItens(j.itens || [])
    }).catch((e) => setErro(e.message || 'Não consegui ler os cadastros.')).finally(() => setCarregando(false))
  }, [])
  useEffect(() => { carregar() }, [carregar])

  const contagem = useMemo(() => {
    const c: Record<string, number> = { livre: 0, com_equipe: 0, nao_chamar: 0 }
    for (const i of itens || []) c[i.grupo]++
    return c
  }, [itens])
  const visiveis = (itens || []).filter((i) => i.grupo === grupo)

  return (
    <div className="p-4 md:p-6 max-w-5xl mx-auto flex flex-col gap-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2">
          <ClipboardText size={22} weight="duotone" />
          <h1 className="text-xl font-bold">Cadastros incompletos</h1>
        </div>
        <button type="button" onClick={carregar} disabled={carregando} className="flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-line text-sm hover:bg-black/5 dark:hover:bg-white/10">
          {carregando ? <CircleNotch size={14} className="animate-spin" /> : <ArrowsClockwise size={14} />} Atualizar
        </button>
      </div>
      <p className="text-sm text-muted">
        Donos com quem a conversa do cadastro do imóvel parou. A nota (0 a 100) mede a procura: quantos pedidos dos grupos (30 dias) e clientes nossos
        o imóvel atenderia. Quem já tem o imóvel cadastrado ou já falou com a gente em outro número nos últimos 14 dias fica em &quot;Não chamar&quot;.
      </p>
      <div className="flex gap-2 flex-wrap">
        {GRUPOS.map((g) => (
          <button key={g.k} type="button" title={g.dica} onClick={() => setGrupo(g.k)}
                  className={`px-3 py-1.5 rounded-full text-sm border ${grupo === g.k ? 'bg-accent text-white border-accent' : 'border-line hover:bg-black/5 dark:hover:bg-white/10'}`}>
            {g.r} · {contagem[g.k] ?? 0}
          </button>
        ))}
      </div>
      {erro && <div className="rounded-md border border-red-500/40 bg-red-500/10 text-red-600 px-3 py-2 text-sm">{erro}</div>}
      {itens === null && !erro && <div className="flex items-center gap-2 text-muted"><CircleNotch size={16} className="animate-spin" /> Carregando…</div>}
      {itens && visiveis.length === 0 && <div className="text-muted text-sm">Nenhum cadastro neste grupo.</div>}
      <div className="flex flex-col gap-3">{visiveis.map((i) => <Cartao key={i.cadastro_id} i={i} />)}</div>
    </div>
  )
}
