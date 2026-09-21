'use client'

/**
 * A semana montada na Agenda em Ascensão, desenhada como grade — do mesmo jeito
 * que a pessoa vê no site: 7 colunas de dia, hora correndo na vertical, cada
 * bloco colorido pela categoria (os Faróis).
 *
 * Lista em texto já existia antes e não resolvia: com 60 a 100 blocos por lead,
 * ler linha a linha não mostra o que a grade mostra de relance — onde o dia
 * está cheio, onde tem buraco, quanto do tempo é procrastinação. É esse
 * reconhecimento visual que a pessoa do atendimento precisa antes de falar com
 * o lead.
 *
 * Usada nas duas telas (painel do lead no chat/Pipeline e detalhe da planilha
 * de /leads), então só usa tokens --chat-* e as cores das categorias: funciona
 * no tema claro e no escuro sem cada tela ter a sua versão.
 */

import { AGENDA_BLOCK_CATEGORIES, AGENDA_WEEKDAYS, formatDuration, minutesToClock, type AgendaBlock } from '@/lib/agenda'

/**
 * Altura de uma hora, em px.
 *
 * Começou em 60 (1px por minuto) e o dia inteiro não cabia na tela — a grade
 * existe pra mostrar a semana de relance, e rolar 1400px pra ver da manhã à
 * noite desfaz justamente isso. A 21px a semana inteira cabe de uma vez, e o
 * bloco de uma hora ainda tem altura pro título.
 */
const ALTURA_HORA = 21
const PX_POR_MIN = ALTURA_HORA / 60
/**
 * Largura mínima de uma coluna de dia.
 *
 * 116 e não menos porque um bloco em cada quatro divide a coluna com outro que
 * o sobrepõe (medido nos 43 mil blocos que já estão no banco: 22,5% em duas
 * faixas, 2,4% em três ou mais). A 116 a metade ainda mostra título legível; a
 * grade rola na horizontal, então o custo de ser mais larga é baixo.
 */
const LARGURA_DIA = 116
/** Faixa das horas à esquerda. */
const LARGURA_GUTTER = 44

/** Cor de quem tem categoria desconhecida — cinza neutro, igual ao "desvio". */
const COR_PADRAO = '#9a9a94'

/**
 * `#f2c744` → `rgba(242,199,68,.22)`.
 *
 * Escrito na mão em vez de `color-mix()` porque a grade roda dentro do CRM que
 * abre em navegador de celular e de máquina antiga; `color-mix` só apareceu no
 * Safari 16.2, e nele falhar significa bloco sem fundo nenhum — a categoria,
 * que é o ponto da grade, sumiria em silêncio.
 */
