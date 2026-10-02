// >>> segundo numero do Tel (28/09)
const TELS_DO_TEL = ['[telefone …7316]', '[telefone …6408]'];
const _finalDoTel = (x) => String(x == null ? '' : x).replace(/\D/g, '').slice(-8);
const _FINAIS_DO_TEL = TELS_DO_TEL.map(_finalDoTel);
const ehTelDoTel = (x) => _FINAIS_DO_TEL.indexOf(_finalDoTel(x)) !== -1;
// <<< segundo numero do Tel
const j = $('Juntar mensagens').first().json;
const t = (j.texto || '').trim();
// >>> escolha do posta (patch_escolha_do_posta_n8n.js)
// Com pergunta aberta ao Tel, o numero sozinho e a RESPOSTA dela -- e
// quem a resolve e o publicador. Sem esta parede ele recebe o card no
// privado ao mesmo tempo em que o imovel sai nos grupos: os ramos do
// fluxo rodam em PARALELO.
//
// So para o TEL: o mesmo numero vindo de um corretor continua pedindo
// o card, que e o caminho dele desde sempre.
if (j.perguntaAberta === true && ehTelDoTel(j.telefone)) return [];
// <<< escolha do posta
if (!/^\d{3,5}$/.test(t)) return [];
return [{ json: { codigo: parseInt(t, 10), telefone: j.telefone, nome: j.nome } }];
