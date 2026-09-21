/**
 * Links internos que abrem uma conversa no chat.
 *
 * O chat trata o `?leadId=` como ENTRADA: ele só age quando o endereço traz
 * algo novo. Isso é o que impede o endereço de brigar com o clique na lista (a
 * briga que já congelou a tela e abriu conversa errada). O preço é que dois
 * links iguais seguidos seriam o mesmo valor — clicar em "Ver conversa" de um
 * lead que já está no endereço não abriria nada, porque nada mudou.
 *
 * Daí o `abrir=`: uma marca de tempo curta que faz cada clique em link ser um
 * endereço diferente. Quem lê é só o chat, pra saber que houve um pedido novo;
 * o valor em si não significa nada.
 */

/** Marca de tempo curta (base 36), só pra diferenciar um pedido do outro. */
function marcaDeAbertura(): string {
  return Date.now().toString(36)
}

/** `/chat?leadId=<id>&abrir=<marca>` — use em todo link interno pro chat. */
export function linkDaConversa(leadId: string): string {
  return `/chat?leadId=${leadId}&abrir=${marcaDeAbertura()}`
}

/**
 * Acrescenta a marca a um link que já existe (o das notificações, montado no
 * servidor). Mantém o que o link já tinha e nunca lança: link torto continua
 * navegando como veio.
 */
export function comMarcaDeAbertura(url: string): string {
  if (!url.includes('leadId=')) return url
  const separador = url.includes('?') ? '&' : '?'
  return `${url}${separador}abrir=${marcaDeAbertura()}`
}
