'use client'

/**
 * A ETAPA NO CARD DO CLIENTE DA CAPTAÇÃO (Pedro, 18/10/2026: "as Etapas da captação não estão lá no número de
 * captação"; depois: "as etapas não atualizam" e "sumiu a aba Tel daí do card lateral").
 *
 * Para quem não é dono da campanha (cliente da OLX, orgânico, ou qualquer conversa do 8595): as etapas da Nay do
 * WhatsApp (385) e, separado por um risco, "Com o Tel" e "Todos" -- os mesmos da campanha (242): Com o Tel cala a Nay
 * para a pessoa; Todos solta. Mesmo desenho do EtapaDaCaptacao: escolher só acende o Salvar.
 *
 * A etapa da OLX é salva por crm_olx_cliente_etapa, que desde a 411 CRIA a linha quando a pessoa não entrou pela Nay
 * (antes devolvia "não é cliente da OLX" e nada mudava). Com o Tel / Todos vão por /api/leads/{id}/captacao-etapa.
 */
import { useCallback, useEffect, useState } from 'react'
import AvisoFlutuante, { type AvisoNaTela } from './AvisoFlutuante'
import { ETAPAS_OLX, fim8, type EtapaOlx } from '@/lib/olxClientes'
import { useOlxClientes, mudarEtapaOlx } from '@/hooks/useOlxClientes'

const DA_NAY = new Set<string>(['filtrar', 'feito_busca', 'imoveis_enviados'])
const PESSOA = [
  { chave: 'com_o_tel', rotulo: 'Com o Tel', titulo: 'A Nay para de responder esta pessoa até voltar para Todos' },
  { chave: 'todos', rotulo: 'Todos', titulo: 'Solta: a Nay volta a atender e a etapa é a dela' },
]

export default function EtapaDoClienteOlx({ telefone, leadId, comOTel, aoMudar }: {
  telefone?: string | null
  leadId: string
  /** a Nay está parada para esta pessoa (Com o Tel) */
  comOTel?: boolean
  aoMudar?: (etapa: string) => void
}) {
  const clientes = useOlxClientes(true)
  const cliente = clientes[fim8(telefone)]
  const etapaOlx: string = cliente?.etapa || 'nova'
  const ondeEsta: string = comOTel ? 'com_o_tel' : etapaOlx
  const [escolhido, setEscolhido] = useState<string>(ondeEsta)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [aviso, setAviso] = useState<AvisoNaTela | null>(null)
  const fecharAviso = useCallback(() => setAviso(null), [])
  useEffect(() => { setEscolhido(ondeEsta); setErro(null) }, [leadId, ondeEsta])
  const mudou = escolhido !== ondeEsta && escolhido !== 'nova'
  const rotulo = (k: string) => ETAPAS_OLX.find((e) => e.chave === k)?.rotulo || PESSOA.find((p) => p.chave === k)?.rotulo || (k === 'nova' ? 'Nova' : k)

  async function salvar() {
    if (!mudou || salvando) return
    setSalvando(true); setErro(null)
    let e: string | null = null
    if (escolhido === 'com_o_tel' || escolhido === 'todos') {
      try {
        const r = await fetch(`/api/leads/${leadId}/captacao-etapa`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: escolhido }),
        })
        const j = await r.json().catch(() => ({} as any))
        if (!r.ok || j?.ok === false) e = j?.mensagem || j?.error || 'o servidor não aceitou a mudança'
      } catch (err: any) { e = err?.message || 'não salvou' }
    } else {
      e = await mudarEtapaOlx(telefone || '', escolhido as EtapaOlx)
      // quem estava Com o Tel e ganhou uma etapa da Nay: solta a Nay junto, senão a etapa nova não vale
      if (!e && comOTel) {
        try {
          await fetch(`/api/leads/${leadId}/captacao-etapa`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: 'todos' }) })
        } catch { /* a etapa da OLX já foi salva; o card recarrega e mostra o que ficou */ }
      }
    }
    setSalvando(false)
    if (e) { setErro(e); setAviso({ tom: 'erro', titulo: `Não salvou: ${rotulo(escolhido)}`, texto: `${e}. Nada mudou; tente de novo.` }); return }
    setAviso({ tom: 'ok', titulo: `Salvo: ${rotulo(escolhido)}`, texto: escolhido === 'com_o_tel' ? 'A Nay parou para esta pessoa.' : escolhido === 'todos' ? 'A Nay volta a atender.' : 'A etapa mudou; a lista já mostra.' })
    aoMudar?.(escolhido)
  }

  return (
    <div className="px-4 py-3 border-b border-[var(--chat-border)]">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-secondary)] mb-2">Etapa da captação</p>
      <div className="flex flex-wrap items-center gap-1.5">
        {ETAPAS_OLX.map((e) => {
          const daNay = DA_NAY.has(e.chave)
          return (
            <button key={e.chave} type="button" disabled={salvando} onClick={() => setEscolhido(e.chave)}
                    title={daNay ? `${e.titulo} (a Nay põe aqui sozinha; na lista, quem está nestas três fica em Todos)` : e.titulo}
                    className={`wa-fase wa-fase--etapa${daNay ? '' : ' wa-fase--rosa'}${escolhido === e.chave ? ' wa-fase--on' : ''}`}>
              {e.rotulo}
            </button>
          )
        })}
        <span className="wa-fase__risco" aria-hidden="true" />
        {PESSOA.map((p) => (
          <button key={p.chave} type="button" disabled={salvando} onClick={() => setEscolhido(p.chave)} title={p.titulo}
                  className={`wa-fase wa-fase--${p.chave === 'com_o_tel' ? 'pessoa' : 'etapa'}${escolhido === p.chave ? ' wa-fase--on' : ''}`}>
            {p.rotulo}
          </button>
        ))}
      </div>
      <div className="mt-2 flex items-center gap-2">
        <button type="button" onClick={salvar} disabled={!mudou || salvando} className="wa-botao-principal">
          {salvando ? 'Salvando…' : 'Salvar'}
        </button>
        {mudou && !salvando && <span className="text-[11px] text-[var(--chat-text-secondary)]">vai para {rotulo(escolhido)} ao salvar</span>}
      </div>
      {erro && <p className="mt-2 text-[11.5px] leading-4 text-red-500">{erro}</p>}
      {!erro && (
        <p className="mt-2 text-[11px] text-[var(--chat-text-secondary)]">
          {comOTel
            ? 'A Nay está parada para esta pessoa (Com o Tel). Escolha uma etapa ou Todos e salve para soltar.'
            : cliente
              ? (etapaOlx === 'nova' ? 'Chegou agora: a Nay ainda não começou o filtro.' : `Hoje em ${rotulo(etapaOlx)}${cliente.humano ? ' · alguém da equipe escreveu, a Nay saiu' : ''}.`)
              : 'Ainda sem etapa para este número; escolha uma e salve.'}
        </p>
      )}
      <AvisoFlutuante aviso={aviso} aoFechar={fecharAviso} />
    </div>
  )
}
