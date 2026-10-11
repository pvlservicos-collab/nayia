// Roda DENTRO do container do CRM:  docker exec -i crm-imobeasy node - conferir        (só mostra, não envia nada)
//                                    docker exec -i crm-imobeasy node - enviar 1 2 3     (cria na Meta os números marcados)
// Os 10 modelos com os botões "Link do grupo" e "Pedir um imóvel" e o RODAPÉ "Imobeasy", a linha cinza embaixo do texto (Pedro, 10/10/2026).
// Criar modelo NÃO manda mensagem a ninguém: ele entra na fila de aprovação da Meta. O token fica no ambiente.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const BOTOES = ['Link do grupo', 'Pedir um imóvel']
const CORPOS = {
  // 1 a 3: texto do Pedro (10/10), como ele deixou
  1: 'Olá, {{1}}! Este é o novo número da Imob Easy, estamos cadastrando corretores parceiros. Por favor, selecione a opção que corresponde a sua necessidade:',
  2: 'Olá, {{1}}! Atualização de cadastro: este é o novo número da Imob Easy para corretores parceiros, se lhe interessar. Selecione uma opção:',
  3: 'Olá, {{1}}. Cadastro de corretor parceiro na Imob Easy. Este é o nosso novo número de atendimento. Selecione a forma de acesso:',
  // 4 a 10: a apresentação (imobiliária com rede de corretores) com o teor de sistema
  4: 'Olá, {{1}}! Aqui é a Imob Easy, imobiliária em Manaus com rede de corretores parceiros. Este é o nosso número de atendimento. Para o seu cadastro, selecione uma opção:',
  5: 'Olá, {{1}}! Este é o novo número de atendimento da Imob Easy, imobiliária em Manaus. Estamos cadastrando corretores parceiros na nossa rede. Selecione a opção:',
  6: 'Olá, {{1}}. A Imob Easy, imobiliária em Manaus, atualizou o sistema da sua rede de corretores parceiros e este é o novo número de atendimento. Selecione uma opção:',
  7: 'Olá, {{1}}! Cadastro de corretor parceiro na Imob Easy, imobiliária em Manaus. Este é o nosso número de atendimento: os imóveis da rede são liberados pelo grupo. Selecione a forma de acesso:',
  8: 'Olá, {{1}}! Aqui é a Imob Easy, imobiliária em Manaus. Nosso sistema libera os imóveis cadastrados para os corretores parceiros pelo grupo. Para dar andamento ao seu cadastro, selecione uma opção:',
  9: 'Olá, {{1}}. Este é o número de atendimento a corretores parceiros da Imob Easy, imobiliária em Manaus. Estamos atualizando os cadastros da rede. Selecione a opção que corresponde ao seu acesso:',
  10: 'Olá, {{1}}! Aqui é a Imob Easy, imobiliária em Manaus. Estamos cadastrando corretores parceiros na nossa rede, e os imóveis são liberados pelo grupo. Selecione a opção que corresponde a sua necessidade:',
  // 11 a 20: no padrão das edições dele (curto, "imobiliária em Manaus", "para o seu cadastro, selecione uma opção")
  11: 'Olá, {{1}}! Aqui é a Imob Easy, imobiliária em Manaus. Este é o nosso número de atendimento a corretores parceiros. Para o seu cadastro, selecione uma opção:',
  12: 'Olá, {{1}}! Este é o novo número da Imob Easy, imobiliária em Manaus. Estamos cadastrando corretores parceiros. Selecione uma opção:',
  13: 'Olá, {{1}}. Cadastro de corretor parceiro na Imob Easy, imobiliária em Manaus. Este é o nosso número de atendimento. Selecione uma opção:',
  14: 'Olá, {{1}}! Aqui é a Imob Easy, imobiliária em Manaus com rede de corretores parceiros. Este é o novo número de atendimento. Selecione a opção que corresponde a sua necessidade:',
  15: 'Olá, {{1}}! Atualização de cadastro na Imob Easy, imobiliária em Manaus com rede de corretores parceiros. Este é o nosso número de atendimento. Selecione uma opção:',
  16: 'Olá, {{1}}. A Imob Easy, imobiliária em Manaus, está cadastrando corretores parceiros na sua rede. Este é o número de atendimento. Para o seu cadastro, selecione uma opção:',
  17: 'Olá, {{1}}! Este é o número de atendimento da Imob Easy, imobiliária em Manaus. Nosso sistema atende corretores parceiros por aqui. Selecione a forma de acesso:',
  18: 'Olá, {{1}}! Aqui é a Imob Easy, imobiliária em Manaus. Nossa rede de corretores parceiros recebe os imóveis pelo grupo. Para o seu cadastro, selecione uma opção:',
  19: 'Olá, {{1}}. Este é o novo número de atendimento da Imob Easy, imobiliária em Manaus, para corretores parceiros. Selecione a opção que corresponde a sua necessidade:',
  20: 'Olá, {{1}}! Cadastro de corretor parceiro: a Imob Easy, imobiliária em Manaus, atende por este número. Os imóveis da rede são liberados pelo grupo. Selecione uma opção:',
}

