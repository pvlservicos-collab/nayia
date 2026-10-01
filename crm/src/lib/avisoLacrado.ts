/**
 * O AVISO LACRADO (01/10/2026) -- como um robô manda aviso ao Tel pela porta 80
 * sem que a chave nem o texto viajem abertos.
 *
 * Por que existe: o bot do Grok roda numa nuvem cujo filtro de saída (Cloudflare
 * WARP + Gateway) corta TODO HTTPS para os nossos servidores e deixa passar a
 * porta 80. Medido em 01/10 com captura no servidor: as conexões dele abriam na
 * 443 e não chegava um byte. Então o pedido vem por HTTP -- e por isso vem
 * lacrado com a chave que os dois lados já têm:
 *
 *   cifrado     = AES-256-CBC do texto, no formato do `openssl enc -pbkdf2`
 *                 ("Salted__" + sal de 8 bytes + texto cifrado), em base64
 *   assinatura  = HMAC-SHA256(chave, hora + "." + cifrado), em hex
 *   hora        = segundos desde 1970, no relógio de quem manda
 *
 * O que isso garante: quem está no caminho não lê o aviso nem consegue inventar
 * um (não tem a chave), e um pedido gravado não serve depois (a hora vence em
 * 5 minutos e a mesma assinatura não passa duas vezes). O que NÃO garante: que
 * o bot esteja falando com o nosso servidor -- alguém no caminho pode sumir com
 * um aviso. Para isso só o HTTPS, que a nuvem dele não deixa usar.
 *
 * Do lado do bot são três comandos (openssl e curl); ver o prompt entregue ao
 * Pedro em 01/10.
 */
import { createDecipheriv, createHmac, pbkdf2Sync, timingSafeEqual } from 'node:crypto'

export const JANELA_DO_LACRE_S = 300
const ITERACOES = 100_000        // o mesmo -iter do comando do bot

/* assinaturas já usadas, até a janela delas vencer (a mesma não passa duas vezes) */
const usadas = new Map<string, number>()

export type AvisoAberto = { ok: true; mensagem: string } | { ok: false; motivo: string }

export function abrirAvisoLacrado(chave: string, hora: unknown, cifrado: unknown, assinatura: unknown, agora = Date.now()): AvisoAberto {
  const h = Number(hora)
  const c = String(cifrado || '').replace(/\s+/g, '')
  const a = String(assinatura || '').trim().toLowerCase()
  if (!Number.isFinite(h) || !c || !/^[0-9a-f]{64}$/.test(a)) return { ok: false, motivo: 'pedido incompleto: faltam hora, cifrado ou assinatura' }
  if (Math.abs(agora / 1000 - h) > JANELA_DO_LACRE_S) return { ok: false, motivo: 'hora fora da janela de 5 minutos (confira o relógio de quem manda)' }

  const certa = createHmac('sha256', chave).update(`${Math.trunc(h)}.${c}`).digest()
  const veio = Buffer.from(a, 'hex')
  if (veio.length !== certa.length || !timingSafeEqual(veio, certa)) return { ok: false, motivo: 'assinatura não confere' }

  for (const [k, vence] of usadas) if (vence < agora) usadas.delete(k)
  if (usadas.has(a)) return { ok: false, motivo: 'pedido repetido' }

  try {
    const bruto = Buffer.from(c, 'base64')
    if (bruto.length < 32 || bruto.subarray(0, 8).toString('latin1') !== 'Salted__') return { ok: false, motivo: 'texto cifrado em formato desconhecido' }
    const derivado = pbkdf2Sync(chave, bruto.subarray(8, 16), ITERACOES, 48, 'sha256')
    const d = createDecipheriv('aes-256-cbc', derivado.subarray(0, 32), derivado.subarray(32, 48))
    const mensagem = Buffer.concat([d.update(bruto.subarray(16)), d.final()]).toString('utf8').trim()
    usadas.set(a, agora + 2 * JANELA_DO_LACRE_S * 1000)
    return { ok: true, mensagem }
  } catch {
    return { ok: false, motivo: 'não consegui abrir o texto cifrado' }
  }
}
