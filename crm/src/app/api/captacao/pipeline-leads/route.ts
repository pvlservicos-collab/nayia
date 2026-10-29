/**
 * O PIPELINE DOS LEADS DA ABA LEADS (Pedro, 24/10/2026; migração 491). Ver src/components/Chat/PipelineDosLeads.tsx.
 *
 *   GET /api/captacao/pipeline-leads?de=AAAA-MM-DD&ate=AAAA-MM-DD   { leads: [...], outros: [...] }   (dias de Manaus)
 *
 * O banco é o da Nay (privado.olx_lead_whatsapp), pelo papel do CRM (nay_disparo), que só executa a função.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import { diaEmManaus } from '@/lib/fusoDeManaus'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const DIA = /^\d{4}-\d{2}-\d{2}$/

export async function GET(req: NextRequest) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const q = req.nextUrl.searchParams
    const ate = DIA.test(q.get('ate') || '') ? q.get('ate')! : diaEmManaus()
    const de = DIA.test(q.get('de') || '') ? q.get('de')! : diaEmManaus(new Date(Date.now() - 30 * 86400_000))
    const [r, o] = await Promise.all([
      naydb().query('SELECT * FROM crm_leads_pipeline($1::date, $2::date)', [de, ate]),
      // 29/10 (nayia 522): quem não é cliente -- corretor, proprietário, empresa e quem a Nay consultou para uma dúvida
      naydb().query('SELECT * FROM crm_leads_pipeline_outros($1::date, $2::date)', [de, ate]).catch(() => ({ rows: [] as any[] })),
    ])
    const outros = [...o.rows, ...(await corretoresPeloCrm(organizationId, r.rows, o.rows))]
    return Response.json({ de, ate, leads: r.rows, outros })
  } catch (err: any) {
    console.error('[captacao/pipeline-leads]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o pipeline dos leads.')
  }
}

/**
 * CORRETOR QUE PASSAVA POR LEAD (Pedro, 29/10/2026: "aqui no pipeline LEADS está contato de corretor, não deveria ter,
 * só lead"). A 522 só olha a tabela de corretores, a busca de corretor e o MOTIVO que a Nay anotou; quem escreve direto
 * no WhatsApp quase nunca tem motivo. Aqui entram os que o CRM mostra ser corretor: o nome da conversa diz (corretor,
 * corretora, imobiliária, CRECI, imóveis) ou a própria pessoa escreveu que é corretor, que tem rede de corretores ou
 * que faz parceria. "Me manda seu CRECI" (cliente pedindo o nosso) não conta: só vale o que a pessoa diz de si.
 */
async function corretoresPeloCrm(organizacao: string, leads: any[], outros: any[]) {
  const ja = new Set(outros.map((x) => x.fone8))
  const fones = [...new Set(leads.map((l) => String(l.telefone || '').replace(/\D/g, '').slice(-8)))].filter((f) => f.length === 8 && !ja.has(f))
  if (!fones.length) return []
  const achados = (await db.execute(sql`
    SELECT right(regexp_replace(l.phone, '[^0-9]', '', 'g'), 8) AS fone8, l.phone AS telefone, l.title AS nome
      FROM leads l
     WHERE l.organization_id = ${organizacao} AND l.deleted_at IS NULL AND l.is_group IS NOT TRUE
       AND right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) = ANY(${sql.raw(`ARRAY[${fones.map((f) => `'${f}'`).join(',')}]::text[]`)})
       AND (l.title ~* '(corretor|corretora|imobili|creci|im[oó]veis)'
            OR EXISTS (SELECT 1 FROM lead_activities a
                        WHERE a.lead_id = l.id AND a.type = 'whatsapp' AND a.metadata->>'direction' = 'inbound'
                          AND a.content ~* '(sou corretor|sou corretora|rede de corretores|corretores parceiros|parceria|nossa imobili|minha imobili|sou da imobili)'))`)).rows as Array<{ fone8: string; telefone: string; nome: string | null }>
  const vistos = new Set<string>()
  return achados.filter((a) => !vistos.has(a.fone8) && vistos.add(a.fone8)).map((a) => ({
    fone8: a.fone8, telefone: a.telefone, nome: a.nome, tipo: 'corretor', motivo: 'corretor pelo nome ou pelo que disse no CRM',
    em: new Date().toISOString(), cliente8: null, codigos: null,
  }))
}
