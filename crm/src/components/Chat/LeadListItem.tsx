'use client'

import { memo } from 'react'
import { LeadWithOwner, SearchHit } from '@/lib/types'
import { PushPin, Checks, User, Robot } from '@phosphor-icons/react'
import { formatPhone, renderSnippet } from '@/lib/utils'
import type { Atendente } from '@/lib/atendentes'
import type { EstadoDaNay } from '@/lib/tiposNay'
import type { DonoNaLista, MarcaDaNay } from '@/lib/tiposNay'

/**
 * Uma linha da lista de conversas, no desenho do WhatsApp Web (29/09/2026):
 * foto, nome e hora em cima; prévia da última mensagem embaixo, com o tique
 * quando fomos nós que falamos por último e a bolinha verde quando há
 * mensagem não lida.
 *
 * Na Parceria entram as marcas da Nay antes da prévia -- "Tel" (o Tel está
 * com a conversa), "Visita" (com a data) e "Proprietário" --, as mesmas dos
 * filtros de cima. Nas outras linhas, quem está atendendo e as etiquetas.
 */
interface LeadListItemProps {
  lead: LeadWithOwner
  isSelected: boolean
  onContextMenu: (e: React.MouseEvent, lead: LeadWithOwner) => void
  timeStr: string
  hit?: SearchHit
  query?: string
  /**
   * Segunda via do clique. Quem decide normalmente é a lista (delegação em
   * LeadList, que sabe qual linha foi apertada mesmo se a lista se reordenar
   * no meio); este onClick é rede de segurança.
   */
  onClick: (lead: LeadWithOwner) => void
  /** Quem está atendendo — etiqueta colorida com o nome, controle interno. */
  atendente?: Atendente
  /** O que a Nay sabe desta conversa (só na Parceria) */
  marca?: MarcaDaNay
  /** captação: o dono e o imóvel ("Evandro Prop Kopenhagen", Pedro 29/09) */
  dono?: DonoNaLista
  /** a chave geral da Nay -- com ela a linha mostra o robô (só na Parceria) */
  nay?: EstadoDaNay | null
}

const RECEBIDO = ['lead']

/** O primeiro nome cadastrado na captação ("Evandro Prop Kopenhagen"); o que veio
 *  TODO EM MAIÚSCULA vira "Tadeu". O nome inteiro fica no title da linha. */
function nomeDoDono(nome: string | null): string {
  const palavras = (nome || '').trim().split(/\s+/).filter((p) => p.replace(/\P{L}/gu, '').length >= 2)
  const primeiro = palavras.find((p) => !/^(sr|sra|dr|dra)\.?$/i.test(p)) || palavras[0] || ''
  if (!primeiro || primeiro !== primeiro.toUpperCase()) return primeiro
  return primeiro.charAt(0) + primeiro.slice(1).toLowerCase()
}

function quandoCurto(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const hoje = new Date()
  const dia = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
  const dif = Math.round((dia(d) - dia(hoje)) / 86400000)
  const hora = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
  if (dif === 0) return `hoje ${hora}`
  if (dif === 1) return `amanhã ${hora}`
  return `${d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} ${hora}`
}

/*
 * O ROBÔ DA NAY (Pedro, 29/09/2026): "o robô não é do lado da pessoa na aba
 * conversas e sim lá na lista de conversas, ele fica no canto da foto da
 * pessoa, inferior esquerdo" -- verde a Nay atendendo, vermelho parada (a chave
 * geral da Nay, ou o Tel / alguém da equipe com a conversa). Só na Parceria.
 */
function Avatar({ lead, robo }: { lead: LeadWithOwner; robo?: { parada: boolean; texto: string } | null }) {
  return (
    <div className="relative flex-shrink-0">
      <div className="w-[49px] h-[49px] rounded-full overflow-hidden flex items-center justify-center"
           style={{ backgroundColor: 'var(--wa-row-selected)' }}>
        {lead.avatar_url ? (
          <img src={lead.avatar_url} alt="" loading="lazy" decoding="async" className="w-full h-full object-cover" />
        ) : (
          <User size={28} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.55 }} />
        )}
      </div>
      {robo && (
        <span className="wa-robo-selo" style={{ ['--cor' as string]: robo.parada ? 'var(--wa-tag-tel)' : 'var(--wa-green)' }}
              title={robo.texto} aria-label={robo.texto} role="img">
          <Robot size={11} weight="fill" />
        </span>
      )}
    </div>
  )
}

