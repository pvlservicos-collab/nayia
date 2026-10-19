'use client'

/**
 * A ETAPA DO CLIENTE DA OLX NO CARD DA CAPTAÇÃO (Pedro, 18/10/2026: "as Etapas da captação ... não estão lá no número
 * de captação"). Até aqui a etapa do cliente da OLX (quem chegou pelo anúncio ou escreveu por conta própria, migração
 * 385/390) só se mudava pelo botão direito na lista; o card só tinha etapa para o dono da campanha (EtapaDaCaptacao).
 *
 * Mesmo desenho do EtapaDaCaptacao: escolher só acende o Salvar. As três primeiras etapas (Filtrar, Feito busca,
 * Imóveis enviado) são da Nay, ela mesma avança; a equipe escolhe Visita, Proprietários, Fechamento e Finalizados.
 */
import { useCallback, useEffect, useState } from 'react'
import AvisoFlutuante, { type AvisoNaTela } from './AvisoFlutuante'
import { ETAPAS_OLX, fim8, type EtapaOlx } from '@/lib/olxClientes'
import { useOlxClientes, mudarEtapaOlx } from '@/hooks/useOlxClientes'

const DA_NAY = new Set<string>(['filtrar', 'feito_busca', 'imoveis_enviados'])

export default function EtapaDoClienteOlx({ telefone, aoMudar }: { telefone?: string | null; aoMudar?: (etapa: EtapaOlx) => void }) {
  const clientes = useOlxClientes(true)
  const cliente = clientes[fim8(telefone)]
  const ondeEsta: string = cliente?.etapa || 'nova'
  const [escolhido, setEscolhido] = useState<string>(ondeEsta)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [aviso, setAviso] = useState<AvisoNaTela | null>(null)
  const fecharAviso = useCallback(() => setAviso(null), [])
  useEffect(() => { setEscolhido(ondeEsta); setErro(null) }, [telefone, ondeEsta])
  const mudou = escolhido !== ondeEsta && escolhido !== 'nova'
  const rotulo = (k: string) => ETAPAS_OLX.find((e) => e.chave === k)?.rotulo || (k === 'nova' ? 'Nova' : k)

  async function salvar() {
    if (!mudou || salvando || escolhido === 'nova') return
    setSalvando(true); setErro(null)
    const e = await mudarEtapaOlx(telefone || '', escolhido as EtapaOlx)
    setSalvando(false)
    if (e) { setErro(e); setAviso({ tom: 'erro', titulo: `Não salvou: ${rotulo(escolhido)}`, texto: `${e}. Nada mudou; tente de novo.` }); return }
    setAviso({ tom: 'ok', titulo: `Salvo: ${rotulo(escolhido)}`, texto: 'A etapa do cliente mudou; a lista já mostra.' })
    aoMudar?.(escolhido as EtapaOlx)
  }

  return (
    <div className="px-4 py-3 border-b border-[var(--chat-border)]">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-secondary)] mb-2">Etapa da captação</p>
      <div className="flex flex-wrap items-center gap-1.5">
        {ETAPAS_OLX.map((e) => {
          const daNay = DA_NAY.has(e.chave)
          return (
            <button key={e.chave} type="button" disabled={salvando}
                    onClick={() => setEscolhido(e.chave)}
                    title={daNay ? `${e.titulo} (a Nay põe aqui sozinha; quem está nestas três fica em Todos na lista)` : e.titulo}
                    className={`wa-fase wa-fase--etapa${daNay ? '' : ' wa-fase--rosa'}${escolhido === e.chave ? ' wa-fase--on' : ''}`}>
              {e.rotulo}
            </button>
          )
        })}
      </div>
      <div className="mt-2 flex items-center gap-2">
        <button type="button" onClick={salvar} disabled={!mudou || salvando} className="wa-botao-principal">
          {salvando ? 'Salvando…' : 'Salvar'}
        </button>
        {mudou && !salvando && escolhido !== 'nova' && (
          <span className="text-[11px] text-[var(--chat-text-secondary)]">vai para {rotulo(escolhido)} ao salvar</span>
        )}
      </div>
      {erro && <p className="mt-2 text-[11.5px] leading-4 text-red-500">{erro}</p>}
      {!erro && (
        <p className="mt-2 text-[11px] text-[var(--chat-text-secondary)]">
          {cliente
            ? (ondeEsta === 'nova' ? 'Chegou agora: a Nay ainda não começou o filtro.' : `Hoje em ${rotulo(ondeEsta)}${cliente.humano ? ' · alguém da equipe escreveu, a Nay saiu' : ''}.`)
            : 'Ainda sem etapa da Nay para este número; escolha uma e salve.'}
        </p>
      )}
      <AvisoFlutuante aviso={aviso} aoFechar={fecharAviso} />
    </div>
  )
}
