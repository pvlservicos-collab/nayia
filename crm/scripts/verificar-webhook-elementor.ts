/**
 * Os dois formatos de webhook do Elementor — `npm run verificar:webhook`.
 *
 * O Elementor Pro manda os campos de dois jeitos, e um formulário NOVO costuma
 * vir no segundo sem ninguém avisar:
 *
 *   achatado  "No Label name", "No Label tel"       (popup antigo)
 *   cru       fields[name][value], meta[date][value] (popup novo)
 *
 * O leitor genérico entendia só o primeiro. No dia em que o popup foi trocado,
 * lead entrou chamado "New Form" (o nome do FORMULÁRIO virou o nome da pessoa)
 * e os campos viraram chaves quebradas tipo "tel][value".
 *
 * Este arquivo passa os dois corpos pelo mesmo caminho da ingestão e mostra o
 * que sairia. Trocou o formulário do site, ou mexeu no parse? Rode isto.
 */

import { desempacotarElementor, flattenBracketKeys, applyAliases, inferContactFields } from '@/lib/ingest'
import { LEAD_SOURCES } from '@/lib/leadSources'

// Corpo igual ao que o popup novo mandou (formato cru do Elementor Pro).
const corpoCru: Record<string, string> = {
  'form[id]': '1606c7c4',
  'form[name]': 'New Form',
  'fields[name][id]': 'name',
  'fields[name][type]': 'text',
  'fields[name][title]': '',
  'fields[name][value]': 'teste',
  'fields[name][raw_value]': 'teste',
  'fields[name][required]': '0',
  'fields[email][id]': 'email',
  'fields[email][type]': 'email',
  'fields[email][value]': 'testando3@gmail.com',
  'fields[email][raw_value]': 'testando3@gmail.com',
  'fields[email][required]': '1',
  'fields[tel][id]': 'tel',
  'fields[tel][type]': 'tel',
  'fields[tel][value]': '96991712835',
  'fields[tel][raw_value]': '96991712835',
  'fields[tel][required]': '1',
  'fields[utm_source][id]': 'utm_source',
  'fields[utm_source][value]': 'ig',
  'meta[date][title]': 'Date',
  'meta[date][value]': '16/09/2026',
  'meta[time][title]': 'Time',
  'meta[time][value]': '18:52',
  'meta[page_url][title]': 'Page URL',
  'meta[page_url][value]': 'https://ascensaotita.com/ascensao-tita-v2/',
  'meta[remote_ip][value]': '2804:8d4::1',
  'meta[credit][value]': 'PRO Elements',
}

// Formato antigo, achatado — não pode quebrar com a mudança.
const corpoAntigo: Record<string, string> = {
  form_name: 'New Form',
  'No Label name': 'Shara',
  'No Label email': 'shara@gmail.com',
  'No Label tel': '31996176245',
  utm_source: 'ig',
}

for (const [rotulo, corpo] of [['POPUP NOVO (cru)', corpoCru], ['POPUP ANTIGO (achatado)', corpoAntigo]] as const) {
  const pronto = inferContactFields(applyAliases(flattenBracketKeys(desempacotarElementor(corpo))))
  const n = LEAD_SOURCES.site_evento.normalize(pronto)
  console.log('\n== ' + rotulo)
  console.log('   nome:     ', n.name)
  console.log('   telefone: ', n.phone)
  console.log('   e-mail:   ', n.email)
  console.log('   campos:   ', Object.keys(n.fields).sort().join(', '))
}
process.exit(0)
