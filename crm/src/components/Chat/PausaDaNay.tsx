'use client'

/**
 * O AVISINHO DA PAUSA (Pedro, 28/10/2026: "quando alguém mandar msg para o lead fica claro que a Nay parou por 30
 * minutos, deixa um avisinho lá"). A equipe escreveu para o lead, pelo CRM ou pelo celular: a Nay Leads espera 30 min
 * desde a última mensagem da equipe e depois volta lendo o que foi dito (nay-olx). Aqui só se mostra até quando.
 * Relê quando a conversa mexe (mexeuEm) e some sozinho quando a pausa acaba.
 */
import { useEffect, useState } from 'react'
import { PauseCircle } from '@phosphor-icons/react'
import { horaEmManaus } from '@/lib/fusoDeManaus'

export default function PausaDaNay({ leadId, mexeuEm }: { leadId: string; mexeuEm?: string | null }) {
  const [pausa, setPausa] = useState<{ ate: string; equipeEm: string; quem: string | null } | null>(null)
  const [, setTique] = useState(0)

  useEffect(() => {
    let vivo = true
    const ler = () => fetch(`/api/leads/${leadId}/pausa-da-nay`)
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (vivo) setPausa(j?.ate ? j : null) })
      .catch(() => { if (vivo) setPausa(null) })
    void ler()
    const t = setInterval(() => { void ler() }, 60_000)   // a mensagem do celular pode não mexer na conversa aberta
    return () => { vivo = false; clearInterval(t) }
  }, [leadId, mexeuEm])

  // a cada 30 s: os minutos que faltam e o fim da pausa
  useEffect(() => {
    if (!pausa) return
    const t = setInterval(() => setTique((x) => x + 1), 30_000)
    return () => clearInterval(t)
  }, [pausa])

  if (!pausa) return null
  const falta = Math.ceil((new Date(pausa.ate).getTime() - Date.now()) / 60_000)
  if (falta <= 0) return null
  return (
    <p className="text-[12px] mt-2 leading-4 inline-flex items-start gap-1.5 text-left px-3 py-2 rounded-lg"
       style={{ color: '#b45309', background: 'color-mix(in srgb, #f59e0b 14%, transparent)' }}>
      <PauseCircle size={15} weight="fill" className="flex-shrink-0 mt-px" />
      <span>
        A Nay está em pausa até {horaEmManaus(new Date(pausa.ate))} (faltam {falta} min): {pausa.quem || 'a equipe'} escreveu
        às {horaEmManaus(new Date(pausa.equipeEm))}. Depois ela volta sozinha, lendo o que foi dito.
      </span>
    </p>
  )
}
