'use client'

/**
 * O MODO V3 (Pedro, 04/11/2026, o pedido do Atendimento da v3: "deixar fácil identificar de qual fila é o contato e quem
 * está respondendo agora, removendo informação repetida ... só reorganize a interface"). A tela da v3 (ChatV3) liga este
 * contexto; os componentes de sempre (o balão da ActivityTimeline, o cabeçalho da ChatWindow, a caixa da
 * ActivityComposer) leem e mudam só o desenho. Fora da v3 o valor é false e nada muda.
 *
 * As cores fixas do pedido (as mesmas em todo lugar).
 */
import { createContext, useContext } from 'react'

export const ModoV3 = createContext(false)
export const useModoV3 = () => useContext(ModoV3)

export type FilaV3 = 'locacao' | 'venda' | 'corretores' | 'proprietarios'
export const FILAS_V3: Record<FilaV3, { rotulo: string; tipo: string; quem: string; cor: string }> = {
  locacao: { rotulo: 'Locação', tipo: 'Lead locação', quem: 'Diego', cor: '#1D9E75' },
  venda: { rotulo: 'Venda', tipo: 'Lead venda', quem: 'Rayssa', cor: '#D85A30' },
  corretores: { rotulo: 'Corretores', tipo: 'Corretor', quem: 'Nay', cor: '#D4537E' },
  proprietarios: { rotulo: 'Proprietários', tipo: 'Proprietário', quem: 'Equipe', cor: '#D97706' },
}

/* AS ETAPAS DO LEAD = as etapas reais da Nay Leads (Pedro, 04/11: "uma única fonte de verdade para as etapas"; "Nomes da
   Nay"). Mudar na barra muda a etapa dela (/api/captacao/olx-clientes, crm_olx_cliente_etapa), a mesma do card antigo.
   Proprietários, Fechamento e Finalizados da Nay vêm depois da visita: a barra fica cheia até Visita e o nome é o dela. */
export const ETAPAS_V3 = [
  { chave: 'filtrar', curto: 'Filtrar', rotulo: 'Filtrar', cor: '#378ADD' },
  { chave: 'feito_busca', curto: 'Feito busca', rotulo: 'Feito busca', cor: '#7F77DD' },
  { chave: 'imoveis_enviados', curto: 'Imóveis enviados', rotulo: 'Imóveis enviados', cor: '#639922' },
  { chave: 'visita', curto: 'Visita', rotulo: 'Visita', cor: '#EF9F27' },
] as const
export type EtapaDaNay = 'nova' | 'filtrar' | 'feito_busca' | 'imoveis_enviados' | 'visita' | 'proprietarios' | 'fechamento' | 'finalizado'
/** até onde a barra enche (-1: a Nay ainda não começou) */
export function indiceDaEtapa(e: string | null | undefined): number {
  const i = ETAPAS_V3.findIndex((x) => x.chave === e)
  if (i >= 0) return i
  return e === 'proprietarios' || e === 'fechamento' || e === 'finalizado' ? 3 : -1
}
export const NOME_DA_ETAPA: Record<string, string> = {
  nova: 'Chegou agora', filtrar: 'Filtrar', feito_busca: 'Feito busca', imoveis_enviados: 'Imóveis enviados', visita: 'Visita',
  proprietarios: 'Com o proprietário', fechamento: 'Fechamento', finalizado: 'Finalizado',
}

/** o selo de quem responde: IA (roxo) ou a pessoa (verde); o claro e o escuro estão no globals.css (.v3-selo-*) */
export const CLASSE_DO_AUTOR = { ia: 'v3-ia', humano: 'v3-humano', parada: 'v3-parada' } as const

/* A EQUIPE (Pedro, 04/11: "na nossa equipe só tem eu Pedro, Tel, Rayssa, Lucas e Diego, todo o resto está com a tag equipe
   errada"): o selo só leva o nome de um destes; fora deles não há "Equipe" genérico */
export const EQUIPE_V3 = ['pedro', 'tel', 'rayssa', 'lucas', 'diego'] as const
