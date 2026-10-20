'use client'

/**
 * A BARRINHA DO DISPARO PELA API OFICIAL (Pedro, 09/10/2026): "em cima desses filtros quero uma barrinha para eu
 * saber qual lista está sendo disparada e quanto falta para acabar".
 *
 * O disparo do Python (serviço nay-captacao, chave python_disparo) tira um proprietário por vez da fila, em
 * listas, nesta ordem: os nunca chamados e depois a retomada de quem não respondeu no outro número (323). A barra
 * mostra se está saindo agora (ou por que não, e quando volta), a lista da vez com o progresso e o que falta, e as
 * outras listas. Os números vêm do banco (crm_captacao_disparo_oficial, migração 331), a cada 30 s.
 */
import { useEffect, useState } from 'react'
import type { DisparoOficial } from '@/lib/nayLeitura'
import { diasAteEmManaus, horaEmManaus, quandoCurtoEmManaus } from '@/lib/fusoDeManaus'

function tempoDeDisparo(faltam: number, segMedio: number): string {
  const min = Math.round((faltam * segMedio) / 60)
  if (min < 1) return 'menos de 1 min'
  if (min < 60) return `${min} min`
  const h = Math.floor(min / 60)
  const m = min % 60
  return m ? `${h}h${String(m).padStart(2, '0')}` : `${h}h`
}

function volta(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return diasAteEmManaus(d) === 0 ? `volta às ${horaEmManaus(d)}` : `volta ${quandoCurtoEmManaus(iso)}`
}

export default function BarraDoDisparoOficial() {
  const [d, setD] = useState<DisparoOficial | null | undefined>(undefined)

  useEffect(() => {
    let vivo = true
    const ler = async () => {
      try {
        const r = await fetch('/api/captacao/disparo-oficial')
        const j = await r.json()
        if (r.ok && vivo) setD(j.disparo ?? null)
      } catch { /* a barra fica com o último número */ }
    }
    void ler()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void ler() }, 30_000)
    return () => { vivo = false; clearInterval(t) }
  }, [])

  if (d === null) return null   // a migração 331 ainda não está no banco
  if (d === undefined) {
    return (
      <div className="barra-calma barra-calma--linha" aria-label="Disparo pela API oficial">
        <span className="barra-calma__grupo">Disparo</span>
        <div className="barra-calma__item"><span className="barra-calma__rotulo">Lendo…</span></div>
      </div>
    )
  }

  const daVez = d.listas.find((l) => l.faltam > 0) || null
  const faltamTodas = d.listas.reduce((s, l) => s + l.faltam, 0)

  // o estado: saindo, parado por horário, desligado, falhando ou acabou
  let luz = ''
  let estado = 'Saindo agora'
  let explica = 'Um modelo por vez, a cada ' + Math.round(d.segMedio) + ' s em média'
  if (!d.ligado) {
    luz = 'barra-calma__luz--desligado'; estado = 'Desligado'; explica = 'O disparo pela API oficial está desligado (python_disparo)'
  } else if (!daVez) {
    luz = 'barra-calma__luz--desligado'; estado = 'Acabou'; explica = 'Todas as listas já saíram'
  } else if (d.motivo === 'fora do horário') {
    luz = 'barra-calma__luz--pausa'; estado = `Fora do horário · ${volta(d.voltaEm)}`.replace(/ · $/, '')
    explica = 'O disparo só sai no horário da captação (com a pausa do almoço)'
  } else if (d.motivo && /falharam/.test(d.motivo)) {
    luz = 'barra-calma__luz--ruim'; estado = 'Parado: os 3 últimos falharam'; explica = 'Confira a conta da API oficial antes de religar'
  } else if (d.motivo && /^esperando a Meta/.test(d.motivo)) {
    // 449: o modelo próprio da lista (447) ainda não foi aprovado; sai sozinho quando a Meta aprovar
    luz = 'barra-calma__luz--pausa'; estado = 'Esperando a Meta aprovar o modelo'
    explica = d.motivo.replace(/^e/, 'E') + '. Sai sozinho quando aprovar.'
  }

  return (
    <div className="barra-calma barra-calma--linha" aria-label="Disparo pela API oficial">
      <span className="barra-calma__grupo">Disparo</span>
      <div className="barra-calma__item" title={explica}>
        <span className={`barra-calma__luz ${luz}`} />
        <span className="barra-calma__valor">{estado}</span>
      </div>

      {daVez && (() => {
        const total = daVez.enviados + daVez.faltam
        const pct = total ? Math.round((daVez.enviados / total) * 100) : 0
        return (
          <div className="barra-calma__item" title={daVez.titulo}>
            <span className="barra-calma__rotulo">Lista</span>
            <span className="barra-calma__valor">{daVez.rotulo}</span>
            <span className="disparo-progresso" aria-label={`${pct}%`}><i style={{ width: `${pct}%` }} /></span>
            <span className="barra-calma__valor">{daVez.enviados} de {total}</span>
            <span className="barra-calma__rotulo">faltam {daVez.faltam} · ≈ {tempoDeDisparo(daVez.faltam, d.segMedio)} de disparo</span>
          </div>
        )
      })()}

      {d.listas.filter((l) => l !== daVez).map((l) => (
        <div key={l.chave} className="barra-calma__item" title={l.titulo}>
          <span className="barra-calma__rotulo">{l.faltam === 0 ? `${l.rotulo} ✓` : `Depois: ${l.rotulo}`}</span>
          <span className="barra-calma__valor">{l.faltam === 0 ? l.enviados : l.faltam}</span>
        </div>
      ))}

      {daVez && faltamTodas !== daVez.faltam && (
        <div className="barra-calma__item" title="Todas as listas que ainda vão sair">
          <span className="barra-calma__rotulo">Faltam ao todo</span>
          <span className="barra-calma__valor">{faltamTodas}</span>
        </div>
      )}
      <div className="barra-calma__item" title={d.ultimoEm ? `Último às ${horaEmManaus(new Date(d.ultimoEm))}` : 'Nenhum hoje'}>
        <span className="barra-calma__rotulo">Hoje</span>
        <span className="barra-calma__valor">{d.hoje}</span>
      </div>
      {d.falharamHoje > 0 && (
        <div className="barra-calma__item barra-calma__item--alto" title="Modelos de hoje que a Meta recusou">
          <span className="barra-calma__rotulo">Falharam</span>
          <span className="barra-calma__valor">{d.falharamHoje}</span>
        </div>
      )}
    </div>
  )
}
