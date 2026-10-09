/**
 * GENTE ESCREVEU, A NAY DE CAPTAÇÃO PARA (Pedro, 09/10/2026: "se eu mando msg no chat da API
 * oficial a Nay desliga? ... põe para desligar").
 *
 * Até aqui só o botão "Parar Nay", a escalada e o celular da Z-API calavam a Nay de captação para
 * uma pessoa; o que saía pelo CRM no número oficial ela nem via, e respondia por cima. Agora a
 * mensagem de gente pelo CRM, no oficial ou no número da captação, faz o mesmo que o botão: a
 * etapa "Com o Tel" (242), que a Nay de captação respeita até alguém clicar "Nay voltar a atender".
 *
 * Só para quem está na campanha (tem linha em captacao_leads): o número oficial também é da Nay
 * de locação, e corretor conversando por lá não tem nada a ver com a captação.
 */
import { db } from '@/lib/db'
import { eq } from 'drizzle-orm'
import { profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import { escolherEtapaDaCaptacao } from '@/lib/nayLeitura'

export async function pararNayDaCaptacaoPorGente(telefone: string, memberId: string | null): Promise<void> {
  try {
    const r = await naydb().query(
      'SELECT l.id, l.humano_assumiu_em IS NOT NULL AS parada FROM captacao_leads l WHERE l.id = captacao_lead_por_contato($1::text)',
      [telefone],
    )
    const l = r.rows[0]
    if (!l || l.parada) return   // não é da campanha, ou já está com gente
    let quem = 'alguém no CRM'
    if (memberId) {
      const [m] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, memberId)).limit(1).catch(() => [] as any[])
      if (m?.nome) quem = m.nome.trim()
    }
    await escolherEtapaDaCaptacao(telefone, 'com_o_tel', quem)
  } catch (err: any) {
    console.error('[captacao] não consegui parar a Nay para', telefone.slice(-4), err?.message || err)
  }
}
