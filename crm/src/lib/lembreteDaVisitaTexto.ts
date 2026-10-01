/**
 * O TEXTO DO LEMBRETE DA VISITA, sem banco: serve à tela (a mensagem padrão já
 * vem escrita na janela) e à rota (que troca as marcas pelo que vale para cada
 * pessoa). Pedro, 01/10/2026: "esse lembrete quero ... já com uma mensagem
 * padrão pronta lá na janela".
 *
 * AS MARCAS. O lembrete do corretor e o do proprietário não são o mesmo texto:
 * muda o nome, muda como se fala do imóvel ("no Parque dos Ingleses" x "no seu
 * imóvel"), e o "hoje / amanhã / dia 03/10" é contado da hora em que o lembrete
 * SAI, não de agora. Por isso a janela mostra um modelo com três marcas, e cada
 * pessoa recebe o seu preenchido:
 *   {nome}    o primeiro nome (sem nome que pareça de gente, some com a vírgula)
 *   {quando}  "hoje às 15:00", "amanhã às 15:00", "dia 03/10 às 15:00"
 *   {imóvel}  "no <imóvel>" para o corretor, "no seu imóvel…" para o dono
 * Quem apagar as marcas manda o texto como escreveu, igual para os dois.
 */
const FUSO = 'America/Manaus'

export const MODELO_DO_LEMBRETE =
  'Oi, {nome}! Passando para lembrar da visita {quando} {imóvel}. Qualquer imprevisto, me avisa por aqui.'

const diaEm = (d: Date) => d.toLocaleDateString('en-CA', { timeZone: FUSO })   // AAAA-MM-DD em Manaus

/** "hoje às 15:00" / "amanhã às 15:00" / "dia 03/10 às 15:00", visto de QUANDO o lembrete sai. */
export function quandoNoLembrete(visita: Date, enviadoEm: Date): string {
  const hora = visita.toLocaleTimeString('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' })
  const diaVisita = diaEm(visita)
  if (diaVisita === diaEm(enviadoEm)) return `hoje às ${hora}`
  if (diaVisita === diaEm(new Date(enviadoEm.getTime() + 86_400_000))) return `amanhã às ${hora}`
  const [, m, d] = diaVisita.split('-')
  return `dia ${d}/${m} às ${hora}`
}

/** O primeiro nome, só se parecer nome de gente ("Alecsandro Reboucas👔" -> "Alecsandro"). */
export function primeiroNome(nome: string | null | undefined): string | null {
  const p = String(nome || '').trim().split(/\s+/)[0]?.replace(/[^\p{L}'-]/gu, '') || ''
  if (p.length < 2 || /^\d/.test(p)) return null
  return p[0].toUpperCase() + p.slice(1).toLowerCase()
}

/** O modelo (o padrão ou o que a pessoa escreveu na janela) com as marcas trocadas para UM destinatário. */
export function preencherLembrete(modelo: string, para: 'corretor' | 'proprietario', nome: string | null, visita: Date,
                                  enviadoEm: Date, imovel: string | null, imovelDoDono: string | null): string {
  const primeiro = primeiroNome(nome)
  const onde = para === 'proprietario'
    ? (imovelDoDono || 'no seu imóvel')
    : (imovel ? `no ${imovel}` : 'no imóvel')
  return modelo
    .replace(/(,?\s*)\{nome\}/gi, (_tudo, antes: string) => (primeiro ? antes + primeiro : ''))
    .replace(/\{quando\}/gi, quandoNoLembrete(visita, enviadoEm))
    .replace(/\{im[óo]vel\}/gi, onde)
    .trim()
}

/** O texto de sempre, para quem não escreveu um. Português de gente, sem cerimônia. */
export function textoDoLembrete(para: 'corretor' | 'proprietario', nome: string | null, visita: Date, enviadoEm: Date,
                                imovel: string | null, imovelDoDono: string | null): string {
  return preencherLembrete(MODELO_DO_LEMBRETE, para, nome, visita, enviadoEm, imovel, imovelDoDono)
}