const LeadListItem = ({ lead, isSelected, onClick, onContextMenu, timeStr, hit, query, atendente, marca, nay, dono }: LeadListItemProps) => {
  const robo = nay === undefined ? null : !nay ? { parada: true, texto: 'Lendo a Nay…' }
    : !nay.ligada ? { parada: true, texto: `Nay parada: ${nay.motivo || 'desligada'}` }
    : marca?.telAtendendo ? { parada: true, texto: `Nay parada nesta conversa: ${marca.telMotivo || 'o Tel está com a conversa'}` }
    : { parada: false, texto: 'Nay atendendo esta conversa' }
  // Conversa importada não tem prévia (a Z-API não traz mensagem antiga).
  const importada = (lead.custom_attributes as Record<string, unknown> | undefined)?.origem === 'conversa_whatsapp'
  const semPrevia = importada ? 'Conversa do WhatsApp · sem histórico aqui' : lead.last_activity_type ? '' : 'Sem mensagens'
  const previa = lead.last_message_content || semPrevia
  const fomosNos = !!lead.last_message_sender_type && !RECEBIDO.includes(lead.last_message_sender_type)
  const naoLida = !!lead.is_unread

  return (
    <button
      type="button"
      data-lead-id={lead.id}
      onClick={() => onClick(lead)}
      onContextMenu={(e) => onContextMenu(e, lead)}
      className={`wa-linha ${isSelected ? 'wa-linha--sel' : ''}`}
    >
      <Avatar lead={lead} robo={robo} />
      <div className="flex-1 min-w-0 py-[11px]">
        <div className="flex items-baseline justify-between gap-2">
          <span className="flex items-center gap-1.5 min-w-0">
            {dono ? (
              /* captação (Pedro, 29/09): [nome] [Prop] [condomínio] */
              <span className="flex items-baseline gap-1.5 min-w-0"
                    title={[dono.nome, dono.condominio, dono.codigo ? `#${dono.codigo}` : null, dono.bairro].filter(Boolean).join(' · ')}>
                <span className={`wa-nome truncate flex-shrink ${naoLida ? 'font-semibold' : ''}`}>{nomeDoDono(dono.nome) || formatPhone(lead.title)}</span>
                <span className="wa-marca flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}>Prop</span>
                {dono.condominio && <span className="wa-dono-imovel truncate">{dono.condominio}{dono.imoveis > 1 ? ` +${dono.imoveis - 1}` : ''}</span>}
              </span>
            ) : (
              <span className={`wa-nome truncate ${naoLida ? 'font-semibold' : ''}`}>{formatPhone(lead.title)}</span>
            )}
            {/* a etiqueta da etapa saiu (Pedro, 29/09: "retira as tags de recebeu
                imóvel, não tá bacana"); a etapa virou a trilha do card do contato */}
          </span>
          <span className="text-[12px] leading-4 flex-shrink-0"
                style={{ color: naoLida ? 'var(--wa-unread)' : 'var(--wa-text-2)', fontWeight: naoLida ? 600 : 400 }}>
            {timeStr}
          </span>
        </div>

        <div className="flex items-center gap-1.5 mt-[2px] min-w-0">
          {marca?.telAtendendo && (
            <span className="wa-marca" style={{ color: 'var(--wa-text-2)' }} title={marca.telMotivo || 'O Tel está com esta conversa'}>
              {(marca.telMotivo || '').startsWith('Rayssa:') ? 'Rayssa' : 'Tel'}
            </span>
          )}
          {marca?.visitaAberta && (
            <span className="wa-marca" style={{ color: 'var(--wa-text-2)' }} title="Visita em andamento">
              Visita {quandoCurto(marca.visitaQuando)}
            </span>
          )}
          {/* Pedro, 30/09: "retire a tag de corretor parceiro do chat Todos, deixe só a
              tag proprietários e equipe" -- quase todo mundo é corretor, a etiqueta
              não diferenciava ninguém. O CRECI continua no card do contato. */}
          {(marca?.equipe || marca?.acompanhante) && (
            <span className="wa-marca" style={{ color: 'var(--wa-text-2)' }} title="Da equipe da Imob Easy">Equipe</span>
          )}
          {marca?.proprietario && (
            <span className="wa-marca" style={{ color: 'var(--wa-text-2)' }}
                  title={marca.imoveisDoDono.length ? `Proprietário: ${marca.imoveisDoDono.join(', ')}` : 'Proprietário'}>
              Proprietário
            </span>
          )}
          {!marca && (lead.lead_tags || []).slice(0, 2).map((lt: any) => lt.tag && (
            <span key={lt.tag_id} className="wa-marca" style={{ color: 'var(--wa-text-2)' }}>
              {lt.tag.name}
            </span>
          ))}
          {fomosNos && previa && <Checks size={16} weight="bold" className="flex-shrink-0" style={{ color: 'var(--wa-text-2)' }} />}
          <span className={`wa-previa truncate ${naoLida ? 'font-medium' : ''}`}
                style={naoLida ? { color: 'var(--wa-text)' } : undefined}>
            {previa}
          </span>
          <span className="ml-auto flex items-center gap-1.5 pl-1 flex-shrink-0">
            {lead.is_pinned && <PushPin size={16} weight="fill" className="-rotate-45" style={{ color: 'var(--wa-text-2)' }} />}
            {naoLida && (
              /* o número, como no WhatsApp (01/10): é a mesma conta das bolinhas
                 das etapas, então dá para somar com o olho e conferir */
              <span className="wa-badge" aria-label={`${lead.nao_lidas || 1} sem ler`}>
                {(lead.nao_lidas || 1) > 99 ? '99+' : (lead.nao_lidas || 1)}
              </span>
            )}
          </span>
        </div>

        {hit?.matchType === 'message' && hit.snippet && (
          <div className="wa-previa text-[13px] italic mt-0.5 line-clamp-1">
            <span dangerouslySetInnerHTML={{ __html: renderSnippet(hit.snippet, query ?? '') }} />
          </div>
        )}
      </div>
    </button>
  )
}

