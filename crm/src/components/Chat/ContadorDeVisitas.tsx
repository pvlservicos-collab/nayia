'use client'

/**
 * O CONTADOR DE VISITAS (Pedro, 01/11/2026): no lugar de "Para responder / Visitas hoje / Nay hoje / Nay calada" da
 * Parceria, "um contador de visitas com uma barra: na Parceria 3 visitas por dia e no Leads 1 visita por dia", e o
 * slogan da empresa ao lado.
 *
 * A conta é a que a barra antiga já fazia (visitas marcadas para hoje que não caíram); só a meta é nova.
 * Os números vêm de /api/parceria/painel.
 */
import { useEffect, useState } from 'react'
import { CheckCircle } from '@phosphor-icons/react'

export const META_DE_VISITAS = { parceria: 3, leads: 1 } as const
const SLOGAN = 'O máximo de opções de imóveis para você, se não temos agora, vamos encontrar'

export default function ContadorDeVisitas({ linha }: { linha: 'parceria' | 'leads' }) {
  const meta = META_DE_VISITAS[linha]
  const [feitas, setFeitas] = useState<number | null>(null)

  useEffect(() => {
    let vivo = true
    const ler = async () => {
      try {
        const r = await fetch('/api/parceria/painel')
        const j = await r.json()
        if (r.ok && vivo) setFeitas(linha === 'parceria' ? Number(j.painel?.visitasHoje ?? 0) : Number(j.visitasLeadsHoje ?? 0))
      } catch { /* o contador espera a próxima leitura */ }
    }
    void ler()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void ler() }, 30_000)
    return () => { vivo = false; clearInterval(t) }
  }, [linha])

  const n = feitas ?? 0
  const bateu = feitas !== null && n >= meta
  const pct = Math.min(100, Math.round((n / meta) * 100))

  return (
    <div className="barra-calma" aria-label="Contador de visitas do dia">
      <div className="barra-calma__item contador-visitas" title={`Visitas marcadas para hoje: ${feitas ?? '…'} de ${meta}. Não contam as canceladas nem as que expiraram.`}>
        <span className="barra-calma__rotulo">Visitas hoje</span>
        <span className="barra-calma__valor">{feitas === null ? '…' : n}<small className="opacity-60">/{meta}</small></span>
        <span className="contador-visitas__trilho" role="progressbar" aria-valuemin={0} aria-valuemax={meta} aria-valuenow={n} aria-label="Meta de visitas do dia">
          <span className={`contador-visitas__cheio ${bateu ? 'contador-visitas__cheio--meta' : ''}`} style={{ width: `${pct}%` }} />
        </span>
        {bateu && <CheckCircle size={16} weight="fill" className="contador-visitas__ok" aria-label="Meta do dia batida" />}
      </div>
      <span className="barra-calma__fim barra-calma__slogan" title={SLOGAN}>{SLOGAN}</span>
    </div>
  )
}
