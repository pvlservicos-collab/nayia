'use client'

import { memo } from 'react'
import { LeadWithOwner, SearchHit } from '@/lib/types'
import { PushPin, Checks, User, Robot, CaretDown } from '@phosphor-icons/react'
import { formatPhone, renderSnippet } from '@/lib/utils'
import type { Atendente } from '@/lib/atendentes'
import type { EstadoDaNay } from '@/lib/tiposNay'
import type { DonoNaLista, MarcaDaNay } from '@/lib/tiposNay'
import { quandoCurtoEmManaus } from '@/lib/fusoDeManaus'
import { nayEmPausa } from '@/lib/etapaDaParceria'
import { PASSOS_DA_NAY } from '@/lib/olxClientes'
import type { NayLeadsComDono } from '@/hooks/useNayLeadsComDono'
import EtiquetasDoCard from './EtiquetasDoCard'

/* 03/10: quem escreve à mão pausa a Nay por 30 min, e a conversa fica na aba dela */
const TEXTO_DA_PAUSA = 'Nay em pausa: alguém escreveu à mão nesta conversa, e ela espera 30 minutos antes de voltar a responder'

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
  /** WhatsApp Leads (20/10): as etiquetas que são aba (as etapas) aparecem antes das outras na linha */
  etiquetasEmDestaque?: string[]
  /** Oficial (Pedro, 24/10): o contato já mandou mensagem (respondeu ao disparo); a linha ganha um verde leve da esquerda */
  respondeu?: boolean
  /** Oficial (Pedro, 26/10: "as tags lá na API oficial, lá onde tem 2 filtrado ... substituir por tags personalizadas
   *  coloridas"): as etiquetas coloridas na linha e o "+" que põe, tira e cria sem abrir o card */
  etiquetasColoridas?: boolean
  /** Parceria (Pedro, 02/11: "eu quero a tag, ex corretor, e as tags personalizadas do menu etiqueta, não essas etapas da Nay"):
   *  embaixo do nome, as etiquetas da equipe com a cor delas, sem as etapas */
  tagsDaEquipe?: boolean
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
  /** Parceria (492, Pedro 24/10): a Nay Leads está conversando com este proprietário por aqui; a linha fica roxa */
  nayLeads?: NayLeadsComDono
  /** WhatsApp Leads (Pedro, 26/10): quem veio da OLX (é cliente, não dono) -- a linha fica azul e ganha a etiqueta Cliente */
  clienteOlx?: boolean
  /** WhatsApp Leads (517, Pedro 29/10): este lead tem contatos relacionados embaixo (a bolinha e a setinha) */
  relacionados?: { n: number; aberto: boolean; semLer: boolean; avatares: (string | null)[] }
  aoAlternarRelacionados?: (leadId: string) => void
  /** 517: esta linha é um contato relacionado, aninhado embaixo do lead ("Relacionado · #9051") */
  relacao?: string
  /** WhatsApp Leads (520, Pedro 29/10): o passo da Nay com este lead (1 a 5) e a etapa dela -- a barrinha embaixo */
  passoDaNay?: { passo: number; etapa: string }
  /** 29/10 (Pedro: "deixa só a tag OLX e se é venda ou locação embaixo do nome"): a finalidade que a Nay entendeu */
  finalidadeDoCliente?: string | null
  /** 520: de onde veio o cliente da Nay Leads -- 'olx' mostra "OLX" no lugar do antigo "Cliente" */
  origemDoCliente?: string | null
  /** 30/10 (Pedro): no "Proprietários e corretores" do Leads, a etiqueta de cada um (corretor a Nay atende; dono, não) */
  papelNoLeads?: 'corretor' | 'proprietario' | null
  /** 03/11 (Pedro: "uma cor para cada tipo de conversa"): o tipo de contato (Cliente, Corretor, Administração...) -- a faixa
   *  colorida à esquerda e o nome dele embaixo */
  tipoDoContato?: { nome: string; cor: string } | null
  /** 03/11: a conversa é de outra linha e aparece nesta aba (misto): "Falando pelo número Parceria" em cima */
  faixaDaLinha?: string | null
}

const RECEBIDO = ['lead']