function comAlfa(hex: string, alfa: number): string {
  const limpo = hex.replace('#', '')
  const cheio = limpo.length === 3 ? limpo.split('').map((c) => c + c).join('') : limpo
  const n = parseInt(cheio, 16)
  if (!Number.isFinite(n)) return hex
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alfa})`
}

/** Um bloco já posicionado: com faixa (lane) resolvida contra quem o sobrepõe. */
interface BlocoPosicionado extends AgendaBlock {
  inicio: number
  fim: number
  faixa: number
  faixas: number
}

/**
 * Distribui os blocos de um dia em faixas lado a lado.
 *
 * Cerca de um em cada oito blocos se sobrepõe a outro — o deslocamento que cai
 * dentro do expediente, a reunião dentro do bloco de trabalho. Empilhados no
 * mesmo lugar, o de cima esconderia o de baixo e a grade mentiria sobre o dia
 * da pessoa. Então blocos que se cruzam viram um grupo, e dentro do grupo cada
 * um ganha uma faixa: a primeira que já terminou quando ele começa.
 */
export function posicionar(blocos: AgendaBlock[]): BlocoPosicionado[] {
  const ordenados = blocos
    .map((b) => ({ ...b, inicio: Number(b.s) || 0, fim: (Number(b.s) || 0) + (Number(b.d) || 0) }))
    .sort((a, b) => a.inicio - b.inicio || b.fim - a.fim)

  const saida: BlocoPosicionado[] = []
  let grupo: (typeof ordenados[number] & { faixa: number })[] = []
  let fimDoGrupo = -1
  let faixasDoGrupo: number[] = []

  const fecharGrupo = () => {
    for (const bloco of grupo) {
      saida.push({ ...bloco, faixas: faixasDoGrupo.length })
    }
    grupo = []
    faixasDoGrupo = []
    fimDoGrupo = -1
  }

  for (const bloco of ordenados) {
    // Começou depois de tudo que veio antes terminar: grupo novo.
    if (bloco.inicio >= fimDoGrupo && grupo.length > 0) fecharGrupo()

    let faixa = faixasDoGrupo.findIndex((fim) => fim <= bloco.inicio)
    if (faixa === -1) {
      faixa = faixasDoGrupo.length
      faixasDoGrupo.push(bloco.fim)
    } else {
      faixasDoGrupo[faixa] = bloco.fim
    }

    grupo.push({ ...bloco, faixa })
    fimDoGrupo = Math.max(fimDoGrupo, bloco.fim)
  }
  if (grupo.length > 0) fecharGrupo()

  return saida
}

export default function AgendaGrid({
  blocks,
  alturaMax = 420,
}: {
  blocks: AgendaBlock[]
  /** Altura visível da grade em px; o resto rola. */
  alturaMax?: number
}) {
  const validos = blocks.filter(
    (b) => Number.isFinite(Number(b.day)) && Number(b.day) >= 0 && Number(b.day) <= 6 && Number(b.d) > 0
  )
  if (validos.length === 0) return null

  // Recorta a grade no que a pessoa realmente usa: começar sempre à meia-noite
  // encheria a tela de vazio antes do primeiro bloco. O fim pode passar de 24h —
  // bloco que atravessa a madrugada é comum (sono, trabalho de madrugada).
  const inicioMin = Math.min(...validos.map((b) => Number(b.s) || 0))
  const fimMax = Math.max(...validos.map((b) => (Number(b.s) || 0) + (Number(b.d) || 0)))
  const inicio = Math.floor(inicioMin / 60) * 60
  const fim = Math.max(Math.ceil(fimMax / 60) * 60, inicio + 60)
  const altura = (fim - inicio) * PX_POR_MIN

  const horas: number[] = []
  for (let m = inicio; m <= fim; m += 60) horas.push(m)

  const porDia = AGENDA_WEEKDAYS.map((label, day) => ({
    label,
    day,
    blocos: posicionar(validos.filter((b) => Number(b.day) === day)),
  }))

  return (
    <div className="rounded-xl border border-[var(--chat-border)] overflow-hidden bg-[var(--chat-bg-panel)]">
      <div className="overflow-auto scrollbar-hide" style={{ maxHeight: alturaMax }}>
        <div style={{ minWidth: LARGURA_GUTTER + 7 * LARGURA_DIA }}>
          {/* Cabeçalho dos dias — gruda no topo enquanto a grade rola. */}
          <div className="flex sticky top-0 z-20 bg-[var(--chat-bg-panel)] border-b border-[var(--chat-border)]">
            <div
              className="flex-shrink-0 sticky left-0 z-10 bg-[var(--chat-bg-panel)]"
              style={{ width: LARGURA_GUTTER }}
            />
            {porDia.map((dia) => (
              <div
                key={dia.day}
                className="flex-1 text-center py-1.5 text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] border-l border-[var(--chat-border)]"
                style={{ minWidth: LARGURA_DIA }}
              >
                {dia.label}
              </div>
            ))}
          </div>

          <div className="flex" style={{ height: altura }}>
            {/* Faixa das horas — gruda na esquerda enquanto rola pro lado. */}
            <div
              className="relative flex-shrink-0 sticky left-0 z-10 bg-[var(--chat-bg-panel)]"
              style={{ width: LARGURA_GUTTER }}
            >
              {horas.map((m) => (
                <span
                  key={m}
                  className="absolute right-1.5 text-[9px] tabular-nums text-[var(--chat-text-tertiary)] -translate-y-1/2"
                  style={{ top: (m - inicio) * PX_POR_MIN }}
                >
                  {minutesToClock(m)}
                </span>
              ))}
            </div>

            {porDia.map((dia) => (
              <div
                key={dia.day}
                className="relative flex-1 border-l border-[var(--chat-border)]"
                style={{ minWidth: LARGURA_DIA }}
              >
                {/* Linhas de hora, só como referência de leitura. */}
                {horas.slice(0, -1).map((m) => (
                  <div
                    key={m}
                    className="absolute inset-x-0 border-t border-[var(--chat-border)] opacity-60"
                    style={{ top: (m - inicio) * PX_POR_MIN }}
                  />
                ))}

                {dia.blocos.map((bloco, i) => {
                  const categoria = AGENDA_BLOCK_CATEGORIES[bloco.c ?? '']
                  const cor = categoria?.color ?? COR_PADRAO
                  const alturaBloco = (bloco.fim - bloco.inicio) * PX_POR_MIN
                  const largura = 100 / bloco.faixas
                  const titulo = bloco.t || categoria?.label || '—'
                  const horario = `${minutesToClock(bloco.inicio)}–${minutesToClock(bloco.fim)}`

                  return (
                    <div
                      key={bloco.id ?? `${bloco.inicio}-${i}`}
                      title={`${horario} · ${titulo} · ${formatDuration(bloco.fim - bloco.inicio)}${categoria ? ` · ${categoria.label}` : ''}`}
                      className="absolute overflow-hidden rounded-[3px] px-1 leading-tight"
                      style={{
                        top: (bloco.inicio - inicio) * PX_POR_MIN,
                        height: Math.max(alturaBloco - 1, 2),
                        left: `calc(${bloco.faixa * largura}% + 1px)`,
                        width: `calc(${largura}% - 2px)`,
                        // Fundo translúcido + barra na cor cheia à esquerda: a cor
                        // identifica a categoria sem competir com o texto, e o
                        // mesmo par funciona no tema claro e no escuro.
                        backgroundColor: comAlfa(cor, 0.22),
                        borderLeft: `2px solid ${cor}`,
                      }}
                    >
                      {/* Nesta escala uma hora tem 21px: dá pro título, não pro
                          horário junto. Bloco de 15 minutos tem 5px — aí só a cor
                          e o tooltip informam, texto ali seria borrão. */}
                      {alturaBloco >= 26 && (
                        <span className="block text-[8px] tabular-nums text-[var(--chat-text-tertiary)] truncate leading-[1.15]">
                          {horario}
                        </span>
                      )}
                      {alturaBloco >= 10 && (
                        <span className="block text-[9px] font-medium text-[var(--chat-text-secondary)] truncate leading-[1.15]">
                          {titulo}
                        </span>
                      )}
                    </div>
                  )
                })}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
