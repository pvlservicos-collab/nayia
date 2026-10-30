'use client'

/**
 * CONTACTAR DONO (Pedro, 30/10/2026: "quando clico em WhatsApp não quero assim, quero Contactar dono, e ele abre uma
 * opção: primeiro checa automático se já tem conversa; se não, abre o mesmo menu criar contato para selecionar o número;
 * e quando clicar em criar conversa já cria aquela mesma mensagem que a Nay envia, digitada no WhatsApp, para ele só
 * enviar"). Escolhe o telefone do anúncio, confere em cada linha se já há conversa e abre (ou cria) a conversa com a
 * pergunta da Nay já digitada no campo. Nada é enviado aqui: quem aperta Enviar é a pessoa, no chat.
 */
import { useEffect, useState } from 'react'
import {
  abrirConversa, conversasDoNumero, deixarRascunho, irParaConversa, mensagemDaNay, NOME_DA_LINHA, soDigitos,
  type Anuncio, type LinhaDeEnvio,
} from './contatoDono'

function foneBonito(t: string) {
  let d = soDigitos(t)
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2)
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : t
}

type Linha = { linha: LinhaDeEnvio; configurada: boolean; leadId: string | null }

export default function ContactarDono({ anuncio, aoFechar }: { anuncio: Anuncio; aoFechar: () => void }) {
  const fones = anuncio.telefones || []
  const [fone, setFone] = useState(fones[0] || '')
  const [linhas, setLinhas] = useState<Linha[] | null>(null)
  const [erro, setErro] = useState('')
  const [abrindo, setAbrindo] = useState<LinhaDeEnvio | null>(null)
  const texto = mensagemDaNay(anuncio)

  useEffect(() => {
    if (!fone) return
    let vivo = true
    setLinhas(null); setErro('')
    conversasDoNumero(fone).then((l) => { if (vivo) setLinhas(l) }).catch((e) => { if (vivo) setErro(e.message) })
    return () => { vivo = false }
  }, [fone])

  async function ir(linha: LinhaDeEnvio, leadId: string | null) {
    setAbrindo(linha); setErro('')
    try {
      const id = leadId || await abrirConversa(fone, linha, anuncio.anunciante)
      deixarRascunho(id, texto)
      irParaConversa(id, linha)
    } catch (e: any) {
      setErro(e?.message || 'Não consegui abrir a conversa.')
      setAbrindo(null)
    }
  }

  const ordem: LinhaDeEnvio[] = ['captacao', 'parceria']
  const mostradas = ordem.map((l) => linhas?.find((x) => x.linha === l)).filter((x): x is Linha => !!x)
  return (
    <div className="fixed inset-0 z-[80] flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-label="Contactar dono">
      <div className="absolute inset-0 bg-black/50" onClick={aoFechar} />
      <div className="relative w-full max-w-md rounded-xl border border-line bg-panel p-4 shadow-2xl text-ink max-h-[90vh] overflow-auto">
        <div className="flex items-start justify-between gap-2 mb-2">
          <div className="min-w-0">
            <h3 className="text-base font-bold">Contactar dono</h3>
            <p className="text-xs text-muted truncate">{anuncio.anunciante || 'anunciante'} · {anuncio.titulo}</p>
          </div>
          <button type="button" className="btn btn-outline btn-sm" onClick={aoFechar}>Fechar</button>
        </div>

        {!fones.length ? <p className="text-sm text-muted">Este anúncio não tem telefone no scrap.</p> : (
          <>
            {fones.length > 1 && (
              <div className="mb-3">
                <p className="text-xs font-semibold text-muted mb-1">Qual número</p>
                <div className="flex flex-wrap gap-1.5">
                  {fones.map((t) => (
                    <button key={t} type="button" onClick={() => setFone(t)}
                            className={`px-3 py-1.5 rounded-full border text-sm ${t === fone ? 'bg-accent/15 border-accent text-accent font-semibold' : 'border-line'}`}>
                      {foneBonito(t)}
                    </button>
                  ))}
                </div>
              </div>
            )}
            {fones.length === 1 && <p className="text-sm font-semibold mb-2">{foneBonito(fone)}</p>}

            {!linhas && !erro && <p className="text-sm text-muted">Conferindo se já existe conversa…</p>}
            {linhas && (
              <div className="grid gap-2">
                {mostradas.map((x) => (
                  <div key={x.linha} className="flex items-center gap-2 rounded-lg border border-line px-3 py-2">
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-semibold">{NOME_DA_LINHA[x.linha]}</p>
                      <p className="text-xs text-muted">{!x.configurada ? 'linha não configurada' : x.leadId ? 'já existe conversa com este número' : 'ainda não existe conversa'}</p>
                    </div>
                    <button type="button" disabled={!x.configurada || !!abrindo} onClick={() => void ir(x.linha, x.leadId)}
                            className="btn btn-outline btn-sm disabled:opacity-40 whitespace-nowrap">
                      {abrindo === x.linha ? 'Abrindo…' : x.leadId ? 'Abrir conversa' : 'Criar conversa'}
                    </button>
                  </div>
                ))}
              </div>
            )}
            {erro && <p className="text-xs mt-2" style={{ color: '#dc2626' }}>{erro}</p>}

            <p className="text-xs font-semibold text-muted mt-3 mb-1">A mensagem que vai digitada (você só envia)</p>
            <p className="text-xs whitespace-pre-line rounded-lg bg-black/5 dark:bg-white/5 p-2.5">{texto}</p>
          </>
        )}
      </div>
    </div>
  )
}