/** O primeiro nome cadastrado na captação ("Evandro Prop Kopenhagen"); o que veio
 *  TODO EM MAIÚSCULA vira "Tadeu". O nome inteiro fica no title da linha. */
export function nomeDoDono(nome: string | null): string {
  const palavras = (nome || '').trim().split(/\s+/).filter((p) => p.replace(/\P{L}/gu, '').length >= 2)
  const primeiro = palavras.find((p) => !/^(sr|sra|dr|dra)\.?$/i.test(p)) || palavras[0] || ''
  if (!primeiro || primeiro !== primeiro.toUpperCase()) return primeiro
  return primeiro.charAt(0) + primeiro.slice(1).toLowerCase()
}

/** O imóvel do dono, do jeito que a lista e o cabeçalho mostram: "Kopenhagen #3050 +1".
 *  Pedro, 13/10/2026: "tem uns imóveis que no disparo não aparece o código ... os imóveis comerciais". A tela só
 *  mostrava o nome do CONDOMÍNIO: imóvel sem condomínio (prédio, sala, casa em via pública; 21 conversas da Oficial
 *  nesse dia) ficava sem nada ou com um "—", e o código só existia no balãozinho do mouse. Agora, sem condomínio,
 *  entra o tipo e o bairro, e o código aparece sempre que o dono tem imóvel. */
export function imovelDoDono(dono: { condominio: string | null; codigo: string | null; tipo: string | null; bairro: string | null; imoveis: number } | null | undefined): string {
  if (!dono) return ''
  const condo = (dono.condominio || '').trim()
  const temCondo = !!condo && !/^[—–-]+$/.test(condo) && !/n[aã]o identificad/i.test(condo)
  const onde = temCondo ? condo : [dono.tipo, dono.bairro].map((x) => (x || '').trim()).filter(Boolean).join(' ')
  const codigo = (dono.codigo || '').trim()
  if (!onde && !codigo) return ''
  return [onde, codigo ? `#${codigo}` : ''].filter(Boolean).join(' ') + (dono.imoveis > 1 ? ` +${dono.imoveis - 1}` : '')
}

/** As etiquetas que são ETAPA (do funil, da Nay ou da campanha): não são as personalizadas do menu Etiquetas. */
const ETAPA_COMO_TAG = new Set(['recebeu mensagem', 'recebeu imóvel', 'em atendimento', 'em andamento', 'com o tel', 'sem resposta',
  'não respondeu', 'respondeu', 'disponível', 'disponíveis', 'alugado', 'alugados', 'vendido', 'já vendeu', 'quer vender',
  'tem outro imóvel', 'mandou os dados', 'atualizou cadastro do seu imóvel', 'sugeriu outro imóvel', 'follow up', 'visita',
  'visitas', 'fechamento', 'cadastrando', 'finalizados', 'filtrado', 'enviado opção', 'enviado opções'])
export const ehEtapaComoTag = (nome: string) => /^nay:/i.test(nome) || /^\d+\s/.test(nome) || ETAPA_COMO_TAG.has(nome.trim().toLowerCase())

/** As etiquetas da linha com as de destaque (a etapa, no WhatsApp Leads) na frente; o resto na ordem de sempre. */
function emDestaquePrimeiro<T extends { tag_id: string }>(lista: T[], destaque?: string[]): T[] {
  if (!destaque?.length) return lista
  return [...lista.filter((lt) => destaque.includes(lt.tag_id)), ...lista.filter((lt) => !destaque.includes(lt.tag_id))]
}

/* a hora da visita é a de Manaus, não a do computador (src/lib/fusoDeManaus.ts) */
function quandoCurto(iso: string | null): string {
  return quandoCurtoEmManaus(iso)
}

/*
 * O ROBÔ DA NAY (Pedro, 29/09/2026): "o robô não é do lado da pessoa na aba
 * conversas e sim lá na lista de conversas, ele fica no canto da foto da
 * pessoa, inferior esquerdo" -- verde a Nay atendendo, vermelho parada (a chave
 * geral da Nay, ou o Tel / alguém da equipe com a conversa). Só na Parceria.
 */
