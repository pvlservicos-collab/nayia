/**
 * A parede do servidor para "só responde no WhatsApp da captação"
 * (ver captacaoSoResponde.ts). A tela avisa e esconde o botão; quem BARRA é
 * isto, chamado nas rotas que abrem conversa ou mandam mensagem.
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { RECUSA_DA_CAPTACAO, soRespondeNaCaptacao } from '@/lib/captacaoSoResponde'

const TIPO_DA_CAPTACAO = 'whatsapp_zapi_captacao'

/** A pessoa logada está na lista de quem só responde? (token de API e robô não têm membro: passam) */
export async function membroSoResponde(memberId: string | null): Promise<boolean> {
  if (!memberId) return false
  const r = await db.execute(sql`
    SELECT p.full_name AS nome
      FROM organization_members m LEFT JOIN profiles p ON p.id = m.user_id
     WHERE m.id = ${memberId} LIMIT 1`)
  return soRespondeNaCaptacao((r.rows[0] as any)?.nome)
}

/** Abrir conversa nova: devolve a recusa, ou null se pode. */
export async function recusaAbrirNaCaptacao(memberId: string | null, tipoDaLinha: string): Promise<string | null> {
  if (tipoDaLinha !== TIPO_DA_CAPTACAO) return null
  return (await membroSoResponde(memberId)) ? RECUSA_DA_CAPTACAO : null
}

/**
 * Mandar mensagem numa conversa: só é "começar" quando a conversa é da linha da
 * captação e a pessoa do outro lado ainda não escreveu nada. Responder quem já
 * escreveu continua liberado. Devolve a recusa, ou null se pode.
 */
export async function recusaEscreverNaCaptacao(
  organizationId: string, memberId: string | null, leadId: string,
): Promise<string | null> {
  if (!memberId) return null
  const r = await db.execute(sql`
    SELECT i.type AS tipo,
           EXISTS (SELECT 1 FROM lead_activities a
                    WHERE a.lead_id = l.id AND a.metadata->>'direction' = 'inbound') AS ja_escreveu
      FROM leads l LEFT JOIN integrations i ON i.id = l.integration_id
     WHERE l.id = ${leadId} AND l.organization_id = ${organizationId} LIMIT 1`)
  const linha = r.rows[0] as any
  if (!linha || linha.tipo !== TIPO_DA_CAPTACAO || linha.ja_escreveu) return null
  return (await membroSoResponde(memberId)) ? RECUSA_DA_CAPTACAO : null
}
