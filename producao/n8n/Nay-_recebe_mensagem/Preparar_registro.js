const tel = $('Juntar mensagens').first().json.telefone;
let codigo = 0;
try { codigo = parseInt($('Buscar imovel').first().json.codigo, 10) || 0; } catch (e) { codigo = 0; }
if (!codigo) { try { codigo = parseInt($('Achar codigo na resposta').first().json.codigo, 10) || 0; } catch (e) { codigo = 0; } }
// O messageId do card que acabou de sair. E ele que volta em
// `referenceMessageId` quando o corretor MARCA esta mensagem, e e
// por igualdade com ele que a Nay descobre de qual imovel ele fala.
// try/catch porque nem todo caminho passa pelo Enviar Z-API.
let msgId = null;
try {
  const r = $('Enviar Z-API').first().json || {};
  msgId = r.messageId || r.id || r.zaapId || null;
} catch (e) { msgId = null; }
return [{ json: { codigo: codigo, telefone: tel, messageId: msgId } }];
