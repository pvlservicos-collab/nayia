const r = $input.first().json;
const TEL = $('Comando do Tel').first().json.tel_tel;
const out = [];
if (r.avisar && r.msg_corretor) {
  out.push({ rota: 'send-text', pausa: 1, corpo: { phone: String(r.avisar), message: r.msg_corretor } });
}
out.push({ rota: 'send-text', pausa: 2, corpo: { phone: TEL, message: r.msg_tel } });
return out.map(x => ({ json: x }));
