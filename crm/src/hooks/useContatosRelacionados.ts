'use client'

import { useEffect, useState } from 'react'

export interface Relacionados {
  /** lead (8 últimos dígitos) -> os contatos relacionados a ele (8 últimos dígitos), com os códigos dos imóveis */
  doLead: Record<string, Array<{ contato: string; motivos: string; codigos: number[] }>>
  /** contato relacionado (8 últimos dígitos) -> os leads dele */
  doContato: Record<string, string[]>
}

const VAZIO: Relacionados = { doLead: {}, doContato: {} }

/**
 * 517 (Pedro, 29/10): quem a Nay Leads procurou por causa de um lead (o dono da dúvida, o corretor da visita) fica
 * embaixo do lead na lista do WhatsApp Leads. Lido a cada 60 s, só nessa linha.
 */
export function useContatosRelacionados(ligado: boolean): Relacionados {
  const [rel, setRel] = useState<Relacionados>(VAZIO)
  useEffect(() => {
    if (!ligado) { setRel(VAZIO); return }
    let vivo = true
    const ler = () => fetch('/api/captacao/relacionados')
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => {
        if (!vivo || !Array.isArray(j?.pares)) return
        const doLead: Relacionados['doLead'] = {}
        const doContato: Relacionados['doContato'] = {}
        for (const p of j.pares as Array<{ cliente: string; contato: string; motivos: string | null; codigos: number[] | null }>) {
          ;(doLead[p.cliente] ||= []).push({ contato: p.contato, motivos: p.motivos || '', codigos: p.codigos || [] })
          ;(doContato[p.contato] ||= []).push(p.cliente)
        }
        setRel({ doLead, doContato })
      })
      .catch(() => {})
    ler()
    const t = setInterval(ler, 60_000)
    return () => { vivo = false; clearInterval(t) }
  }, [ligado])
  return rel
}
