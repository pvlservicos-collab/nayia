const w = $('Webhook').first().json.body || {};
// Mesma parede do "Detectar imagem" (16/09): audio que SAI daqui nao volta
// para ser transcrito. Nunca quebrou nada porque a resposta do Whisper nao tem
// campo `id`, mas transcrever o proprio audio e gasto sem uso.
if (w.isGroup || w.isNewsletter || w.broadcast || w.isStatusReply) return [];
if (w.type !== 'ReceivedCallback') return [];
if (w.fromMe || w.fromApi) return [];
const a = w.audio || {};
const url = a.audioUrl || '';
if (!url) return [];
const seg = Number(a.seconds || 0);
return [{ json: { audio_url: url, seg: seg, longo: seg > 180, telefone: w.phone, nome: w.senderName } }];