function Avatar({ lead, robo, outros }: { lead: LeadWithOwner; robo?: { parada: boolean; texto: string } | null; outros?: { n: number; avatares: (string | null)[] } }) {
  return (
    <div className="relative flex-shrink-0">
      <div className="wa-avatar rounded-full overflow-hidden flex items-center justify-center"
           style={{ backgroundColor: 'var(--wa-row-selected)' }}>
        {lead.avatar_url ? (
          <img src={lead.avatar_url} alt="" loading="lazy" decoding="async" className="w-full h-full object-cover" />
        ) : (
          <User size={28} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.55 }} />
        )}
      </div>
      {/* 29/10 (Pedro): as fotos dos contatos relacionados em bolinhas no canto de baixo à direita da foto do lead,
          sempre à mostra, para ver que há mais gente ali */}
      {outros && (
        <span className="absolute flex items-center" style={{ right: -6, bottom: -4, flexDirection: 'row-reverse' }}
              title={`${outros.n} contato(s) relacionado(s)`}>
          {outros.avatares.slice(0, 2).map((url, i) => (
            <span key={i} className="rounded-full overflow-hidden flex items-center justify-center"
                  style={{ width: 20, height: 20, marginLeft: -7, background: 'var(--wa-row-selected)', border: '2px solid var(--wa-bg, #fff)', zIndex: 2 - i }}>
              {url ? <img src={url} alt="" loading="lazy" decoding="async" className="w-full h-full object-cover" />
                : <User size={11} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.6 }} />}
            </span>
          ))}
          {outros.n > 2 && (
            <span className="rounded-full flex items-center justify-center text-white"
                  style={{ width: 20, height: 20, marginLeft: -7, fontSize: 9, fontWeight: 700, background: '#7c3aed', border: '2px solid var(--wa-bg, #fff)' }}>+{outros.n - 2}</span>
          )}
        </span>
      )}
      {robo && (
        <span className="wa-robo-selo" style={{ ['--cor' as string]: robo.parada ? 'var(--wa-tag-tel)' : 'var(--wa-green)' }}
              title={robo.texto} aria-label={robo.texto} role="img">
          <Robot size={11} weight="fill" />
        </span>
      )}
    </div>
  )
}

/* 29/10 (Pedro: "tira essa tag 2 filtrado, ou visita, deixa só a tag OLX e se é venda ou locação embaixo do nome"):
   a barrinha dos 5 passos da Nay (520) saiu da linha; os passos continuam nas abas e no card do lead. */
const FINALIDADE: Record<string, { rotulo: string; cor: string }> = {
  locacao: { rotulo: 'Locação', cor: '#0891b2' },
  venda: { rotulo: 'Venda', cor: '#d97706' },
}

/* A BARRINHA DA NAY (520, Pedro, 29/10/2026): os 5 passos do atendimento dela com o lead, embaixo das etiquetas. Ela
   sobe quando a Nay avança e volta sozinha quando o pedido muda. Fechamento enche de roxo; finalizado, de cinza. */
function BarrinhaDaNay({ passo, etapa }: { passo: number; etapa: string }) {
  const fechou = etapa === 'fechamento' || etapa === 'finalizado'
  const cor = etapa === 'fechamento' ? '#7c3aed' : etapa === 'finalizado' ? 'var(--wa-text-2)' : passo >= 5 ? 'var(--wa-green)' : '#0891b2'
  const p = PASSOS_DA_NAY.find((x) => x.n === passo)
  const titulo = fechou ? `Nay: ${etapa === 'fechamento' ? 'em fechamento' : 'atendimento finalizado'}`
    : p ? `Nay: passo ${passo} de 5 — ${p.rotulo}. ${p.titulo}` : 'Nay: ainda não começou o atendimento'
  return (
    <div className="flex items-center gap-[3px] mt-[5px] mb-[1px]" title={titulo} aria-label={titulo} role="img">
      {PASSOS_DA_NAY.map((x) => (
        <span key={x.n} className="h-[3px] flex-1 rounded-full max-w-[34px]"
              style={{ background: x.n <= passo ? cor : 'var(--wa-row-selected)', opacity: x.n <= passo ? 1 : 0.9 }} />
      ))}
    </div>
  )
}

