'use client'

/**
 * AGENDAR MENSAGEM NO CARD DA LINHA OFICIAL (Pedro, 09/10/2026): "coloca também os botões lá Nay
 * parar de atender e Nay voltar a atender, e agendar msg no chat da API oficial".
 *
 * ONDE FICAM OS BOTÕES DA NAY. No número oficial a única Nay que responde é a de captação. Quem
 * está na campanha abre o card da captação (PainelContatoCaptacao), que já tem "Parar Nay" e
 * "Nay voltar a atender" valendo para ela, mais o agendar. Este card é o de quem NÃO está na
 * campanha: não há Nay nenhuma respondendo essa pessoa por aqui, então não há botão de Nay.
 *
 * NÃO ligar aqui a rota da Parceria (/api/leads/{id}/nay): o "voltar" dela reentrega a mensagem à
 * Nay da Parceria, que responde pelo OUTRO número (o da Z-API). Foi ao ar assim por alguns minutos
 * em 09/10, ninguém clicou, e saiu.
 */
import AgendarFollowup from './AgendarFollowup'

/** A regra da Meta, dita onde a pessoa agenda: texto livre só dentro de 24 h da última mensagem dela. */
export const AVISO_DAS_24_HORAS =
  'Pelo número oficial, a mensagem agendada só sai se a pessoa tiver escrito nas 24 horas anteriores ao envio (regra da Meta). Fora disso ela fica com erro aqui na lista.'

export default function AgendarNoCardOficial({ leadId }: { leadId: string }) {
  return (
    <div className="w-full mb-3 text-left chat-theme">
      <AgendarFollowup leadId={leadId} />
      <p className="px-4 pb-2 text-[11px] leading-4" style={{ color: 'var(--wa-text-2)' }}>{AVISO_DAS_24_HORAS}</p>
    </div>
  )
}
