'use client'

import { memo } from 'react'

/**
 * Os filtros de cima da lista, no desenho do WhatsApp Web (29/09/2026).
 *
 * Quem decide QUAIS filtros aparecem é a lista (LeadList), porque muda por
 * linha:
 *   parceria  -> Todas · Não lidas · Proprietários · Visitas · Tel
 *                (Pedro, 29/09: "troca por TODOS, Não lidos, Proprietários
 *                 (filtra conforme o banco de dados, o sistema já sabe quem
 *                 é), VISITAS, TEL (TAG TEL QUE É O TEL ATENDENDO)")
 *   captação / oficial -> Todas · as etiquetas do funil · quem está atendendo
 *                (Tel, 26/09 e 28/09) -- só o desenho mudou.
 *
 * Clicar no filtro ativo volta para "Todas", como no WhatsApp.
 */
export type ChatTab = string

export interface FiltroDaLista {
  chave: ChatTab
  rotulo: string
  contagem?: number
  /** cor própria (etiqueta, atendente) -- vira um pontinho antes do nome */
  cor?: string
  titulo?: string
}

/** mantido para quem ainda importa o tipo antigo */
export interface EtiquetaDaAba {
  id: string
  nome: string
  cor: string
}

interface ChatFilterTabsProps {
  ativo: ChatTab
  aoMudar: (tab: ChatTab) => void
  filtros: FiltroDaLista[]
}

function ChatFilterTabs({ ativo, aoMudar, filtros }: ChatFilterTabsProps) {
  return (
    /* rola de lado com a barrinha e com a rodinha do mouse (Pedro, 29/09:
       "põe uma barrinha para mexer para o lado as tags, porque não tem") */
    <div className="flex items-center gap-2 px-4 pb-2 pt-0.5 overflow-x-auto wa-rolagem-x" role="tablist"
         onWheel={(e) => {
           const el = e.currentTarget
           if (el.scrollWidth <= el.clientWidth || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return
           el.scrollLeft += e.deltaY
         }}>
      {filtros.map((f) => {
        const on = ativo === f.chave
        return (
          <button
            key={f.chave}
            type="button"
            role="tab"
            aria-selected={on}
            title={f.titulo}
            onClick={() => aoMudar(on && f.chave !== 'all' ? 'all' : f.chave)}
            className={`wa-chip ${on ? 'wa-chip--on' : ''}`}
          >
            {f.cor && <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: f.cor }} />}
            {f.rotulo}
            {f.contagem !== undefined && f.contagem > 0 && <span className="wa-chip__n">{f.contagem}</span>}
          </button>
        )
      })}
    </div>
  )
}

export default memo(ChatFilterTabs)
