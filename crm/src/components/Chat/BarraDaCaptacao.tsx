'use client'

/**
 * A BARRA DA CAPTAÇÃO (Pedro, 29/09/2026): "quero outra linha dessa lá em
 * captação mostrando quantos contatados até agora no dia de hoje, quantos
 * disponíveis, quantos alugados, todos os status lá, e um botão enviar
 * relatório ao Tel".
 *
 * A mesma faixa escura da barra da Parceria, no topo da aba da captação:
 * HOJE (disparos e quem respondeu), as seis etapas do funil (as mesmas das
 * tags e do Pipeline) e a fila. O botão mostra o relatório antes de mandar --
 * o mesmo texto do das 18h, para o mesmo número, pela linha da captação (ver
 * /api/captacao/relatorio e a migração 178).
 */
import { useEffect, useState } from 'react'
import { PaperPlaneTilt, X, CheckCircle, Warning, Copy } from '@phosphor-icons/react'
import type { PlacarDaCaptacao } from '@/lib/nayLeitura'

const ETAPAS: Array<{ chave: keyof PlacarDaCaptacao; rotulo: string; cor: string }> = [
  { chave: 'naoRespondeu', rotulo: 'NÃO RESPONDEU', cor: '#94a3b8' },
  { chave: 'respondeu', rotulo: 'RESPONDEU', cor: '#38bdf8' },
  { chave: 'disponivel', rotulo: 'DISPONÍVEL', cor: '#22c55e' },
  { chave: 'alugado', rotulo: 'ALUGADO', cor: '#f59e0b' },
  { chave: 'vendido', rotulo: 'VENDIDO', cor: '#a78bfa' },
  { chave: 'mandouDados', rotulo: 'DADOS', cor: '#f472b6' },
]

type EstadoDoEnvio = 'lendo' | 'pronto' | 'enviando' | 'enviado' | 'erro'

