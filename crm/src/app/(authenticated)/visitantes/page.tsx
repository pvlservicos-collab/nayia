'use client'

/**
 * VISITANTES (Pedro, 20/10/2026: "cria uma aba lá no CRM VISITANTES: lá vai ter um registro de todos os clientes e
 * corretores que já visitaram com a gente por dia, mês, trimestre e total; aí eu vou poder filtrar pelos corretores, ou
 * pelos leads, e cria uma lista com o filtro que cliquei").
 *
 * As visitas que aconteceram vêm de /api/visitantes (crm_visitantes, 427). O período escolhe as datas; "Corretores" ou
 * "Clientes" agrupa por pessoa (quantas visitas, a última, os imóveis). A lista do filtro sai em CSV ou com os
 * telefones copiados.
 */
import { Fragment, useEffect, useMemo, useState } from 'react'

type Visita = {
  origem: 'parceria' | 'olx'; id: number; quando: string; codigo: number | null; imovel: string | null; estado: string
  resultado: string | null; corretor: string | null; corretor_telefone: string | null; cliente: string | null; cliente_telefone: string | null
}
type Periodo = 'dia' | 'mes' | 'trimestre' | 'total'
type Quem = 'corretores' | 'clientes'

function hojeEmManaus() {
  return new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Manaus' })
}
function fone(t: string | null | undefined) {
  let d = String(t || '').replace(/\D/g, '')
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2)
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : (t || '')
}
function quando(iso: string) {
  return new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Manaus' })
}
function ultimoDia(ano: number, mes: number) { return new Date(Date.UTC(ano, mes, 0)).getUTCDate() }

function intervalo(p: Periodo, dia: string, mes: string, ano: number, tri: number): { de: string; ate: string } | null {
  if (p === 'total') return null
  if (p === 'dia') return { de: dia, ate: dia }
  if (p === 'mes') {
    const [a, m] = mes.split('-').map(Number)
    return { de: `${mes}-01`, ate: `${mes}-${String(ultimoDia(a, m)).padStart(2, '0')}` }
  }
  const m1 = (tri - 1) * 3 + 1, m3 = m1 + 2
  return { de: `${ano}-${String(m1).padStart(2, '0')}-01`, ate: `${ano}-${String(m3).padStart(2, '0')}-${String(ultimoDia(ano, m3)).padStart(2, '0')}` }
}

