'use client'

/**
 * O que a Nay sabe de um contato (marcas + histórico), para o card do lado
 * da conversa da Parceria. Guardado por um minuto por conversa: reabrir uma
 * conversa mostra o card na hora, e a busca nova corre por trás.
 */
import { useCallback, useEffect, useState } from 'react'
import type { ImovelEnviado, ItemDoHistorico, MarcaDaNay } from '@/lib/tiposNay'

type Dados = { marca: MarcaDaNay | null; historico: ItemDoHistorico[]; enviados: ImovelEnviado[] }
const guardados = new Map<string, { em: number; dados: Dados }>()
const VALIDADE_MS = 60_000

export function useContatoNay(leadId: string | null | undefined) {
  const [dados, setDados] = useState<Dados | null>(() => (leadId ? guardados.get(leadId)?.dados ?? null : null))
  const [carregando, setCarregando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  const recarregar = useCallback(async () => {
    if (!leadId) return
    setCarregando(true)
    try {
      const r = await fetch(`/api/leads/${leadId}/nay`)
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      const novos: Dados = { marca: j.marca ?? null, historico: j.historico || [], enviados: j.enviados || [] }
      guardados.set(leadId, { em: Date.now(), dados: novos })
      setDados(novos)
      setErro(null)
    } catch (e: any) {
      setErro(e?.message || 'Não consegui ler a Nay')
    } finally {
      setCarregando(false)
    }
  }, [leadId])

  useEffect(() => {
    if (!leadId) { setDados(null); return }
    const g = guardados.get(leadId)
    setDados(g?.dados ?? null)
    if (!g || Date.now() - g.em > VALIDADE_MS) void recarregar()
  }, [leadId, recarregar])

  return {
    marca: dados?.marca ?? null, historico: dados?.historico ?? [], enviados: dados?.enviados ?? [],
    carregando: carregando && !dados, erro, recarregar,
  }
}