export default function BarraDaCaptacao() {
  const [placar, setPlacar] = useState<PlacarDaCaptacao | null>(null)
  const [janela, setJanela] = useState(false)
  const [texto, setTexto] = useState('')
  const [envio, setEnvio] = useState<EstadoDoEnvio>('lendo')
  const [erro, setErro] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true
    const ler = async () => {
      try {
        const r = await fetch('/api/captacao/placar')
        const j = await r.json()
        if (r.ok && vivo) setPlacar(j.placar)
      } catch { /* a barra fica com o último número */ }
    }
    void ler()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void ler() }, 30_000)
    return () => { vivo = false; clearInterval(t) }
  }, [])

  useEffect(() => {
    if (!janela) return
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape' && envio !== 'enviando') setJanela(false) }
    document.addEventListener('keydown', esc)
    return () => document.removeEventListener('keydown', esc)
  }, [janela, envio])

  const abrirRelatorio = async () => {
    setJanela(true); setEnvio('lendo'); setErro(null); setTexto('')
    try {
      const r = await fetch('/api/captacao/relatorio')
      const j = await r.json()
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      if (!j.temDestino) throw new Error('A captação não tem o número do relatório configurado.')
      setTexto(j.mensagem); setEnvio('pronto')
    } catch (e: any) {
      setErro(e?.message || 'Não consegui montar o relatório.'); setEnvio('erro')
    }
  }

  const mandar = async () => {
    setEnvio('enviando'); setErro(null)
    try {
      const r = await fetch('/api/captacao/relatorio', { method: 'POST' })
      const j = await r.json()
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      setTexto(j.mensagem || texto); setEnvio('enviado')
    } catch (e: any) {
      setErro(e?.message || 'Não consegui mandar.'); setEnvio('erro')
    }
  }

  /* COPIAR O RELATÓRIO (Pedro, 29/09: "uma opção de copiar o relatório ao lado
     do botão enviar"): o mesmo texto do enviar, direto para a área de
     transferência -- para colar onde quiser. */
  const [copia, setCopia] = useState<'nada' | 'copiando' | 'copiado' | 'erro'>('nada')
  const copiarRelatorio = async () => {
    setCopia('copiando')
    try {
      const r = await fetch('/api/captacao/relatorio')
      const j = await r.json()
      if (!r.ok || !j?.mensagem) throw new Error(j?.error || 'sem texto')
      try {
        await navigator.clipboard.writeText(j.mensagem)
      } catch {
        // sem permissão da área de transferência: o jeito antigo
        const area = document.createElement('textarea')
        area.value = j.mensagem
        area.style.position = 'fixed'; area.style.opacity = '0'
        document.body.appendChild(area); area.select()
        document.execCommand('copy')
        area.remove()
      }
      setCopia('copiado')
    } catch {
      setCopia('erro')
    }
    setTimeout(() => setCopia('nada'), 2500)
  }

  const p = placar
  const v = (n: number | undefined) => (p ? String(n ?? 0) : '…')
  const semTeto = !p || p.tetoHoje >= 999

  return (
    <div className="painel-barra painel-barra--linha" aria-label="Números da captação">
      <div className="painel-barra__rola"
           onWheel={(e) => { if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) e.currentTarget.scrollLeft += e.deltaY }}>
        {/* HOJE (Pedro, 29/09: "ajusta as métricas, tá estranho; põe total de
            mensagens enviadas") -- o dia de um lado, o total da campanha do outro */}
        <div className="painel-barra__hoje">
          <span className="painel-barra__hoje-rotulo">HOJE</span>
          <span className="painel-barra__placar-rotulo" title="Primeira mensagem da campanha para um proprietário">DISPAROS</span>
          <span className="painel-barra__hoje-numero">{v(p?.disparosHoje)}{!semTeto && <small className="text-[13px] opacity-70">/{p?.tetoHoje}</small>}</span>
          <span className="painel-barra__placar-rotulo"
                title={p ? `Tudo o que o número da captação mandou hoje: ${p.enviadasHojeDisparo} disparos, ${p.enviadasHojeNay} respostas da Nay, ${p.enviadasHojeEquipe} da equipe` : ''}>ENVIADAS</span>
          <span className="painel-barra__hoje-numero">{v(p?.enviadasHoje)}</span>
          <span className="painel-barra__placar-rotulo" title="Proprietários da campanha que responderam hoje">RESPONDERAM</span>
          <span className="painel-barra__hoje-numero">{v(p?.pessoasHoje)}</span>
          {!!p?.falharamHoje && <span className="painel-barra__aviso" title="Disparos de hoje que falharam"><Warning size={14} weight="fill" />{p.falharamHoje} falharam</span>}
        </div>
        <div className="painel-barra__total-rotulo" title="Desde o começo da campanha">TOTAL</div>
        {ETAPAS.map((e) => (
          <div key={e.chave} className="painel-barra__placar" title={`Proprietários na etapa "${e.chave === 'mandouDados' ? 'mandou os dados' : e.rotulo.toLowerCase()}" (todos os disparados)`}>
            <span className="painel-barra__ponto" style={{ background: e.cor, boxShadow: `0 0 8px ${e.cor}` }} />
            <span className="painel-barra__placar-rotulo">{e.rotulo}</span>
            <span className="painel-barra__placar-valor">{v(p?.[e.chave] as number | undefined)}</span>
          </div>
        ))}
        <div className="painel-barra__placar" title="Mensagens que o número da captação mandou desde o começo (disparos, Nay e equipe)">
          <span className="painel-barra__placar-rotulo">ENVIADAS</span>
          <span className="painel-barra__placar-valor">{v(p?.enviadasTotal)}</span>
        </div>
        <div className="painel-barra__placar"
             title={p ? `Para chamar: ${p.nuncaChamados} nunca chamados e ${p.perguntarDeNovo} para perguntar de novo (de ${p.total} na campanha)` : ''}>
          <span className="painel-barra__placar-rotulo">FILA</span>
          <span className="painel-barra__placar-valor">{p ? p.nuncaChamados + p.perguntarDeNovo : '…'}</span>
        </div>
        {p?.modoTeste && <div className="painel-barra__placar painel-barra__placar--alerta"><span className="painel-barra__placar-valor painel-barra__placar-valor--texto">MODO TESTE</span></div>}
        {p?.pausada && <div className="painel-barra__placar painel-barra__placar--alerta"><span className="painel-barra__placar-valor painel-barra__placar-valor--texto">DISPARO PAUSADO</span></div>}
      </div>

      <button type="button" onClick={() => void copiarRelatorio()} disabled={copia === 'copiando'}
              className="painel-barra__botao painel-barra__botao--contorno" title="Copiar o relatório de hoje">
        {copia === 'copiado' ? <CheckCircle size={16} weight="fill" /> : <Copy size={16} weight="bold" />}
        <span>{copia === 'copiado' ? 'Copiado' : copia === 'erro' ? 'Não copiou' : 'Copiar'}</span>
      </button>
      <button type="button" onClick={abrirRelatorio} className="painel-barra__botao" style={{ marginLeft: 0 }} title="Enviar o relatório de hoje ao Tel (mostra antes de mandar)">
        <PaperPlaneTilt size={16} weight="fill" />
        <span>Enviar ao Tel</span>
      </button>

      {janela && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center p-4" onClick={() => envio !== 'enviando' && setJanela(false)}>
          <div className="absolute inset-0 bg-black/50" />
          <div role="dialog" aria-label="Relatório da captação" onClick={(e) => e.stopPropagation()}
               className="relative w-[min(440px,100%)] rounded-2xl shadow-2xl flex flex-col max-h-[85vh]"
               style={{ background: 'var(--wa-panel)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}>
            <div className="flex items-center justify-between px-4 pt-3 pb-2">
              <span className="text-[15px] font-semibold">Relatório da captação</span>
              <button type="button" onClick={() => setJanela(false)} disabled={envio === 'enviando'} aria-label="Fechar"
                      className="p-1 rounded-full hover:bg-[var(--wa-row-hover)]"><X size={18} style={{ color: 'var(--wa-text-2)' }} /></button>
            </div>
            <div className="px-4 pb-2 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
              Vai para o Tel pelo número da captação, no mesmo número do relatório automático do fim da captação.
            </div>
            <div className="mx-4 mb-3 rounded-lg px-3 py-2.5 overflow-y-auto wa-rolagem text-[14px] leading-[1.45] whitespace-pre-wrap"
                 style={{ background: 'var(--wa-out)', color: 'var(--wa-text)', minHeight: 120 }}>
              {envio === 'lendo' ? 'Montando…' : texto || (erro ?? '')}
            </div>
            {erro && envio === 'erro' && texto && <p className="mx-4 mb-2 text-[13px]" style={{ color: '#ef4444' }}>{erro}</p>}
            <div className="flex items-center justify-end gap-2 px-4 pb-4">
              {envio === 'enviado' ? (
                <>
                  <span className="flex items-center gap-1.5 text-[14px] font-medium mr-auto" style={{ color: 'var(--wa-green)' }}>
                    <CheckCircle size={18} weight="fill" /> Enviado ao Tel
                  </span>
                  <button type="button" onClick={() => setJanela(false)} className="painel-barra__botao painel-barra__botao--janela">Fechar</button>
                </>
              ) : (
                <>
                  <button type="button" onClick={() => setJanela(false)} disabled={envio === 'enviando'}
                          className="px-3 py-2 rounded-full text-[14px]" style={{ color: 'var(--wa-text-2)' }}>Cancelar</button>
                  <button type="button" onClick={mandar} disabled={envio !== 'pronto' && !(envio === 'erro' && !!texto)}
                          className="painel-barra__botao painel-barra__botao--janela disabled:opacity-50">
                    <PaperPlaneTilt size={16} weight="fill" />
                    {envio === 'enviando' ? 'Enviando…' : 'Enviar ao Tel'}
                  </button>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
