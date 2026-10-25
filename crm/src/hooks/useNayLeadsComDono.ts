'use client'

import { useEffect, useState } from 'react'

export interface NayLeadsComDono { nome: string | null; motivo: string | null; ate: string }

/**
 * 492 (Pedro, 24/10): os proprietários com quem a Nay Leads está conversando pela Parceria, pelos 8 últimos dígitos.
 * Lido a cada 30 s, só na Parceria.
 */
export function useNayLeadsComDono(ligado: boolean): Record<string, NayLeadsComDono> {
  const [donos, setDonos] = useState<Record<string, NayLeadsComDono>>({})
  useEffect(() => {
    if (!ligado) { setDonos({}); return }
    let vivo = true
    const ler = () => fetch('/api/parceria/nay-leads-com-dono')
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (vivo && j?.donos) setDonos(j.donos) })
      .catch(() => {})
    ler()
    const t = setInterval(ler, 30_000)
    return () => { vivo = false; clearInterval(t) }
  }, [ligado])
  return donos
}
