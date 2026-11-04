'use client'

/**
 * OS BOTÕES DE ORGANIZAR A CONVERSA, no alto dela, ao lado de "Cadastrar imóvel" (Pedro, 03/11/2026: "quando o Lucas clicar
 * em um número tenha em cima do lado de cadastrar imóvel um botão enviar para Rayssa, ou Enviar para administração ... e
 * que o Lucas consiga fazer aquele relacionamento de conversa que coloca uma conversa dentro da outra").
 *
 *   Tipo            o tipo de contato (cor na lista); o lápis do menu edita a lista de tipos
 *   Rayssa          a conversa aparece na aba Rayssa da Parceria, com a faixa "Conversando pelo número Leads";
 *                   a Nay Leads cala (etapa 'rayssa' da captação)
 *   Administração   o tipo vira Administração: a conversa sai das abas do número e vai para o Chat Administração (só o Tel)
 *   Dentro de…      põe esta conversa dentro de outra (a setinha da lista), ou tira
 */
import { useEffect, useRef, useState } from 'react'
import { Check, CircleNotch, FolderSimpleUser, HouseLine, MagnifyingGlass, PaperPlaneRight, Plus, Tag, Trash, TreeStructure, UserPlus, X } from '@phosphor-icons/react'
import type { LeadWithOwner, SearchHit } from '@/lib/types'
import { useTiposDeContato } from '@/hooks/useTiposDeContato'
import { acharTipo, dentroDe, pessoasDe, type TipoDeContato } from '@/lib/organizacaoDoLead'

const fim8 = (t: string | null | undefined) => String(t || '').replace(/\D/g, '').slice(-8)

export interface Organizado { custom_attributes: Record<string, any>; last_activity_at?: string; is_unread?: boolean }

export async function organizar(leadId: string, corpo: Record<string, unknown>): Promise<Organizado> {
  const r = await fetch(`/api/leads/${leadId}/organizar`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo),
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j.error || j.message || 'Não consegui salvar.')
  return { custom_attributes: j.custom_attributes || {}, last_activity_at: j.last_activity_at, is_unread: j.is_unread }
}

interface Props {
  lead: LeadWithOwner
  /** o tipo que a lista deduz quando ninguém escolheu (corretor, proprietário...) */
  tipoDeduzido?: string | null
  aoMudar: (o: Organizado) => void
  /** na aba para onde a conversa foi ENVIADA (mudou_para): só o botão de devolver */
  soDevolver?: string
  /** 03/11 (Pedro): só o administrador (o Tel) adiciona pessoa à conversa; a lista é da equipe (lib/atendentes) */
  equipe?: { id: string; nome: string; cor: string }[]
}

