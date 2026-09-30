/*
 * "sim" e "não" do Tel, quando a Nay fez uma pergunta a ele.
 *
 * O PEDIDO (Tel, 14/09): "quero que poste novamente mas ela me perguntando e
 * eu confirmando". Na conversa real ele escreveu "Pode postar novamente" -- que
 * caiu no agente, porque não era comando -- e depois o código solto, que caiu
 * no ramo de código puro e mandou o card para o chat dele.
 *
 * ESTES LITERAIS SÓ VALEM COM PERGUNTA ABERTA. Sozinhos eles casam qualquer
 * "ok" da conversa; quem decide se há pergunta é `nay_pergunta_aberta_do_tel()`,
 * lida no `Reservar mensagens` e passada como `perguntaAberta`. Os dois nós que
 * leem isto -- `Comando do Tel` (manda) e `Rotear para o agente` (descarta) --
 * exigem as duas coisas juntas.
 *
 * A MENSAGEM INTEIRA tem que ser resposta. "sim\nposta o 5750" (duas mensagens
 * juntadas pela janela de 25s) não é "sim": tem um comando dentro.
 *
 * `patch_resposta_ao_tel_n8n.js` LÊ estes literais daqui; o Python tem a mesma
 * regra em `interpretar_comando.py`, e `casos_resposta_ao_tel.json` roda os dois.
 */

// Tem que ter pelo menos uma palavra de CONCORDAR -- "por favor" sozinho não é
// resposta. As outras só acompanham ("sim, pode postar de novo por favor").
const RESPOSTA_SIM_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?=[\s\S]*\b(?:sim|s|pode|isso|ok|okay|beleza|blz|confirm[oa]|confirmado|quero|bora|manda|posta|postar|poste|reposta|repostar|claro|certo|novamente)\b)(?:(?:sim|s|pode|isso|ok|okay|beleza|blz|confirm[oa]|confirmado|quero|bora|manda|posta|postar|poste|reposta|repostar|claro|certo|mesmo|com\s+certeza|de\s+novo|novamente|outra\s+vez|por\s+favor|pfv|pf|nay)(?:[\s,;.!]+|$)){1,8}$/i;

const RESPOSTA_NAO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:n[aã]o|n|deixa(?:\s+quieto)?|esquece|cancela|agora\s+n[aã]o|melhor\s+n[aã]o)(?:[\s,;.!]+(?:n[aã]o|precisa|posta|postar|obrigad[oa]|nay|por\s+enquanto|agora|quieto))*[\s,;.!]*$/i;

function respostaAoTel(texto) {
  const t = String(texto || '').trim();
  if (RESPOSTA_SIM_RE.test(t)) return 'sim';
  if (RESPOSTA_NAO_RE.test(t)) return 'nao';
  return null;
}

module.exports = { RESPOSTA_SIM_RE, RESPOSTA_NAO_RE, respostaAoTel };
