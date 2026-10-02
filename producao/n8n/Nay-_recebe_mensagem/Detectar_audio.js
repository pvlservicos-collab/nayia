const w = $('Webhook').first().json.body || {};
const a = w.audio || {};
const url = a.audioUrl || '';
if (!url) return [];
const seg = Number(a.seconds || 0);
return [{ json: { audio_url: url, seg: seg, longo: seg > 180, telefone: w.phone, nome: w.senderName } }];
