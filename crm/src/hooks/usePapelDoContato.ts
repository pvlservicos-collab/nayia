'use client'

/**
 * PROPRIETÁRIO, VISITA E LOCAÇÃO de uma conversa, nos dois números (Leads e Parceria), para as abas da v2 do CRM
 * (lib/versaoDoCrm.ts). As mesmas regras que as listas dos números já usam, num lugar só:
 *   proprietário  o tipo escolhido à mão manda (Proprietário sim; outro tipo, não). Sem tipo: na Parceria, a etapa
 *                 Proprietários da Nay (etapaDaParceria); no Leads, o dono da campanha ou do cadastro que não é cliente da
 *                 OLX nem corretor (o papelNoLeads da LeadList)
 *   visita        na Parceria, a etapa Visitas; no Leads, a etiqueta da etapa Visita
 *   locação       no Leads, quem a Nay entendeu como locação (a finalidade do cliente) ou quem a equipe mandou com o botão
 *                 "Mandar para locação" (custom_attributes.atendimento_locacao)
 */
import { useCallback } from 'react'
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { tipoEscolhido } from '@/lib/organizacaoDoLead'
import { etapaDaParceria } from '@/lib/etapaDaParceria'
import { fim8 } from '@/lib/olxClientes'
import { useEtiquetas } from '@/lib/etiquetas'
import { useParceriaMarcas } from './useParceriaMarcas'
import { useCaptacaoDonos } from './useCaptacaoDonos'
import { useOlxClientes } from './useOlxClientes'
import { useDonosDoCadastro } from './useDonosDoCadastro'
import { useCorretoresDaCaptacao } from './useCorretoresDaCaptacao'

export function usePapelDoContato(ativo = true) {
  const { marcas } = useParceriaMarcas(ativo)
  const donos = useCaptacaoDonos(ativo)
  const olxClientes = useOlxClientes(ativo)
  const donosDoCadastro = useDonosDoCadastro(ativo)
  const corretores = useCorretoresDaCaptacao(ativo)
  const etiquetas = useEtiquetas()
  const idVisita = etiquetas.find((t) => (t.nomeOriginal || t.name) === 'Visita')?.id

  const ehProprietario = useCallback((l: LeadWithOwner): boolean => {
    const tipo = tipoEscolhido(l)
    if (tipo) return tipo === 'proprietario'
    const linha = getLinhaWhatsapp(l)
    if (linha === 'parceria') return etapaDaParceria(l as any, marcas[l.id]) === 'proprietarios'
    if (linha !== 'captacao') return false
    const f = fim8(l.phone)
    if (corretores.has(f)) return false
    const d = donos[l.id]
    if (d && !(!d.captacaoId && olxClientes[f])) return true
    return donosDoCadastro.has(f) && !olxClientes[f]
  }, [marcas, donos, olxClientes, donosDoCadastro, corretores])

  const ehVisita = useCallback((l: LeadWithOwner): boolean => {
    const linha = getLinhaWhatsapp(l)
    if (linha === 'parceria') return etapaDaParceria(l as any, marcas[l.id]) === 'visitas'
    if (linha === 'captacao') return !!idVisita && (l.lead_tags || []).some((lt: any) => lt.tag_id === idVisita)
    return false
  }, [marcas, idVisita])

  const ehLocacao = useCallback((l: LeadWithOwner): boolean => {
    if (getLinhaWhatsapp(l) !== 'captacao') return false
    const marca = (l.custom_attributes as any)?.atendimento_locacao
    if (marca === true || marca === false) return marca
    return olxClientes[fim8(l.phone)]?.finalidade === 'locacao'
  }, [olxClientes])

  return { ehProprietario, ehVisita, ehLocacao }
}