export default function VisitantesPage() {
  const hoje = hojeEmManaus()
  const [periodo, setPeriodo] = useState<Periodo>('mes')
  const [dia, setDia] = useState(hoje)
  const [mes, setMes] = useState(hoje.slice(0, 7))
  const [ano, setAno] = useState(Number(hoje.slice(0, 4)))
  const [tri, setTri] = useState(Math.floor((Number(hoje.slice(5, 7)) - 1) / 3) + 1)
  const [quem, setQuem] = useState<Quem>('corretores')
  const [visitas, setVisitas] = useState<Visita[]>([])
  const [carregando, setCarregando] = useState(true)
  const [aberto, setAberto] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [recado, setRecado] = useState('')

  const faixa = intervalo(periodo, dia, mes, ano, tri)
  useEffect(() => {
    setCarregando(true)
    const q = faixa ? `?de=${faixa.de}&ate=${faixa.ate}` : ''
    fetch(`/api/visitantes${q}`).then((r) => r.json()).then((j) => setVisitas(j.visitas || [])).finally(() => setCarregando(false))
  }, [faixa?.de, faixa?.ate]) // eslint-disable-line react-hooks/exhaustive-deps

  const pessoas = useMemo(() => {
    const m = new Map<string, { chave: string; nome: string; telefone: string; visitas: Visita[] }>()
    for (const v of visitas) {
      const nome = quem === 'corretores' ? v.corretor : v.cliente
      const tel = quem === 'corretores' ? v.corretor_telefone : v.cliente_telefone
      if (!nome && !tel) continue
      const d = String(tel || '').replace(/\D/g, '')
      const chave = d.length >= 8 ? d.slice(-8) : `n:${String(nome).toLowerCase().trim()}`
      const p = m.get(chave) || { chave, nome: nome || '', telefone: tel || '', visitas: [] }
      if (!p.nome && nome) p.nome = nome
      p.visitas.push(v)
      m.set(chave, p)
    }
    const t = busca.trim().toLowerCase()
    return [...m.values()]
      .filter((p) => !t || p.nome.toLowerCase().includes(t) || p.telefone.includes(t.replace(/\D/g, '') || '§'))
      .sort((a, b) => b.visitas.length - a.visitas.length || (a.visitas[0]?.quando < b.visitas[0]?.quando ? 1 : -1))
  }, [visitas, quem, busca])

  const semPessoa = visitas.filter((v) => (quem === 'corretores' ? !v.corretor && !v.corretor_telefone : !v.cliente && !v.cliente_telefone)).length

  const baixar = () => {
    const linhas = [['nome', 'telefone', 'visitas', 'ultima_visita', 'imoveis']]
    for (const p of pessoas) {
      linhas.push([p.nome, fone(p.telefone), String(p.visitas.length), quando(p.visitas[0].quando),
                   [...new Set(p.visitas.map((v) => v.imovel || (v.codigo ? `código ${v.codigo}` : '')))].filter(Boolean).join(' | ')])
    }
    const texto = linhas.map((l) => l.map((x) => `"${String(x).replace(/"/g, '""')}"`).join(';')).join('\r\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob(['﻿' + texto], { type: 'text/csv;charset=utf-8' }))
    a.download = `visitantes-${quem}-${faixa ? `${faixa.de}_a_${faixa.ate}` : 'total'}.csv`
    document.body.appendChild(a); a.click(); a.remove()
  }
  const copiar = async () => {
    const tels = pessoas.map((p) => String(p.telefone).replace(/\D/g, '')).filter((t) => t.length >= 10)
    try { await navigator.clipboard.writeText(tels.join('\n')); setRecado(`${tels.length} telefones copiados.`) } catch { setRecado('Não consegui copiar.') }
    setTimeout(() => setRecado(''), 4000)
  }

  const chip = (on: boolean) => `px-3 py-1.5 rounded-full border text-sm ${on ? 'bg-accent/15 border-accent/40 text-accent font-semibold' : 'border-line text-ink-2'}`
  const campo = 'px-3 py-1.5 border border-line rounded-lg text-sm text-ink bg-transparent'

  return (
    <div className="max-w-6xl mx-auto px-4 py-6">
      <h1 className="text-2xl font-bold text-ink pb-1">Visitantes</h1>
      <p className="text-sm text-muted mb-4">
        Os corretores e os clientes que já visitaram um imóvel com a gente: as visitas encerradas da Parceria e as visitas
        confirmadas dos clientes do WhatsApp Leads que já passaram.
      </p>

      <div className="flex flex-wrap items-center gap-2 mb-3">
        {([['dia', 'Dia'], ['mes', 'Mês'], ['trimestre', 'Trimestre'], ['total', 'Total']] as const).map(([k, r]) => (
          <button key={k} type="button" className={chip(periodo === k)} onClick={() => setPeriodo(k)}>{r}</button>
        ))}
        {periodo === 'dia' && <input type="date" className={campo} value={dia} onChange={(e) => setDia(e.target.value)} style={{ colorScheme: 'light dark' }} />}
        {periodo === 'mes' && <input type="month" className={campo} value={mes} onChange={(e) => setMes(e.target.value)} style={{ colorScheme: 'light dark' }} />}
        {periodo === 'trimestre' && (
          <>
            <select className={campo} value={tri} onChange={(e) => setTri(Number(e.target.value))}>
              {[1, 2, 3, 4].map((t) => <option key={t} value={t}>{t}º trimestre</option>)}
            </select>
            <input type="number" className={`${campo} w-24`} value={ano} onChange={(e) => setAno(Number(e.target.value) || ano)} />
          </>
        )}
      </div>
      <div className="flex flex-wrap items-center gap-2 mb-4">
        <button type="button" className={chip(quem === 'corretores')} onClick={() => setQuem('corretores')}>Corretores</button>
        <button type="button" className={chip(quem === 'clientes')} onClick={() => setQuem('clientes')}>Clientes (leads)</button>
        <input className={`${campo} flex-1 min-w-[200px]`} placeholder="Procurar por nome ou telefone" value={busca} onChange={(e) => setBusca(e.target.value)} />
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <div className="rounded-xl border border-line bg-panel p-3"><p className="text-xs text-muted">Visitas no período</p><p className="text-2xl font-bold text-ink">{visitas.length}</p></div>
        <div className="rounded-xl border border-line bg-panel p-3"><p className="text-xs text-muted">{quem === 'corretores' ? 'Corretores' : 'Clientes'} diferentes</p><p className="text-2xl font-bold text-ink">{pessoas.length}</p></div>
        <div className="rounded-xl border border-line bg-panel p-3"><p className="text-xs text-muted">Pela Parceria</p><p className="text-2xl font-bold text-ink">{visitas.filter((v) => v.origem === 'parceria').length}</p></div>
        <div className="rounded-xl border border-line bg-panel p-3"><p className="text-xs text-muted">Pelo WhatsApp Leads</p><p className="text-2xl font-bold text-ink">{visitas.filter((v) => v.origem === 'olx').length}</p></div>
      </div>

      <div className="flex flex-wrap items-center gap-2 mb-2">
        <h2 className="text-lg font-semibold text-ink mr-auto">
          Lista: {quem === 'corretores' ? 'corretores' : 'clientes'} {faixa ? (faixa.de === faixa.ate ? `do dia ${faixa.de.split('-').reverse().join('/')}` : `de ${faixa.de.split('-').reverse().join('/')} a ${faixa.ate.split('-').reverse().join('/')}`) : '(total)'}
        </h2>
        <button type="button" className="btn btn-outline btn-sm" onClick={copiar} disabled={!pessoas.length}>Copiar telefones</button>
        <button type="button" className="btn btn-primary btn-sm" onClick={baixar} disabled={!pessoas.length}>Baixar a lista (CSV)</button>
        {recado && <span className="text-sm text-muted">{recado}</span>}
      </div>
      {semPessoa > 0 && (
        <p className="text-xs text-muted mb-2">{semPessoa} visita(s) sem {quem === 'corretores' ? 'corretor' : 'cliente'} anotado ficaram fora da lista.</p>
      )}

      {carregando ? <p className="text-sm text-muted">Carregando…</p> : !pessoas.length ? (
        <p className="text-sm text-muted">Ninguém visitou neste período.</p>
      ) : (
        <div className="rounded-xl border border-line overflow-hidden">
          <table className="w-full text-sm text-ink">
            <thead className="bg-panel text-left text-xs text-muted">
              <tr><th className="px-3 py-2">Nome</th><th className="px-3 py-2">Telefone</th><th className="px-3 py-2">Visitas</th>
                <th className="px-3 py-2">Última visita</th><th className="px-3 py-2">Imóveis</th></tr>
            </thead>
            <tbody>
              {pessoas.map((p) => (
                <Fragment key={p.chave}>
                  <tr className="border-t border-line cursor-pointer hover:bg-panel" onClick={() => setAberto(aberto === p.chave ? null : p.chave)}>
                    <td className="px-3 py-2 font-medium">{p.nome || '(sem nome)'}</td>
                    <td className="px-3 py-2">{fone(p.telefone)}</td>
                    <td className="px-3 py-2">{p.visitas.length}</td>
                    <td className="px-3 py-2">{quando(p.visitas[0].quando)}</td>
                    <td className="px-3 py-2 text-muted truncate max-w-[320px]">
                      {[...new Set(p.visitas.map((v) => v.imovel || (v.codigo ? `código ${v.codigo}` : '')))].filter(Boolean).join(' · ')}
                    </td>
                  </tr>
                  {aberto === p.chave && (
                    <tr className="border-t border-line bg-panel">
                      <td colSpan={5} className="px-3 py-2">
                        {p.visitas.map((v) => (
                          <div key={`${v.origem}-${v.id}`} className="text-xs py-0.5">
                            {quando(v.quando)} · {v.imovel || `código ${v.codigo}`} · {v.origem === 'olx' ? 'WhatsApp Leads' : 'Parceria'}
                            {quem === 'corretores' && v.cliente ? ` · cliente ${v.cliente}` : ''}
                            {quem === 'clientes' && v.corretor ? ` · corretor ${v.corretor}` : ''}
                            {v.resultado ? ` · ${v.resultado}` : ''}
                          </div>
                        ))}
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
