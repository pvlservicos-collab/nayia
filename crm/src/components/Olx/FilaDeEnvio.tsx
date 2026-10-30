'use client'

/**
 * A FILA DE ENVIO (Pedro, 30/10/2026: "embaixo de um imóvel um botão Enviar ou Adicionar à fila, e vai aparecer um
 * carrinho do lado direito do monitor; ele pode selecionar vários e enviar mensagem de uma vez"). O carrinho guarda os
 * anúncios escolhidos; "Enviar a todos" abre a conversa de cada anunciante na linha escolhida e manda a mesma pergunta
 * que a Nay manda, uma a cada poucos segundos. Quem deu certo sai da fila; quem falhou fica, com o motivo.
 */
import { useState } from 'react'
import { ShoppingCartSimple, X } from '@phosphor-icons/react'
import { abrirConversa, enviarTexto, mensagemDaNay, NOME_DA_LINHA, type Anuncio, type LinhaDeEnvio } from './contatoDono'

const ESPERA_ENTRE_ENVIOS_MS = 4000
const reais = (v: number | null | undefined) => (v ? `R$ ${Math.round(Number(v)).toLocaleString('pt-BR')}` : '')

/** Manda a pergunta da Nay ao primeiro telefone do anúncio. Devolve o erro em texto, ou null quando saiu. */
export async function enviarAoDono(a: Anuncio, linha: LinhaDeEnvio): Promise<string | null> {
  const fone = (a.telefones || [])[0]
  if (!fone) return 'sem telefone'
  try {
    const id = await abrirConversa(fone, linha, a.anunciante)
    await enviarTexto(id, mensagemDaNay(a))
    return null
  } catch (e: any) {
    return e?.message || 'não saiu'
  }
}

export default function FilaDeEnvio({ itens, linha, aoMudarLinha, aoTirar, aoEnviados }: {
  itens: Anuncio[]; linha: LinhaDeEnvio; aoMudarLinha: (l: LinhaDeEnvio) => void
  aoTirar: (olxId: number) => void; aoEnviados: (olxIds: number[]) => void
}) {
  const [aberta, setAberta] = useState(false)
  const [confirmando, setConfirmando] = useState(false)
  const [enviando, setEnviando] = useState(false)
  const [estado, setEstado] = useState<Record<number, string>>({})

  if (!itens.length && !aberta) return null

  async function enviarTodos() {
    setEnviando(true); setConfirmando(false)
    const deramCerto: number[] = []
    for (const a of [...itens]) {
      setEstado((e) => ({ ...e, [a.olx_id]: 'enviando…' }))
      const erro = await enviarAoDono(a, linha)
      setEstado((e) => ({ ...e, [a.olx_id]: erro ? `falhou: ${erro}` : 'enviado' }))
      if (!erro) deramCerto.push(a.olx_id)
      await new Promise((r) => setTimeout(r, ESPERA_ENTRE_ENVIOS_MS))
    }
    aoEnviados(deramCerto)
    setEnviando(false)
  }

  return (
    <>
      <button type="button" onClick={() => setAberta((v) => !v)} aria-label="Abrir a fila de envio"
              className="fixed right-4 bottom-4 z-[70] flex items-center gap-2 rounded-full px-4 py-3 text-sm font-semibold text-white shadow-xl"
              style={{ background: 'linear-gradient(135deg, #a855f7, #6d28d9)' }}>
        <ShoppingCartSimple size={20} weight="fill" /> Fila de envio
        <span className="min-w-[22px] h-[22px] px-1 rounded-full bg-white text-[12px] leading-[22px] text-center" style={{ color: '#6d28d9' }}>{itens.length}</span>
      </button>
      {aberta && (
        <aside className="fixed right-0 top-14 bottom-0 z-[75] w-full sm:w-[340px] flex flex-col border-l border-line bg-panel text-ink shadow-2xl">
          <div className="flex items-center justify-between gap-2 px-4 py-3 border-b border-line">
            <h3 className="text-base font-bold flex items-center gap-2"><ShoppingCartSimple size={18} weight="fill" /> Fila de envio ({itens.length})</h3>
            <button type="button" className="btn btn-outline btn-sm" onClick={() => setAberta(false)} aria-label="Fechar"><X size={14} /></button>
          </div>
          <div className="px-4 py-2 border-b border-line">
            <p className="text-xs font-semibold text-muted mb-1">Enviar pelo número</p>
            <div className="flex gap-1.5">
              {(['captacao', 'parceria'] as LinhaDeEnvio[]).map((l) => (
                <button key={l} type="button" onClick={() => aoMudarLinha(l)} disabled={enviando}
                        className={`px-3 py-1.5 rounded-full border text-xs ${linha === l ? 'bg-accent/15 border-accent text-accent font-semibold' : 'border-line'}`}>
                  {NOME_DA_LINHA[l]}
                </button>
              ))}
            </div>
          </div>
          <ul className="flex-1 overflow-auto divide-y divide-line">
            {!itens.length && <li className="p-4 text-sm text-muted">A fila está vazia. Use “Adicionar à fila” nos imóveis.</li>}
            {itens.map((a) => (
              <li key={a.olx_id} className="flex gap-2 p-3 items-start">
                <div className="w-14 h-14 rounded-lg overflow-hidden bg-black/10 shrink-0">
                  {a.fotos?.[0] ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={a.fotos[0]} alt="" referrerPolicy="no-referrer" className="w-full h-full object-cover" />
                  ) : null}
                </div>
                <div className="min-w-0 flex-1 text-xs">
                  <p className="font-semibold truncate">{a.anunciante || 'anunciante'}</p>
                  <p className="text-muted truncate" title={a.titulo || ''}>{a.titulo}</p>
                  <p className="text-muted">{[reais(a.preco), a.bairro].filter(Boolean).join(' · ')}</p>
                  {estado[a.olx_id] && (
                    <p className="font-semibold" style={{ color: estado[a.olx_id].startsWith('falhou') ? '#dc2626' : '#16a34a' }}>{estado[a.olx_id]}</p>
                  )}
                </div>
                <button type="button" onClick={() => aoTirar(a.olx_id)} disabled={enviando} aria-label="Tirar da fila" className="text-muted hover:text-ink disabled:opacity-40"><X size={14} /></button>
              </li>
            ))}
          </ul>
          <div className="p-3 border-t border-line grid gap-2">
            {confirmando ? (
              <>
                <p className="text-xs">Mandar a pergunta da Nay a <b>{itens.length}</b> anunciante{itens.length > 1 ? 's' : ''} pelo {NOME_DA_LINHA[linha]}? Sai uma a cada poucos segundos.</p>
                <div className="flex gap-2">
                  <button type="button" className="btn btn-outline btn-sm flex-1" onClick={() => setConfirmando(false)}>Voltar</button>
                  <button type="button" className="btn btn-sm flex-1 text-white" style={{ background: '#6d28d9' }} onClick={() => void enviarTodos()}>Confirmar envio</button>
                </div>
              </>
            ) : (
              <button type="button" disabled={!itens.length || enviando} onClick={() => setConfirmando(true)}
                      className="btn btn-sm w-full text-white disabled:opacity-40" style={{ background: 'linear-gradient(135deg, #a855f7, #6d28d9)' }}>
                {enviando ? 'Enviando…' : `Enviar a todos (${itens.length})`}
              </button>
            )}
          </div>
        </aside>
      )}
    </>
  )
}
