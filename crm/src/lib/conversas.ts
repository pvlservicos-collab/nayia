/**
 * Quanto tempo uma conversa IMPORTADA do WhatsApp, que nunca teve mensagem no
 * CRM, continua aparecendo na lista do Chat.
 *
 * Existe em um lugar só porque duas camadas precisam concordar: a API recorta o
 * que manda pro navegador (`?scope=conversas`) e o LeadList recorta o que
 * desenha. Se os números divergissem, a lista mostraria menos do que o servidor
 * mandou (desperdício) ou tentaria mostrar o que não recebeu (buraco).
 *
 * Nada é apagado: a conversa fora da janela continua no banco, aparece na busca
 * e volta pra lista assim que chegar ou sair uma mensagem.
 */
export const DIAS_CONVERSA_IMPORTADA = 30
