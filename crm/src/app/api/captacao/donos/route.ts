/**
 * GET /api/captacao/donos -- quem é o dono de cada conversa da captação
 * (Pedro, 29/09/2026: "mostrar o nome do proprietário e o imóvel ao lado --
 * Evandro Prop Kopenhagen"). Devolve { donos: { <leadId>: DonoNaLista } }.
 *
 * O dono vem da captação (migração 180) e casa com a conversa pelo telefone
 * (8 últimos dígitos) ou pelo @lid. Guarda 60 s: a lista pede a cada 2 min em
 * cada tela aberta.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { donosDaCaptacao } from '@/lib/nayLeitura'
import { naydb } from '@/lib/nayDisparo'
import type { DonoNaLista } from '@/lib/tiposNay'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const guardadas = new Map<string, { em: number; donos: Record<string, DonoNaLista> }>()

/** 26/10: quem muda a etapa à mão (captacao-etapa) tira esta guarda na hora -- senão o GET
 *  seguinte (a recarga do hook, no mesmo segundo) devolve a cópia de até 60s atrás e a escolha
 *  parece não ter pegado: ela volta para a aba antiga até a guarda vencer sozinha. */
export function invalidarDonosDaCaptacao(organizationId: string): void {
  guardadas.delete(organizationId)
}

/* 29/10 (Pedro: "tem gente apontada como proprietário lá no WhatsApp Lead que na verdade é corretor"; nayia 526): o
   corretor que é o contato cadastrado do imóvel (Agnaldo da Idealize, Davi Izel, Moacy, Sarah, Thiago, Raquel...) e os
   números nossos não levam "Prop" na linha do WhatsApp Leads. A conta leva uns segundos e muda pouco: 10 min de guarda. */
let corretoresGuardados: { em: number; fins: Set<string> } | null = null
/* 04/11 (o CRM lento; em 03/11 às 10h a conta estourou os 20 s 23 vezes em 3 min): um cálculo por vez para todos os
   pedidos, e a falha também fica guardada -- a próxima tentativa só 2 min depois, com a cópia anterior (ou ninguém) */
let corretoresEmCurso: Promise<Set<string>> | null = null
export async function corretoresDaCaptacao(): Promise<Set<string>> {
  if (corretoresGuardados && Date.now() - corretoresGuardados.em < 10 * 60_000) return corretoresGuardados.fins
  if (!corretoresEmCurso) corretoresEmCurso = calcularCorretores().finally(() => { corretoresEmCurso = null })
  return corretoresEmCurso
}

async function calcularCorretores(): Promise<Set<string>> {
  try {
    /* 30/10 (Pedro: "você colocou todos os corretores como proprietários ... se o cara tem corretor no nome, ou CRECI, ou
       imobiliária, é corretor; se ele envia outro imóvel..."; nayia 541): a 526 só olhava quem também era dono de
       campanha (11). crm_leads_corretores olha todo mundo do 8595 (nome, o que ele disse, outro imóvel, grupos e lista de
       corretores, contato de imóvel de parceiro...) e aqui entra o título da conversa no CRM. */
    const [r, nomes] = await Promise.all([
      naydb().query('SELECT fone8 FROM crm_leads_corretores()').catch(() => naydb().query('SELECT fone8 FROM crm_captacao_corretores()')),
      db.execute(sql`
        SELECT DISTINCT right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) AS fone8
          FROM leads l JOIN integrations i ON i.id = l.integration_id
         WHERE l.deleted_at IS NULL AND i.type = 'whatsapp_zapi_captacao'
           AND l.title ~* '(corretor|creci|imobili)'`),
    ])
    const fins = new Set((r.rows as Array<{ fone8: string }>).map((x) => x.fone8))
    for (const n of nomes.rows as Array<{ fone8: string }>) if (n.fone8?.length === 8) fins.add(n.fone8)
    corretoresGuardados = { em: Date.now(), fins }
  } catch (e: any) {
    console.error('[captacao/donos] corretores', e?.message || e)   // sem a 526: ninguém sai, como antes
    corretoresGuardados = { em: Date.now() - 8 * 60_000, fins: corretoresGuardados?.fins || new Set() }
  }
  return corretoresGuardados!.fins
}

async function calcular(organizacao: string): Promise<Record<string, DonoNaLista>> {
  const [donos, conversas, corretores] = await Promise.all([
    donosDaCaptacao(),
    db.execute(sql`
      SELECT l.id::text AS id, right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) AS fim8,
             coalesce(l.custom_attributes->>'chat_lid', '') AS lid, i.type AS tipo
        FROM leads l JOIN integrations i ON i.id = l.integration_id
       WHERE l.organization_id = ${organizacao} AND l.deleted_at IS NULL
         AND i.type IN ('whatsapp_zapi_captacao', 'whatsapp_cloud_official') AND coalesce(l.is_group, false) = false`),
    corretoresDaCaptacao(),
  ])
  const porFim = new Map<string, DonoNaLista>()
  const porLid = new Map<string, DonoNaLista>()
  for (const d of donos) {
    const { telefone, lid, ...resto } = d
    if (telefone.length >= 8) porFim.set(telefone.slice(-8), resto)
    if (lid) porLid.set(lid, resto)
  }
  const saida: Record<string, DonoNaLista> = {}
  for (const c of conversas.rows as Array<{ id: string; fim8: string; lid: string; tipo: string }>) {
    if (c.tipo === 'whatsapp_zapi_captacao' && corretores.has(c.fim8)) continue   // 526: corretor/equipe sem "Prop" na Leads
    const d = (c.fim8.length === 8 ? porFim.get(c.fim8) : undefined) || (c.lid ? porLid.get(c.lid) : undefined)
    if (d) saida[c.id] = d
  }
  return saida
}

export async function GET(req: NextRequest) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const guardada = guardadas.get(organizationId)
    if (guardada && Date.now() - guardada.em < 60_000) return Response.json({ donos: guardada.donos })
    const donos = await calcular(organizationId)
    guardadas.set(organizationId, { em: Date.now(), donos })
    return Response.json({ donos })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os donos da captação.')
  }
}
