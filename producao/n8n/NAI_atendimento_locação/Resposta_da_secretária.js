// A caixa de saida e a MESMA da Nay de locacao: quem divide o texto em
// mensagens, guarda e libera o envio ja esta pronto ali.
const a = $('NAI (secretária)').first().json || {};
const j = $('Juntar mensagens').first().json || {};
return [{ json: {
  texto: String(a.output || '').trim(),
  codigos: [],
  escreveu: j.texto || '',
  fotos_site: []
} }];