export default function OrganizarConversa({ lead, tipoDeduzido, aoMudar, soDevolver, equipe }: Props) {
  const { tipos, salvar } = useTiposDeContato()
  const [menu, setMenu] = useState<'' | 'tipo' | 'dentro' | 'editar' | 'pessoas'>('')
  const [ocupado, setOcupado] = useState('')
  const [aviso, setAviso] = useState('')
  const caixa = useRef<HTMLDivElement>(null)
  const escolhido = lead.custom_attributes?.tipo_contato as string | undefined
  const tipo = acharTipo(tipos, escolhido || tipoDeduzido)

  useEffect(() => {
    if (!menu) return
    const fora = (e: MouseEvent) => { if (caixa.current && !caixa.current.contains(e.target as Node)) setMenu('') }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [menu])
  useEffect(() => { setMenu(''); setAviso('') }, [lead.id])

  const fazer = async (rotulo: string, corpo: Record<string, unknown>, depois?: () => Promise<void>) => {
    setOcupado(rotulo); setAviso('')
    try {
      const o = await organizar(lead.id, corpo)
      if (depois) await depois()
      aoMudar(o)
      setAviso(rotulo)
      setTimeout(() => setAviso(''), 2500)
    } catch (e: any) {
      setAviso(e.message || 'Não consegui salvar.')
    } finally {
      setOcupado(''); setMenu('')
    }
  }

  const enviarRayssa = () => fazer('Enviado para a Rayssa', { rayssa: true }, async () => {
    // a Nay Leads cala para esta pessoa enquanto a Rayssa atende (a mesma etapa manual da captação)
    await fetch(`/api/leads/${lead.id}/captacao-etapa`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: 'rayssa' }),
    }).catch(() => undefined)
  })
  const enviarAdministracao = () => fazer('Enviado para a Administração', { tipo: 'administracao' })

  const botao = 'flex items-center gap-1.5 h-9 px-2.5 rounded-lg text-[13px] font-semibold flex-shrink-0'
  const borda = { border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }

  if (soDevolver) {
    return (
      <button type="button" className={botao} style={borda} disabled={!!ocupado}
              onClick={() => fazer('Devolvida', { devolver: true }, async () => {
                // a Nay Leads volta a atender (a etapa manual 'rayssa' da captação sai)
                await fetch(`/api/leads/${lead.id}/captacao-etapa`, {
                  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: 'todos' }),
                }).catch(() => undefined)
              })}
              title={`Tira a conversa daqui e ela volta para a aba ${soDevolver}`}>
        {ocupado ? <CircleNotch size={16} className="animate-spin" /> : <PaperPlaneRight size={16} className="-scale-x-100" />}
        <span className="hidden lg:inline">Devolver para o {soDevolver}</span>
      </button>
    )
  }

  return (
    <div ref={caixa} className="relative flex items-center gap-1.5">
      <button type="button" className={botao} style={{ ...borda, ...(tipo ? { color: tipo.cor, borderColor: tipo.cor + '66' } : {}) }}
              onClick={() => setMenu(menu === 'tipo' ? '' : 'tipo')} title="Tipo de contato (a cor da conversa na lista)">
        <Tag size={16} weight="fill" />
        <span className="hidden lg:inline">{tipo?.nome || 'Tipo'}</span>
      </button>
      <button type="button" className={botao} style={borda} onClick={enviarRayssa} disabled={!!ocupado}
              title="A conversa sai do Leads e vai para a aba Rayssa da Parceria, no topo (a resposta continua saindo por este número); a Nay para de responder">
        {ocupado === 'Enviado para a Rayssa' ? <CircleNotch size={16} className="animate-spin" /> : <PaperPlaneRight size={16} />}
        <span className="hidden xl:inline">Enviar para Rayssa</span>
      </button>
      <button type="button" className={botao} style={borda} onClick={enviarAdministracao} disabled={!!ocupado}
              title="O contato vira Administração: sai das abas deste número e vai para o Chat Administração (só o Tel vê)">
        {ocupado === 'Enviado para a Administração' ? <CircleNotch size={16} className="animate-spin" /> : <FolderSimpleUser size={16} />}
        <span className="hidden xl:inline">Enviar para administração</span>
      </button>
      {equipe && equipe.length > 0 && (
        <button type="button" className={botao} style={borda} onClick={() => setMenu(menu === 'pessoas' ? '' : 'pessoas')}
                title="Adicionar alguém da equipe a esta conversa: em Administração, ela só aparece (fixada) para quem for adicionado">
          <UserPlus size={16} />
          <span className="hidden xl:inline">Adicionar pessoa{pessoasDe(lead).length ? ` (${pessoasDe(lead).length})` : ''}</span>
        </button>
      )}
      <button type="button" className={botao} style={borda} onClick={() => setMenu(menu === 'dentro' ? '' : 'dentro')}
              title="Pôr esta conversa dentro de outra (aparece na setinha embaixo dela)">
        <TreeStructure size={16} />
        <span className="hidden 2xl:inline">Dentro de…</span>
      </button>
      {aviso && (
        <span className="absolute top-full right-0 mt-1 text-[12px] px-2 py-1 rounded shadow z-40 whitespace-nowrap"
              style={{ background: 'var(--wa-panel, #fff)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}>{aviso}</span>
      )}

      {menu === 'tipo' && (
        <div className="absolute top-full right-0 mt-1 w-56 rounded-lg shadow-lg z-40 py-1"
             style={{ background: 'var(--wa-panel, #fff)', border: '1px solid var(--wa-divider)' }}>
          {tipos.map((t) => (
            <button key={t.chave} type="button" onClick={() => fazer(`Tipo: ${t.nome}`, { tipo: t.chave })}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-[13px] text-left hover:bg-black/5 dark:hover:bg-white/10"
                    style={{ color: 'var(--wa-text)' }}>
              <span className="w-3 h-3 rounded-full flex-shrink-0" style={{ background: t.cor }} />
              <span className="flex-1">{t.nome}</span>
              {(escolhido || tipoDeduzido) === t.chave && <span className="text-[11px] opacity-60">{escolhido ? 'escolhido' : 'automático'}</span>}
            </button>
          ))}
          {escolhido && (
            <button type="button" onClick={() => fazer('Tipo automático', { tipo: null })}
                    className="w-full px-3 py-1.5 text-[12px] text-left hover:bg-black/5 dark:hover:bg-white/10" style={{ color: 'var(--wa-text-2)' }}>
              Voltar ao automático
            </button>
          )}
          <button type="button" onClick={() => setMenu('editar')}
                  className="w-full px-3 py-1.5 text-[12px] text-left border-t hover:bg-black/5 dark:hover:bg-white/10"
                  style={{ color: 'var(--wa-text-2)', borderColor: 'var(--wa-divider)' }}>
            Editar os tipos…
          </button>
        </div>
      )}
      {menu === 'editar' && <EditarTipos tipos={tipos} salvar={salvar} fechar={() => setMenu('')} />}
      {menu === 'dentro' && <DentroDe lead={lead} fazer={fazer} />}
      {menu === 'pessoas' && equipe && (
        <div className="absolute top-full right-0 mt-1 w-60 rounded-lg shadow-lg z-40 py-1"
             style={{ background: 'var(--wa-panel, #fff)', border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>
          <p className="px-3 py-1 text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Quem vê esta conversa (fixada no Leads)</p>
          {equipe.map((p) => {
            const tem = pessoasDe(lead).includes(p.id)
            return (
              <button key={p.id} type="button" disabled={!!ocupado}
                      onClick={() => {
                        const novas = tem ? pessoasDe(lead).filter((x) => x !== p.id) : [...pessoasDe(lead), p.id]
                        void fazer(tem ? `${p.nome} saiu da conversa` : `${p.nome} adicionado`, { pessoas: novas })
                      }}
                      className="w-full flex items-center gap-2 px-3 py-1.5 text-[13px] text-left hover:bg-black/5 dark:hover:bg-white/10">
                <span className="w-3 h-3 rounded-full flex-shrink-0" style={{ background: p.cor }} />
                <span className="flex-1">{p.nome}</span>
                {tem && <Check size={15} style={{ color: '#16a34a' }} />}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

function EditarTipos({ tipos, salvar, fechar }: { tipos: TipoDeContato[]; salvar: (t: TipoDeContato[]) => Promise<TipoDeContato[]>; fechar: () => void }) {
  const [lista, setLista] = useState<TipoDeContato[]>(tipos)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)
  const mudar = (i: number, campo: keyof TipoDeContato, v: string) => setLista((l) => l.map((t, k) => (k === i ? { ...t, [campo]: v } : t)))
  return (
    <div className="absolute top-full right-0 mt-1 w-80 rounded-lg shadow-lg z-40 p-3 flex flex-col gap-2"
         style={{ background: 'var(--wa-panel, #fff)', border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>
      <div className="flex items-center justify-between text-[13px] font-semibold">
        Tipos de contato <button type="button" onClick={fechar}><X size={16} /></button>
      </div>
      {lista.map((t, i) => (
        <div key={i} className="flex items-center gap-2">
          <input type="color" value={t.cor} onChange={(e) => mudar(i, 'cor', e.target.value)} className="w-7 h-7 rounded border-0 p-0 bg-transparent" />
          <input value={t.nome} onChange={(e) => mudar(i, 'nome', e.target.value)} maxLength={40}
                 className="flex-1 h-8 px-2 rounded text-[13px] bg-transparent" style={{ border: '1px solid var(--wa-divider)' }} />
          <button type="button" title="Tirar este tipo" onClick={() => setLista((l) => l.filter((_, k) => k !== i))}><Trash size={15} /></button>
        </div>
      ))}
      <button type="button" onClick={() => setLista((l) => [...l, { chave: '', nome: 'Novo tipo', cor: '#0891b2' }])}
              className="flex items-center gap-1 text-[12px] self-start" style={{ color: 'var(--wa-text-2)' }}>
        <Plus size={13} /> Novo tipo
      </button>
      {erro && <span className="text-[12px] text-red-600">{erro}</span>}
      <button type="button" disabled={salvando}
              onClick={async () => {
                setSalvando(true); setErro('')
                try { await salvar(lista.map((t) => ({ ...t, chave: t.chave || t.nome }))); fechar() }
                catch (e: any) { setErro(e.message) } finally { setSalvando(false) }
              }}
              className="h-8 rounded-md text-[13px] font-semibold text-white" style={{ background: '#16a34a' }}>
        {salvando ? 'Salvando…' : 'Salvar'}
      </button>
    </div>
  )
}

function DentroDe({ lead, fazer }: { lead: LeadWithOwner; fazer: (r: string, c: Record<string, unknown>) => Promise<void> }) {
  const [q, setQ] = useState('')
  const [achados, setAchados] = useState<SearchHit[]>([])
  const [buscando, setBuscando] = useState(false)
  const pais = dentroDe(lead)
  useEffect(() => {
    if (q.trim().length < 2) { setAchados([]); return }
    const ctl = new AbortController()
    const t = setTimeout(async () => {
      setBuscando(true)
      try {
        const r = await fetch('/api/leads/search', { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ q: q.trim() }), signal: ctl.signal })
        const j = await r.json()
        setAchados(((j.hits || []) as SearchHit[]).filter((h) => fim8(h.lead.phone) !== fim8(lead.phone)).slice(0, 8))
      } catch {} finally { setBuscando(false) }
    }, 300)
    return () => { clearTimeout(t); ctl.abort() }
  }, [q, lead.phone])
  return (
    <div className="absolute top-full right-0 mt-1 w-80 rounded-lg shadow-lg z-40 p-3 flex flex-col gap-2"
         style={{ background: 'var(--wa-panel, #fff)', border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>
      <div className="text-[13px] font-semibold">Pôr esta conversa dentro de…</div>
      <div className="flex items-center gap-2 h-8 px-2 rounded" style={{ border: '1px solid var(--wa-divider)' }}>
        <MagnifyingGlass size={14} />
        <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome ou número da conversa de fora"
               className="flex-1 bg-transparent text-[13px] outline-none" />
        {buscando && <CircleNotch size={14} className="animate-spin" />}
      </div>
      {achados.map((h) => (
        <button key={h.lead.id} type="button" onClick={() => fazer(`Posta dentro de ${h.lead.title || h.lead.phone}`, { dentroDe: { pai: h.lead.id, ligar: true } })}
                className="text-left px-2 py-1.5 rounded text-[13px] hover:bg-black/5 dark:hover:bg-white/10">
          <div className="truncate">{h.lead.title || h.lead.phone}</div>
          <div className="text-[11px] opacity-60">{h.lead.phone}</div>
        </button>
      ))}
      {pais.length > 0 && (
        <div className="border-t pt-2 flex flex-col gap-1" style={{ borderColor: 'var(--wa-divider)' }}>
          <span className="text-[11px] opacity-60">Já está dentro de (final do número):</span>
          {pais.map((p) => (
            <TirarDeDentro key={p} final={p} lead={lead} fazer={fazer} />
          ))}
        </div>
      )}
    </div>
  )
}

function TirarDeDentro({ final, lead, fazer }: { final: string; lead: LeadWithOwner; fazer: (r: string, c: Record<string, unknown>) => Promise<void> }) {
  const [paiId, setPaiId] = useState<string | null>(null)
  useEffect(() => {
    fetch('/api/leads/search', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ q: final }) })
      .then((r) => r.json()).then((j) => {
        const h = ((j.hits || []) as SearchHit[]).find((x) => fim8(x.lead.phone) === final && x.lead.id !== lead.id)
        setPaiId(h?.lead.id || null)
      }).catch(() => {})
  }, [final, lead.id])
  return (
    <div className="flex items-center justify-between text-[12px]">
      <span>…{final}</span>
      <button type="button" disabled={!paiId} onClick={() => paiId && fazer('Tirada de dentro', { dentroDe: { pai: paiId, ligar: false } })}
              className="px-2 py-0.5 rounded disabled:opacity-40" style={{ border: '1px solid var(--wa-divider)' }}>
        Tirar
      </button>
    </div>
  )
}

/** 03/11 (Pedro: "no Parceria ter o botão Enviar para administração"). À tarde, a etapa voltou a ser Fechamento e
 *  Administração ficou só o tipo de contato, igual ao Leads: a conversa sai das abas da Parceria e vai para o Chat
 *  Administração (só o Tel vê). */
export function EnviarParaAdministracaoParceria({ lead, aoMudar }: { lead: LeadWithOwner; aoMudar: (o: Organizado) => void }) {
  const [ocupado, setOcupado] = useState(false)
  const [aviso, setAviso] = useState('')
  const ja = lead.custom_attributes?.tipo_contato === 'administracao'
  return (
    <div className="relative">
      <button type="button" disabled={ocupado || ja}
              className="flex items-center gap-1.5 h-9 px-2.5 rounded-lg text-[13px] font-semibold flex-shrink-0 disabled:opacity-60"
              style={{ border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}
              title="A conversa sai das abas da Parceria e vai para o Chat Administração (só o Tel vê)"
              onClick={async () => {
                setOcupado(true); setAviso('')
                try {
                  aoMudar(await organizar(lead.id, { tipo: 'administracao' }))
                  setAviso('Enviado para a Administração')
                } catch (e: any) { setAviso(e.message || 'Não consegui.') } finally { setOcupado(false); setTimeout(() => setAviso(''), 2500) }
              }}>
        {ocupado ? <CircleNotch size={16} className="animate-spin" /> : <FolderSimpleUser size={16} />}
        <span className="hidden xl:inline">{ja ? 'Em Administração' : 'Enviar para administração'}</span>
      </button>
      {aviso && (
        <span className="absolute top-full right-0 mt-1 text-[12px] px-2 py-1 rounded shadow z-40 whitespace-nowrap"
              style={{ background: 'var(--wa-panel, #fff)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}>{aviso}</span>
      )}
    </div>
  )
}

/** 04/11 (Pedro: "preciso de um botão Enviar para captação", ao lado do Enviar para administração): a conversa ganha a
 *  marca da captação (organizar { captacao: true }) e entra no Chat Captação do Lucas, nos dois números. */
export function EnviarParaCaptacao({ lead, aoMudar }: { lead: LeadWithOwner; aoMudar: (o: Organizado) => void }) {
  const [ocupado, setOcupado] = useState(false)
  const ja = lead.custom_attributes?.conversa_captacao === true
  return (
    <button type="button" disabled={ocupado || ja}
            className="flex items-center gap-1.5 h-9 px-2.5 rounded-lg text-[13px] font-semibold flex-shrink-0 disabled:opacity-60"
            style={{ border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}
            title="A conversa entra no Chat Captação (a aba do Lucas)"
            onClick={async () => {
              setOcupado(true)
              try { aoMudar(await organizar(lead.id, { captacao: true })) }
              catch (e: any) { window.alert(e?.message || 'Não consegui enviar para a captação.') } finally { setOcupado(false) }
            }}>
      {ocupado ? <CircleNotch size={16} className="animate-spin" /> : <HouseLine size={16} />}
      <span className="hidden xl:inline">{ja ? 'Na captação' : 'Enviar para captação'}</span>
    </button>
  )
}
