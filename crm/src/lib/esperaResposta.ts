/*
 * QUEM ESPERA RESPOSTA (Pedro, 30/09/2026: "o número de gente que falta
 * responder ainda tá alto sendo que eu já respondi no CRM").
 *
 * Medido em 30/09: das conversas contadas, a última mensagem da pessoa era, em
 * boa parte, "ok", "obrigado", 👍 DEPOIS da resposta nossa -- isso fecha a
 * conversa, não pede resposta. E o próprio número da Nay (Parceria, final
 * 3618) virou lead na linha da captação, com 53 mensagens "sem resposta".
 *
 * "sim" e saudação continuam contando: "sim" depois de "quer visitar?" pede
 * ação, e "bom dia" abre conversa.
 */
/*
 * 01/10/2026, Pedro: "os círculos da etapa no CRM estão errados, é para
 * aparecer só quantas pessoas falta responder; hoje em proprietário tem 7 mas
 * tá todo mundo respondido".
 *
 * Medido nos 7: "Por nada" e "Ta" entravam na conta (a lista de cortesia não
 * tinha nenhum dos dois), o número INTERNO da Imob Easy (8595-6408) contava
 * como pessoa, e cinco eram de 25 a 30/09 -- conversa velha, não gente
 * esperando. A janela de 24 h, que a barra de métricas já usava, não valia
 * para os círculos: a barra dizia uma coisa e a bolinha outra.
 */
// uma ou mais destas, e nada mais: "ok", "ok obrigado", "show valeu"
const CORTESIA = /^(?:(?:ok+|okay|blz|beleza|certo|certinho|show|top|otimo|perfeito|combinado|fechado|joia|obrigad[oa]s?|muito|obg|vlw|valeu|de nada|por nada|imagina|entendi|entendido|ta|tah|ta bom|ta certo|ta otimo|esta bem|esta bom|esta certo|esta otimo|tudo bem|tudo certo|tranquilo|sem problema|sem problemas|isso|isso mesmo|exato|exatamente|uhum|aham|ata|legal|maravilha|otima|boa|bacana|grato|grata|agradec[oi]|disponha|tamo junto|abraco|abs|figurinha)\s?)+$/

/*
 * Os números que são NOSSOS: a Nay na Parceria (Z-API), a Nay na API oficial e
 * a Imob Easy (8595-6408, o número com os poderes do Tel). Lead deles é eco ou
 * conversa interna, não pessoa esperando atendimento.
 */
const NUMEROS_INTERNOS = ['94453618', '84560874', '85956408']

/** Quanto tempo uma mensagem sem resposta ainda conta como "falta responder". */
export const JANELA_DE_RESPOSTA = 24 * 60 * 60 * 1000

/*
 * "[Figurinha]" entra na lista: figurinha fecha a conversa, como a reação.
 * "[áudio]" e "[foto]" NÃO entram -- áudio sem transcrição e foto do corretor
 * pedem que alguém olhe.
 */
export function soCortesia(texto: string | null | undefined): boolean {
  const cru = String(texto || '').trim()
  if (!cru) return false
  if (cru.startsWith('Reagiu com')) return true
  const s = cru.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim()
  if (!s) return true                       // só emoji ou pontuação
  return s.length <= 40 && CORTESIA.test(s)
}

export function ehNumeroDaNay(phone: string | null | undefined): boolean {
  return NUMEROS_INTERNOS.includes(String(phone || '').replace(/\D/g, '').slice(-8))
}

/**
 * A mensagem dela ainda está dentro da janela? Sem isto, quem escreveu há cinco
 * dias e nunca foi respondido fica na bolinha para sempre -- e aí ela deixa de
 * ser "quem falta responder agora" e vira um passivo histórico.
 */
export function dentroDaJanela(quando: string | null | undefined, agora = Date.now(), janela = JANELA_DE_RESPOSTA): boolean {
  const t = Date.parse(String(quando || ''))
  return Number.isFinite(t) && agora - t <= janela
}

/** A última mensagem é da pessoa, pede resposta e não é a própria Nay. */
export function pedeResposta(l: { last_message_sender_type?: string | null; last_message_content?: string | null;
                                  phone?: string | null }): boolean {
  return l.last_message_sender_type === 'lead' && !soCortesia(l.last_message_content) && !ehNumeroDaNay(l.phone)
}
