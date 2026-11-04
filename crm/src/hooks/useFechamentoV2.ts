'use client'

/**
 * O FECHAMENTO NA V2 (Pedro, 04/11/2026: "uma nova aba fechamento que vai ser a última etapa após proprietários ... quando
 * um lead é enviado para ela vai ficar só o Tel vendo, a não ser que ele inclua alguém como Rayssa ou Diego na conversa, aí
 * essa pessoa pode ver a aba fechamento com o lead lá").
 *   em fechamento  no Leads, a etiqueta Fechamento (que move o card) ou a etapa "fechamento" do funil do número; na Parceria,
 *                  a etapa Fechamento (o fechamento aberto pela Nay ou a escolha no card; etapaDaParceria)
 *   quem vê        o administrador (o Tel) todos; os outros, só aqueles em que o Tel os incluiu (custom_attributes.pessoas,
 *                  a mesma lista do "Adicionar pessoa"; lib/organizacaoDoLead.ts). Na v2, quem não vê também não acha o
 *                  lead nas outras abas (Atendimento, Proprietários).
 */
import { useCallback, useMemo } from 'react'
import type { LeadWithOwner } from '@/lib/types'
import { useAuth } from '@/hooks'
import { usePipeline } from './usePipeline'
import { useParceriaMarcas } from './useParceriaMarcas'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { etapaDaParceria } from '@/lib/etapaDaParceria'
import { pessoasDe } from '@/lib/organizacaoDoLead'
import { useEtiquetas } from '@/lib/etiquetas'

export function useFechamentoV2() {
  const { organizationId, currentOrganization, isMaster, roleName, permissions } = useAuth()
  const admin = !!(isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || (permissions as any)?.['*'])
  const meuId = currentOrganization?.id || ''
  const { marcas } = useParceriaMarcas(true)
  const etiquetas = useEtiquetas()
  const { pipelines } = usePipeline(organizationId || '')
  const idDaEtiqueta = etiquetas.find((t) => (t.nomeOriginal || t.name) === 'Fechamento')?.id
  const idDaEtapa = useMemo(() => {
    const p = (pipelines as any[]).find((x) => x.settings?.linha === 'captacao')
    const s = ((p?.stages || []) as Array<{ id: string; name: string; nome_original?: string | null }>)
      .find((e) => [e.name, e.nome_original].some((n) => String(n || '').trim().toLowerCase() === 'fechamento'))
    return s?.id
  }, [pipelines])

  const emFechamento = useCallback((l: LeadWithOwner) => {
    const linha = getLinhaWhatsapp(l)
    if (linha === 'parceria') return etapaDaParceria(l, marcas[l.id]) === 'fechamento'
    if (linha === 'captacao') {
      return (!!idDaEtiqueta && (l.lead_tags || []).some((lt: any) => lt.tag_id === idDaEtiqueta))
        || (!!idDaEtapa && l.stage_id === idDaEtapa)
    }
    return false
  }, [marcas, idDaEtiqueta, idDaEtapa])

  /** pode ver este lead: fora do fechamento, sim; no fechamento, o Tel ou quem ele incluiu */
  const podeVer = useCallback((l: LeadWithOwner) => !emFechamento(l) || admin || (!!meuId && pessoasDe(l).includes(meuId)),
    [emFechamento, admin, meuId])

  return { emFechamento, podeVer, admin }
}
