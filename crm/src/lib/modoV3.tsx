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

export type FilaV3 = 'locacao' | 'venda' | 'corretores'
export const FILAS_V3: Record<FilaV3, { rotulo: string; tipo: string; quem: string; cor: string }> = {
  locacao: { rotulo: 'Locação', tipo: 'Lead locação', quem: 'Diego', cor: '#1D9E75' },
  venda: { rotulo: 'Venda', tipo: 'Lead venda', quem: 'Rayssa', cor: '#D85A30' },
  corretores: { rotulo: 'Corretores', tipo: 'Corretor', quem: 'Nay', cor: '#D4537E' },
}

export const ETAPAS_V3 = [
  { curto: 'Começar', rotulo: 'Começar', cor: '#888780' },
  { curto: 'Filtrado', rotulo: 'Filtrado', cor: '#378ADD' },
  { curto: 'Em atend.', rotulo: 'Em atendimento', cor: '#7F77DD' },
  { curto: 'Enviado opção', rotulo: 'Enviado opção', cor: '#639922' },
  { curto: 'Visitas', rotulo: 'Visitas', cor: '#EF9F27' },
] as const

/** o selo de quem responde: IA (roxo) ou a pessoa (verde); o claro e o escuro estão no globals.css (.v3-selo-*) */
export const CLASSE_DO_AUTOR = { ia: 'v3-ia', humano: 'v3-humano' } as const