export default memo(LeadListItem, (a, b) => (
  a.lead.id === b.lead.id &&
  a.lead.updated_at === b.lead.updated_at &&
  a.lead.title === b.lead.title &&
  a.lead.avatar_url === b.lead.avatar_url &&
  a.lead.is_unread === b.lead.is_unread &&
  a.lead.nao_lidas === b.lead.nao_lidas &&
  a.lead.is_pinned === b.lead.is_pinned &&
  a.lead.last_message_content === b.lead.last_message_content &&
  a.lead.last_message_sender_type === b.lead.last_message_sender_type &&
  (a.lead.lead_tags?.length ?? 0) === (b.lead.lead_tags?.length ?? 0) &&
  a.isSelected === b.isSelected &&
  a.atendente?.id === b.atendente?.id &&
  a.timeStr === b.timeStr &&
  a.query === b.query &&
  a.hit?.matchType === b.hit?.matchType &&
  a.hit?.snippet === b.hit?.snippet &&
  a.marca?.telAtendendo === b.marca?.telAtendendo &&
  a.marca?.visitaAberta === b.marca?.visitaAberta &&
  a.marca?.visitaQuando === b.marca?.visitaQuando &&
  a.marca?.proprietario === b.marca?.proprietario &&
  a.marca?.corretor === b.marca?.corretor &&
  a.marca?.etapa === b.marca?.etapa &&
  a.dono?.nome === b.dono?.nome &&
  a.dono?.condominio === b.dono?.condominio &&
  a.nay?.ligada === b.nay?.ligada && a.nay === undefined === (b.nay === undefined)
))
