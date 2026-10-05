'use client'

/**
 * O HISTÓRICO DE ATENDIMENTO NO CARD DO CONTATO (Pedro, 05/10/2026): "uma filinha
 * para eu saber quando é a Nay atendendo, ou o Tel entra e digita mensagem ... várias
 * tags em uma fila como um log ... só umas tags passando para o lado".
 *
 * Uma tag por vez que alguém do nosso lado falou (ver src/lib/historicoDeAtendimento.ts):
 * Nay, a conta de cada um no CRM (Tel, Rayssa), "Celular" (digitado direto no WhatsApp
 * do número, sem passar pelo CRM) e envio automático. A mais nova fica à direita, e a
 * fila já abre nela.
 *
 * Lê uma vez ao abrir o card e de novo quando a conversa recebe mensagem (no máximo a
 * cada 15 s). A última leitura de cada conversa fica guardada: voltar a ela não busca
 * de novo antes de 1 minuto.
 */
import { useEffect, useRef, useState } from 'react'
import { DeviceMobile, Lightning, Robot, User } from '@phosphor-icons/react'
import type { TagDeAtendimento, TipoDeAutor } from '@/lib/historicoDeAtendimento'
import { diaEmManaus, horaEmManaus } from '@/lib/fusoDeManaus'

const guardadas = new Map<string, { em: number; marca: string; tags: TagDeAtendimento[] }>()
const VALE_MS = 60_000
const ESPERA_MS = 15_000

const ICONE: Record<TipoDeAutor, typeof Robot> = {
  nay: Robot, conta: User, celular: DeviceMobile, sistema: Lightning, desconhecido: User,
}
const DICA: Record<TipoDeAutor, string> = {
  nay: 'A Nay respondeu',
  conta: 'Mandou pelo CRM, com a conta dela',
  celular: 'Digitado direto no WhatsApp do número (celular ou WhatsApp Web), sem passar pelo CRM: é o aparelho do Tel',
  sistema: 'Envio automático do sistema (publicador)',
  desconhecido: 'Não consegui saber quem mandou',
}

function quando(t: TagDeAtendimento, hoje: string): string {
  const de = new Date(t.de)
  const dia = diaEmManaus(de)
  const [, m, d] = dia.split('-')
  const horas = t.n > 1 && horaEmManaus(de) !== horaEmManaus(new Date(t.ate))
    ? `${horaEmManaus(de)}–${horaEmManaus(new Date(t.ate))}` : horaEmManaus(de)
  return dia === hoje ? horas : `${d}/${m} ${horas}`
}

export default function HistoricoDeAtendimento({ leadId, mexeuEm }: { leadId: string; mexeuEm?: string | null }) {
  const [tags, setTags] = useState<TagDeAtendimento[] | null>(() => guardadas.get(leadId)?.tags ?? null)
  const fila = useRef<HTMLOListElement>(null)
  const marca = mexeuEm || ''

  useEffect(() => {
    const g = guardadas.get(leadId)
    setTags(g?.tags ?? null)
    const idade = g ? Date.now() - g.em : Infinity
    // a mesma conversa, sem mensagem nova, lida há pouco: nada a buscar
    if (g && g.marca === marca && idade < VALE_MS) return
    let vivo = true
    // mensagem nova logo depois de uma leitura: espera, para a rajada virar uma busca só
    const t = setTimeout(async () => {
      try {
        const r = await fetch(`/api/leads/${leadId}/atendimento`)
        if (!r.ok) return
        const j = await r.json()
        const novas: TagDeAtendimento[] = Array.isArray(j?.tags) ? j.tags : []
        if (guardadas.size > 200) guardadas.clear()
        guardadas.set(leadId, { em: Date.now(), marca, tags: novas })
        if (vivo) setTags(novas)
      } catch { /* fica com o que tinha */ }
    }, g && idade < ESPERA_MS ? ESPERA_MS - idade : 0)
    return () => { vivo = false; clearTimeout(t) }
  }, [leadId, marca])

  // a fila abre (e anda) na tag mais nova, à direita
  useEffect(() => {
    const el = fila.current
    if (el) el.scrollLeft = el.scrollWidth
  }, [tags])

  if (!tags || tags.length === 0) return null
  const hoje = diaEmManaus()
  return (
    <div className="wa-atendimento" aria-label="Histórico de atendimento desta conversa">
      <p className="wa-atendimento__titulo">Quem atendeu</p>
      <ol ref={fila} className="wa-atendimento__fila">
        {tags.map((t, i) => {
          const Icone = ICONE[t.tipo]
          const ultima = i === tags.length - 1
          return (
            <li key={`${t.de}-${t.nome}`} className={`wa-atendimento__tag ${ultima ? 'wa-atendimento__tag--ultima' : ''}`}
                style={{ ['--cor' as any]: t.cor }}
                title={`${t.nome}: ${DICA[t.tipo]} · ${t.n} ${t.n === 1 ? 'mensagem' : 'mensagens'} · ${quando(t, '')}`}>
              <Icone size={13} weight="fill" aria-hidden="true" />
              <span className="wa-atendimento__nome">{t.nome}</span>
              <span className="wa-atendimento__quando">{quando(t, hoje)}{t.n > 1 ? ` · ${t.n}` : ''}</span>
            </li>
          )
        })}
      </ol>
    </div>
  )
}
