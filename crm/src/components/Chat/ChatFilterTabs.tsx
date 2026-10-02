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
  /**
   * PARCERIA (Tel, 30/09/2026): "um menu único tipo um tudo com cada parte
   * selecionável e visivelmente selecionada com aspecto 3d ... os 3 primeiros
   * são etapas e devem ficar destacadas de tel e rayssa".
   *
   * 'etapa'  -> Todos, Visitas, Proprietários: onde a conversa ESTÁ.
   * 'pessoa' -> Tel, Rayssa: quem está atendendo.
   * Sem grupo, o filtro sai como sempre saiu (captação, oficial).
   */
  grupo?: 'etapa' | 'pessoa'
  /** borda esquerda rosa: as etapas para onde a conversa VAI (Tel, 30/09) */
  rosa?: boolean
  /**
   * A BOLINHA DA ETAPA (Pedro, 01/10/2026): "as bolinhas nas etapas do WhatsApp
   * Parceria seja a contagem real de mensagens não lidas em todas as etapas".
   *
   * Era "quem falta responder" (30/09) e passou a ser o que o WhatsApp mostra:
   * mensagens sem ler. Em TODAS as etapas, inclusive Todos. Soma o
   * `nao_lidas` de cada conversa da etapa (/api/leads).
   */
  naoLidas?: number
  /**
   * A BOLINHA DAS ETAPAS DA PARCERIA (Pedro, 02/10/2026): quantas PESSOAS têm
   * mensagem sem ler, não quantas mensagens. Quando vem, é ela que aparece.
   */
  pessoas?: number
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
      {filtros.map((f, i) => {
        const on = ativo === f.chave
        // A barrinha que separa as etapas de quem atende: só onde o grupo muda.
        const separa = f.grupo === 'pessoa' && filtros[i - 1]?.grupo === 'etapa'
        const classe = f.grupo
          ? `wa-fase wa-fase--${f.grupo} ${f.rosa ? 'wa-fase--rosa' : ''} ${on ? 'wa-fase--on' : ''}`
          : `wa-chip ${on ? 'wa-chip--on' : ''}`
        return (
          <span key={f.chave} className="contents">
            {separa && <span className="wa-fase__risco" aria-hidden="true" />}
            <button
              type="button"
              role="tab"
              aria-selected={on}
              title={f.titulo}
              onClick={() => aoMudar(on && f.chave !== 'all' ? 'all' : f.chave)}
              className={classe}
            >
              {f.cor && <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: f.cor }} />}
              {f.rotulo}
              {f.contagem !== undefined && f.contagem > 0 && <span className="wa-chip__n">{f.contagem}</span>}
              {!!f.pessoas && (
                <span className="wa-fase__faltam" title={`${f.pessoas} pessoa${f.pessoas > 1 ? 's' : ''} para responder`}>
                  {f.pessoas > 99 ? '99+' : f.pessoas}
                </span>
              )}
              {!f.pessoas && !!f.naoLidas && (
                <span className="wa-fase__faltam" title={`${f.naoLidas} mensage${f.naoLidas > 1 ? 'ns' : 'm'} sem ler`}>
                  {f.naoLidas > 99 ? '99+' : f.naoLidas}
                </span>
              )}
            </button>
          </span>
        )
      })}
    </div>
  )
}

export default memo(ChatFilterTabs)