function modelo(n) {
  return {
    name: 'l3_util_' + String(n).padStart(2, '0'), language: 'pt_BR', category: 'UTILITY',
    components: [
      { type: 'BODY', text: CORPOS[n], example: { body_text: [['Carlos']] } },
      { type: 'FOOTER', text: RODAPE },
      { type: 'BUTTONS', buttons: BOTOES.map(t => ({ type: 'QUICK_REPLY', text: t })) },
    ],
  }
}

function defeitos(m) {
  const corpo = m.components[0].text, d = []
  if (RODAPE.length > 60) d.push('rodapé com mais de 60 caracteres')
  if (corpo.length > 1024) d.push('corpo com mais de 1024 caracteres')
  if (/^\s*\{\{1\}\}/.test(corpo) || /\{\{1\}\}\s*$/.test(corpo)) d.push('variável no começo ou no fim do corpo')
  if ((corpo.match(/\{\{/g) || []).length !== 1) d.push('o corpo deve ter exatamente uma variável')
  for (const b of BOTOES) if (b.length > 25) d.push('botão com mais de 25 caracteres: ' + b)
  return d
}

async function meta(caminho, corpo) {
  const r = await fetch('https://graph.facebook.com/v23.0/' + caminho, {
    method: corpo ? 'POST' : 'GET', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: corpo ? JSON.stringify(corpo) : undefined,
  })
  return r.json()
}

async function main() {
  const [modo, ...numeros] = process.argv.slice(2)
  if (!token || !waba) { console.log('sem META_TOKEN/META_WABA_ID no ambiente do CRM'); return }
  const ja = await meta(waba + '/message_templates?limit=200&fields=name,status,category,components')
  if (ja.error) { console.log('erro da Meta ao listar:', ja.error.message); return }
  const existentes = new Map((ja.data || []).map(t => [t.name, t]))
  if (modo === 'ver') {            // como um modelo que já existe foi montado (para copiar o formato)
    const t = existentes.get(numeros[0]); console.log(JSON.stringify(t ? t.components : null)); return
  }
  if (modo === 'apagar') {
    for (const nome of numeros) {
      const t = existentes.get(nome)
      const botoes = ((t && t.components.find(c => c.type === 'BUTTONS')) || {}).buttons || []
      const mesmos = botoes.length === 2 && botoes.every(b => BOTOES.includes(b.text))
      if (!t || t.category !== 'MARKETING' || !mesmos) { console.log(nome, '-> não apagado (não existe, não é MARKETING ou os botões são outros)'); continue }
      const r = await fetch(`https://graph.facebook.com/v23.0/${waba}/message_templates?name=${encodeURIComponent(nome)}`,
        { method: 'DELETE', headers: { Authorization: 'Bearer ' + token } }).then(x => x.json())
      console.log(nome, '->', r.error ? 'ERRO: ' + r.error.message : 'apagado')
    }
    return
  }
  if (modo === 'situacao') {
    for (const n of Object.keys(CORPOS)) {
      const t = existentes.get(modelo(n).name)
      console.log(modelo(n).name, t ? `${t.status} | ${t.category}` : '(não enviado)')
    }
    return
  }
  const quais = (modo === 'enviar' ? numeros : Object.keys(CORPOS)).map(Number).filter(n => CORPOS[n])
  for (const n of quais) {
    const m = modelo(n), d = defeitos(m)
    const repetido = existentes.has(m.name)
    console.log(`\n${n}. ${m.name} (${m.components[0].text.length} caracteres)${repetido ? ' -- JÁ EXISTE na conta' : ''}${d.length ? ' -- DEFEITO: ' + d.join('; ') : ''}`)
    console.log('   ' + m.components[0].text)
    console.log(`   rodapé: ${RODAPE}`)
    console.log('   botões: ' + BOTOES.join(' | '))
    if (modo !== 'enviar' || repetido || d.length) continue
    const r = await meta(waba + '/message_templates', m)
    console.log('   -> ' + (r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} | id ${r.id}`))
  }
}
main().catch(e => console.log('falhou:', e.message))
