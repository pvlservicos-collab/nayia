'use client'

/**
 * Os corretores do WhatsApp Leads (8 últimos dígitos), para o botão "Proprietários e corretores" (Pedro, 30/10/2026).
 * Lê /api/captacao/corretores uma vez por montagem e de 10 em 10 minutos.
 */
import { useEffect, useState } from 'react'

export function useCorretoresDaCaptacao(ligado: boolean): Set<string> {
  const [fins, setFins] = useState<Set<string>>(() => new Set())
  useEffect(() => {
    if (!ligado) return
    let vivo = true
    const ler = () => fetch('/api/captacao/corretores', { cache: 'no-store' })
      .then((r) => (r.ok ? r.json() : { fins: [] }))
      .then((j) => { if (vivo) setFins(new Set<string>(j.fins || [])) })
      .catch(() => undefined)
    void ler()
    const t = setInterval(ler, 10 * 60_000)
    return () => { vivo = false; clearInterval(t) }
  }, [ligado])
  return fins
}