const LeadListItem = ({ lead, isSelected, onClick, onContextMenu, timeStr, hit, query, atendente, marca, nay, dono, etiquetasEmDestaque, respondeu, nayLeads, clienteOlx, etiquetasColoridas, tagsDaEquipe, onTagsChange, relacionados, aoAlternarRelacionados, relacao, passoDaNay, finalidadeDoCliente, origemDoCliente, papelNoLeads, tipoDoContato, faixaDaLinha }: LeadListItemProps) => {
  const robo = nay === undefined ? null : !nay ? { parada: true, texto: 'Lendo a Nay…' }
    : !nay.ligada ? { parada: true, texto: `Nay parada: ${nay.motivo || 'desligada'}` }
    : nayEmPausa(marca) ? { parada: true, texto: TEXTO_DA_PAUSA }
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
      className={`wa-linha ${isSelected ? 'wa-linha--sel' : ''} ${respondeu ? 'wa-linha--respondeu' : ''}`}
      style={{
        ...(nayLeads ? { boxShadow: 'inset 4px 0 0 #7c3aed, inset 0 0 0 9999px rgba(124, 58, 237, 0.12)' }
          // 29/10 (Pedro): "diminui o azul que destacava quem vem da OLX em 80%" e depois "troca o destaque azul por um
          // leve destaque roxo": a faixa e o fundo em roxo claro
          : tipoDoContato ? { boxShadow: `inset 4px 0 0 ${tipoDoContato.cor}, inset 0 0 0 9999px ${tipoDoContato.cor}0d` }
          : clienteOlx ? { boxShadow: 'inset 4px 0 0 rgba(124, 58, 237, 0.28), inset 0 0 0 9999px rgba(124, 58, 237, 0.035)' }
          : {}),
        ...(relacionados ? { position: 'relative' as const } : {}),
      }}
    >
      <Avatar lead={lead} robo={robo} outros={relacionados} />
      {/* 517: a setinha abre os contatos relacionados embaixo (não abre a conversa). 29/10 (Pedro): roxa, embaixo, quase
          tocando a borda de baixo da linha, alinhada à direita na direção do horário -- não do lado dele */}
      {relacionados && (
        <span role="button" tabIndex={0} data-relacionados={lead.id}
              aria-label={relacionados.aberto ? 'Esconder os contatos relacionados' : `Ver ${relacionados.n} contato(s) relacionado(s)`}
              title={relacionados.aberto ? 'Esconder os contatos relacionados' : `${relacionados.n} proprietário(s) que a Nay procurou por este lead`}
              className="absolute right-2 top-1/2 -translate-y-1/2 z-[1] inline-flex items-center justify-center w-[20px] h-[20px] rounded-full"
              style={{ color: relacionados.semLer ? '#fff' : '#7c3aed', background: relacionados.semLer ? 'var(--wa-unread)' : '#fff', boxShadow: '0 1px 3px rgba(0, 0, 0, 0.22)' }}
              onPointerDown={(e) => e.stopPropagation()}
              onClick={(e) => { e.stopPropagation(); e.preventDefault(); aoAlternarRelacionados?.(lead.id) }}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.stopPropagation(); e.preventDefault(); aoAlternarRelacionados?.(lead.id) } }}>
          <CaretDown size={12} weight="bold" style={{ transform: relacionados.aberto ? 'rotate(180deg)' : undefined, transition: 'transform .15s' }} />
        </span>
      )}
      {/* 29/10 (Pedro): "uma sombra leve, pequena verticalmente, mas ocupando todo o espaço horizontal do contato que tem
          contatos relacionados embaixo"; depois "ao invés da sombra embaixo põe uma sombra clara": um roxo bem claro */}
      {relacionados && (
        <span aria-hidden className="absolute left-0 right-0 bottom-0 h-[6px] pointer-events-none"
              style={{ background: 'linear-gradient(to top, rgba(124, 58, 237, 0.03), rgba(124, 58, 237, 0))' }} />
      )}
      {/* com relacionados, um respiro embaixo para a setinha do pé da linha não encostar no contador */}
      <div className={`flex-1 min-w-0 ${relacionados ? 'py-[11px]' : 'py-[11px]'}`}>
        {faixaDaLinha && (
          <div className="text-[11px] font-semibold leading-[14px] mb-[2px] truncate" style={{ color: '#b45309' }}
               title="A conversa é de outro número; a resposta sai por ele">
            {faixaDaLinha}
          </div>
        )}
        <div className="flex items-baseline justify-between gap-2">
          <span className="flex items-center gap-1.5 min-w-0">
            {dono ? (
              /* captação (Pedro, 29/09): [nome] [Prop] [condomínio] */
              <span className="flex items-baseline gap-1.5 min-w-0"
                    title={[dono.nome, dono.condominio, dono.codigo ? `#${dono.codigo}` : null, dono.bairro].filter(Boolean).join(' · ')}>
                <span className={`wa-nome truncate flex-shrink ${naoLida ? 'font-semibold' : ''}`}>{nomeDoDono(dono.nome) || formatPhone(lead.title)}</span>
                <span className="wa-marca flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}>Prop</span>
                {imovelDoDono(dono) && <span className="wa-dono-imovel truncate">{imovelDoDono(dono)}</span>}
              </span>
            ) : (
              <span className={`wa-nome truncate ${naoLida ? 'font-semibold' : ''}`}>{formatPhone(lead.title)}</span>
            )}
            {/* a etiqueta da etapa saiu (Pedro, 29/09: "retira as tags de recebeu
                imóvel, não tá bacana"); a etapa virou a trilha do card do contato */}
          </span>
          <span className="flex items-center gap-1 flex-shrink-0">
            <span className="wa-lista-hora"
                  style={{ color: naoLida ? 'var(--wa-unread)' : 'var(--wa-text-2)', fontWeight: naoLida ? 600 : 400 }}>
              {timeStr}
            </span>
          </span>
        </div>

        <div className="flex items-center gap-1.5 mt-[2px] min-w-0">
          {tipoDoContato && !papelNoLeads && (
            <span className="wa-marca flex-shrink-0 rounded px-1" style={{ color: '#fff', background: tipoDoContato.cor }}
                  title="Tipo de contato (muda no alto da conversa)">
              {tipoDoContato.nome}
            </span>
          )}
          {relacao && (
            <span className="wa-marca flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}
                  title="Contato relacionado: a Nay falou com ele por causa do lead de cima">
              {relacao}
            </span>
          )}
          {papelNoLeads && (
            <span className="wa-marca flex-shrink-0 rounded px-1"
                  style={{ color: '#fff', background: papelNoLeads === 'corretor' ? '#0d9488' : '#b45309' }}
                  title={papelNoLeads === 'corretor' ? 'Corretor: a Nay atende' : 'Proprietário: a Nay não atende'}>
              {papelNoLeads === 'corretor' ? 'Corretor · Nay atende' : 'Proprietário · Nay não atende'}
            </span>
          )}
          {nayLeads && (
            <span className="wa-marca flex-shrink-0 rounded px-1" style={{ color: '#fff', background: '#7c3aed' }}
                  title={nayLeads.motivo ? `A Nay Leads está conversando com o proprietário: ${nayLeads.motivo}` : 'A Nay Leads está conversando com o proprietário'}>
              Nay olx(leads) conversando
            </span>
          )}
          {/* 520 (Pedro, 29/10: "a tag cliente por OLX"): só quem veio da OLX; o orgânico ganha a etiqueta Locação/Venda */}
          {clienteOlx && origemDoCliente === 'olx' && (
            <span className="wa-marca flex-shrink-0 rounded px-1" style={{ color: '#fff', background: '#2563eb' }}
                  title="Veio da OLX: é quem busca imóvel, não o proprietário">
              OLX
            </span>
          )}
          {clienteOlx && finalidadeDoCliente && FINALIDADE[finalidadeDoCliente] && (
            <span className="wa-marca flex-shrink-0 rounded px-1" style={{ color: '#fff', background: FINALIDADE[finalidadeDoCliente].cor }}
                  title="O que o cliente procura, pelo que a Nay entendeu">
              {FINALIDADE[finalidadeDoCliente].rotulo}
            </span>
          )}
          {marca?.telAtendendo && (nayEmPausa(marca) ? (
            <span className="wa-marca" style={{ color: 'var(--wa-tag-prop)' }} title={TEXTO_DA_PAUSA}>Nay em pausa</span>
          ) : (
            <span className="wa-marca" style={{ color: 'var(--wa-text-2)' }} title={marca.telMotivo || 'O Tel está com esta conversa'}>
              {(marca.telMotivo || '').startsWith('Rayssa:') ? 'Rayssa' : 'Tel'}
            </span>
          ))}
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
          {etiquetasColoridas && <EtiquetasDoCard lead={lead as any} onTagsChange={onTagsChange} compacto />}
          {/* 02/11 (Pedro: "poe para aparecer as tags la no numero parceria embaixo do nome igual é no lead para a rayssa se
              organizar"): na Parceria as etiquetas aparecem embaixo do nome, com a cor delas. No Leads, quem a Nay atende
              como cliente (clienteOlx) não mostra as outras, mas a "Chaves" aparece (vermelha). */}
          {(tagsDaEquipe || clienteOlx) && (lead.lead_tags || []).filter((lt: any) => lt.tag && (tagsDaEquipe ? !ehEtapaComoTag(lt.tag.name) : lt.tag.name === 'Chaves')).slice(0, 3).map((lt: any) => (
            <span key={lt.tag_id} className="wa-marca flex-shrink-0 rounded px-1 truncate max-w-[110px]"
                  style={{ background: (lt.tag.color || '#64748b') + '26', color: lt.tag.color || '#64748b' }} title={lt.tag.name}>
              {lt.tag.name}
            </span>
          ))}
          {!marca && !tagsDaEquipe && !etiquetasColoridas && !clienteOlx && emDestaquePrimeiro(lead.lead_tags || [], etiquetasEmDestaque).slice(0, 2).map((lt: any) => lt.tag && (
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

        {passoDaNay && <BarrinhaDaNay {...passoDaNay} />}

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
  (a.lead.lead_tags || []).map((lt: any) => lt.tag_id).join() === (b.lead.lead_tags || []).map((lt: any) => lt.tag_id).join() &&
  (a.etiquetasEmDestaque || []).join() === (b.etiquetasEmDestaque || []).join() &&
  a.isSelected === b.isSelected &&
  !!a.respondeu === !!b.respondeu &&
  !!a.clienteOlx === !!b.clienteOlx &&
  a.relacionados?.n === b.relacionados?.n &&
  a.relacionados?.aberto === b.relacionados?.aberto &&
  a.relacionados?.semLer === b.relacionados?.semLer &&
  (a.relacionados?.avatares || []).join() === (b.relacionados?.avatares || []).join() &&
  a.aoAlternarRelacionados === b.aoAlternarRelacionados &&
  a.relacao === b.relacao &&
  a.passoDaNay?.passo === b.passoDaNay?.passo &&
  a.passoDaNay?.etapa === b.passoDaNay?.etapa &&
  a.finalidadeDoCliente === b.finalidadeDoCliente &&
  a.origemDoCliente === b.origemDoCliente &&
  a.papelNoLeads === b.papelNoLeads &&
  a.tipoDoContato?.nome === b.tipoDoContato?.nome &&
  a.tipoDoContato?.cor === b.tipoDoContato?.cor &&
  a.faixaDaLinha === b.faixaDaLinha &&
  !!a.etiquetasColoridas === !!b.etiquetasColoridas &&
  !!a.tagsDaEquipe === !!b.tagsDaEquipe &&
  a.atendente?.id === b.atendente?.id &&
  a.timeStr === b.timeStr &&
  a.query === b.query &&
  a.hit?.matchType === b.hit?.matchType &&
  a.hit?.snippet === b.hit?.snippet &&
  a.marca?.telAtendendo === b.marca?.telAtendendo &&
  a.marca?.telMotivo === b.marca?.telMotivo &&
  a.marca?.visitaAberta === b.marca?.visitaAberta &&
  a.marca?.visitaQuando === b.marca?.visitaQuando &&
  a.marca?.proprietario === b.marca?.proprietario &&
  a.marca?.corretor === b.marca?.corretor &&
  a.marca?.etapa === b.marca?.etapa &&
  a.dono?.nome === b.dono?.nome &&
  a.dono?.condominio === b.dono?.condominio &&
  a.dono?.codigo === b.dono?.codigo &&
  a.dono?.tipo === b.dono?.tipo &&
  a.nay?.ligada === b.nay?.ligada && a.nay === undefined === (b.nay === undefined)
))
