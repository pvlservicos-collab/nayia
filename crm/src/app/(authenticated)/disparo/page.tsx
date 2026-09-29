'use client'

/**
 * Enviar imóvel -- o disparo direto para um número.
 *
 * Tel, 28/09/2026: "lá em cima o número, embaixo um campo de pesquisar imóvel,
 * digita uma parte e desce uma lista de imóveis, eu seleciono e clico em enviar
 * e ele envia via zapi, eu seleciono também qual número quero enviar, por
 * padrão fica o de parceria".
 *
 * Quem decide o que pode sair é a rota `/api/disparo` (as paredes da Nay:
 * parceiro não sai, indisponível não sai, fotos do mesmo imóvel uma vez a cada
 * 24h por pessoa). A busca mostra só o que é nosso e está disponível, para não
 * oferecer na lista o que a rota vai recusar.
 *
 * POR FAIXA (Tel, 28/09): "enviar intervalo de imóveis, aí eu posso selecionar
 * uma faixa de renda, bairro ou imobiliário e o sistema vai achar e marcar os
 * imóveis para mim confirmar visualmente". A busca é `/api/disparo/buscar`; ela
 * marca os primeiros (até o teto por envio) e ele confere, tira ou põe, e envia
 * pelo mesmo botão.
 */
import { useEffect, useState } from 'react'
import { PaperPlaneTilt } from '@phosphor-icons/react'
import EscolherImoveis, { type ImovelParaEnviar, type OpcaoDoFiltro } from '@/components/Disparo/EscolherImoveis'

interface Linha { id: string; nome: string; tipo: string; padrao: boolean; aviso: string | null }

function formatarTelefone(v: string) {
  const d = v.replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  if (d.length === 11) return `${d.slice(0, 2)} ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `${d.slice(0, 2)} ${d.slice(2, 6)}-${d.slice(6)}`
  return v
}

export default function DisparoPage() {
  const [telefone, setTelefone] = useState('')
  const [linhas, setLinhas] = useState<Linha[]>([])
  const [linhaId, setLinhaId] = useState('')

  const [escolhidos, setEscolhidos] = useState<ImovelParaEnviar[]>([])
  const [enviando, setEnviando] = useState(false)
  const [resposta, setResposta] = useState<{ ok: boolean; texto: string; canal?: string } | null>(null)
  const [teto, setTeto] = useState(10)
  const [opcoes, setOpcoes] = useState<{ bairros: OpcaoDoFiltro[]; tipos: OpcaoDoFiltro[] }>({ bairros: [], tipos: [] })
  // um envio que deu certo limpa a escolha (a chave remonta o componente)
  const [rodada, setRodada] = useState(0)

  useEffect(() => {
    fetch('/api/disparo').then((r) => r.json()).then((j) => {
      const ls: Linha[] = j.linhas || []
      setLinhas(ls)
      setLinhaId((ls.find((l) => l.padrao) || ls[0])?.id || '')
      if (j.opcoes) setOpcoes({ bairros: j.opcoes.bairros || [], tipos: j.opcoes.tipos || [] })
      if (Number(j.teto) > 0) setTeto(Number(j.teto))
    }).catch(() => {})
  }, [])

  const linha = linhas.find((l) => l.id === linhaId)
  const digitos = telefone.replace(/\D/g, '')
  const podeEnviar = digitos.length >= 10 && escolhidos.length > 0 && !enviando && !!linhaId

  async function enviar() {
    if (!podeEnviar) return
    setEnviando(true); setResposta(null)
    try {
      const res = await fetch('/api/disparo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone, integrationId: linhaId, codigos: escolhidos.map((e) => Number(e.codigo)) }),
      })
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'não consegui enviar')
      setResposta({ ok: true, texto: j.resumo || 'Enviado.', canal: j.canal })
      setEscolhidos([])
      setRodada((r) => r + 1)
    } catch (err: any) {
      setResposta({ ok: false, texto: err?.message || 'não consegui enviar' })
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="p-4 md:p-6 max-w-[860px] mx-auto">
      <div className="mb-4">
        <h1 className="text-xl md:text-2xl font-bold text-ink">Enviar imóvel</h1>
        <p className="text-xs md:text-sm text-muted mt-0.5">
          Vai o card dos grupos e as fotos. As regras da Nay valem aqui também: imóvel de parceiro
          e indisponível não saem, e as fotos do mesmo imóvel vão uma vez a cada 24h para cada número.
        </p>
      </div>

      {/* ---- o número e a linha ---- */}
      <div className="panel rounded-xl border border-line p-3 md:p-4 mb-4 grid gap-3 sm:grid-cols-[1fr_240px]">
        <label className="block">
          <span className="text-xs text-muted">Para qual número</span>
          <input
            value={telefone}
            onChange={(e) => { setTelefone(e.target.value); setResposta(null) }}
            onBlur={() => setTelefone((v) => formatarTelefone(v))}
            inputMode="tel"
            placeholder="92 99999-9999"
            className="mt-1 w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-base text-ink"
          />
        </label>
        <label className="block">
          <span className="text-xs text-muted">Por qual WhatsApp</span>
          <select
            value={linhaId}
            onChange={(e) => { setLinhaId(e.target.value); setResposta(null) }}
            className="mt-1 w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
          >
            {linhas.map((l) => (
              <option key={l.id} value={l.id}>{l.nome}{l.padrao ? ' (padrão)' : ''}</option>
            ))}
          </select>
        </label>
        {linha?.aviso && (
          <p className="sm:col-span-2 text-xs text-amber-400">{linha.aviso}</p>
        )}
      </div>

      {/* ---- a busca ---- */}
      <div className="panel rounded-xl border border-line p-3 md:p-4 mb-4">
        <EscolherImoveis key={rodada} escolhidos={escolhidos} aoMudar={(l) => { setEscolhidos(l); setResposta(null) }}
                         teto={teto} opcoes={opcoes}
                         aoAvisar={(texto) => setResposta(texto ? { ok: false, texto } : null)} />

        <button
          type="button"
          onClick={enviar}
          disabled={!podeEnviar}
          className="mt-4 w-full bg-accent text-black font-bold py-2.5 rounded-lg text-sm flex items-center justify-center gap-2 disabled:opacity-40"
        >
          <PaperPlaneTilt size={16} />
          {enviando
            ? 'enviando…'
            : escolhidos.length
              ? `Enviar ${escolhidos.length} imóve${escolhidos.length === 1 ? 'l' : 'is'}${digitos.length >= 10 ? ` para ${formatarTelefone(telefone)}` : ''}`
              : 'Enviar'}
        </button>
      </div>

      {resposta && (
        <div className={`rounded-xl border px-4 py-3 text-sm whitespace-pre-wrap ${
          resposta.ok ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-300'
                      : 'bg-red-500/10 border-red-500/30 text-red-400'}`}>
          {resposta.texto}
          {resposta.ok && resposta.canal === 'parceria' && (
            <p className="mt-2 text-xs text-muted">
              Sai pela fila da Nay em alguns segundos, uma foto de cada vez (entre 6h e 22h; fora disso, às 6h).
            </p>
          )}
        </div>
      )}
    </div>
  )
}
