'use client'

/**
 * A TRILHA DA NAY NO CARD DO CONTATO (Pedro, 29/09/2026): "retira as tags de
 * recebeu imóvel, não tá bacana; deixa uma trilha no contato do corretor com
 * os nós que a Nay ia percorrer, com uma distinção clara se ela está ativa ou
 * não".
 *
 * Os nós são as etapas da Nay (nai_etapa_contato, migração 141) e a visita:
 * Identificação -> Recebeu imóvel -> Agendamento -> Visita. O que passou fica
 * cheio, o atual pulsa quando a Nay está atendendo, o que falta fica vazio.
 * Com a Nay parada (a chave geral, ou o Tel/equipe com a conversa) a trilha
 * fica cinza e diz o porquê.
 */
import { Robot } from '@phosphor-icons/react'
import type { EstadoDaNay, MarcaDaNay } from '@/lib/tiposNay'

const NOS: Array<{ chave: string; rotulo: string; dica: string }> = [
  { chave: 'identificacao', rotulo: 'Identificação', dica: 'entende o que ele procura' },
  { chave: 'recebeu_imovel', rotulo: 'Recebeu imóvel', dica: 'card e fotos enviados' },
  { chave: 'agendamento_visita', rotulo: 'Agendamento', dica: 'marcando a visita' },
  { chave: 'visita', rotulo: 'Visita', dica: 'visita confirmada' },
]

function haQuanto(iso: string | null): string {
  if (!iso) return ''
  const min = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60000))
  if (min < 60) return `há ${min} min`
  const h = Math.round(min / 60)
  if (h < 48) return `há ${h} h`
  return `há ${Math.round(h / 24)} dias`
}

export default function TrilhaDaNay({ marca, nay }: { marca: MarcaDaNay | null; nay: EstadoDaNay | null }) {
  const atual = marca?.visitaAberta && marca.visitaEstado === 'confirmada'
    ? 3
    : NOS.findIndex((n) => n.chave === marca?.etapa)
  const parada = !nay ? null : !nay.ligada ? `Nay desligada: ${nay.motivo || 'chave geral'}`
    : marca?.telAtendendo ? `Nay parada nesta conversa: ${marca.telMotivo || 'o Tel está com a conversa'}`
    : null
  const ativa = !!nay && !parada

  return (
    <div className={`wa-trilha ${ativa ? 'wa-trilha--ativa' : 'wa-trilha--parada'}`} aria-label="A trilha da Nay com este contato">
      <p className="wa-trilha__estado">
        <Robot size={15} weight="fill" />
        {!nay ? 'Lendo a Nay…' : ativa ? 'Nay ativa nesta conversa' : parada}
      </p>
      <ol className="wa-trilha__nos">
        {NOS.map((n, i) => {
          const passou = atual >= 0 && i < atual
          const aqui = i === atual
          return (
            <li key={n.chave} className={`wa-trilha__no ${passou ? 'wa-trilha__no--passou' : ''} ${aqui ? 'wa-trilha__no--aqui' : ''}`}
                title={`${n.rotulo}: ${n.dica}${aqui && marca?.etapaDesde ? ` · ${haQuanto(marca.etapaDesde)}` : ''}`}>
              <span className="wa-trilha__bola" aria-hidden="true" />
              <span className="wa-trilha__rotulo">{n.rotulo}</span>
              {aqui && marca?.etapaDesde && i < 3 && <span className="wa-trilha__quando">{haQuanto(marca.etapaDesde)}</span>}
            </li>
          )
        })}
      </ol>
      {atual < 0 && <p className="wa-trilha__vazio">A Nay ainda não começou a trilha com este contato.</p>}
    </div>
  )
}
