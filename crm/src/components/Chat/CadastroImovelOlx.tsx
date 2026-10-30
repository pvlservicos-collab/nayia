'use client'

/**
 * CADASTRAR IMÓVEL PELO LINK DA OLX (535, Pedro 30/10/2026): "uma segunda barra à direita, de cadastrar o imóvel desse
 * contato; um botão lá em cima, Cadastrar imóvel; se eu pegar o link da OLX da pessoa e colar lá, o nosso sistema já
 * puxa todos os dados do imóvel, dá a pontuação de quantos dados tem, e eu já posso clicar em publicar imóvel como
 * disponível ... e o sistema já vai montar o card para eu enviar em seguida para um lead" e "quero que tenha uma barra
 * de cadastro que mostra o funcionamento do nosso sistema e, se der erro, qual erro". Entra como PARCEIRO NOVO
 * disponível: fora do site, vai aos leads do WhatsApp Leads (8595).
 *
 * Os passos, cada um com o que aconteceu ou o erro:
 *   1 link · 2 anúncio (base raspada da OLX, no servidor: /admin/api/imoveis/olx/do-link) · 3 pré-cadastro (Rascunho)
 *   4 fotos (o servidor baixa uma a uma: /olx/<cod>/foto) · 5 pontuação (/olx/<cod>/estado)
 *   6 publicar (PUT de sempre: Disponível, parceiro, o contato como proprietário) · 7 card de cliente · 8 enviar ao lead
 *   (a fila do 8595, crm_captacao_enviar_imoveis: corretor não recebe parceiro).
 */
import { useEffect, useRef, useState } from 'react'
import { CheckCircle, CircleNotch, MinusCircle, PaperPlaneRight, WarningCircle, X } from '@phosphor-icons/react'
import type { LeadWithOwner } from '@/lib/types'

type Estado = 'espera' | 'andando' | 'ok' | 'erro'
type Passo = { chave: string; rotulo: string; estado: Estado; detalhe?: string }

const PASSOS: Array<[string, string]> = [
  ['link', 'Ler o link'],
  ['anuncio', 'Achar o anúncio da OLX'],
  ['cadastro', 'Criar o pré-cadastro'],
  ['fotos', 'Baixar as fotos'],
  ['pontuacao', 'Conferir o cadastro'],
  ['publicar', 'Publicar disponível (parceiro novo)'],
  ['card', 'Montar o card'],
  ['enviar', 'Enviar ao lead'],
]

// os campos que a barra deixa corrigir antes de publicar (os mesmos nomes do PUT /admin/api/imoveis/<cod>)
const CAMPOS: Array<{ chave: string; rotulo: string; numero?: boolean }> = [
  { chave: 'tipo', rotulo: 'Tipo' },
  { chave: 'valor_venda', rotulo: 'Venda (R$)', numero: true },
  { chave: 'valor_aluguel', rotulo: 'Aluguel (R$)', numero: true },
  { chave: 'quartos', rotulo: 'Quartos', numero: true },
  { chave: 'suites', rotulo: 'Suítes', numero: true },
  { chave: 'banheiros', rotulo: 'Banheiros', numero: true },
  { chave: 'vagas', rotulo: 'Vagas', numero: true },
  { chave: 'area_util', rotulo: 'Área (m²)', numero: true },
  { chave: 'bairro', rotulo: 'Bairro' },
  { chave: 'mobilia', rotulo: 'Mobília' },
]
// o condomínio só muda escolhendo um da tabela (condo_id), no editar do imóvel: aqui ele só aparece

const MAX_FOTOS = 30

async function lerJson(r: Response) {
  return r.json().catch(() => ({} as any))
}
function erroDe(j: any, r: Response) {
  return String(j?.erro || j?.error || j?.mensagem || `o servidor respondeu ${r.status}`) + (j?.detalhe ? ` (${j.detalhe})` : '')
}

export default function CadastroImovelOlx({ lead, modo, aoFechar }: {
  lead: LeadWithOwner
  modo: 'lateral' | 'gaveta'
  aoFechar: () => void
}) {
  const [link, setLink] = useState('')
  const [passos, setPassos] = useState<Passo[]>(PASSOS.map(([chave, rotulo]) => ({ chave, rotulo, estado: 'espera' })))
  const [rodando, setRodando] = useState(false)
  const [codigo, setCodigo] = useState<number | null>(null)
  const [campos, setCampos] = useState<Record<string, any>>({})
  const [originais, setOriginais] = useState<Record<string, any>>({})
  const [estado, setEstado] = useState<any>(null)
  const [fotos, setFotos] = useState<string[]>([])
  const [card, setCard] = useState<string | null>(null)
  const [donoEContato, setDonoEContato] = useState(true)
  const [busca, setBusca] = useState('')
  const [leads, setLeads] = useState<Array<{ nome: string | null; telefone: string }>>([])
  const vivo = useRef(true)
  useEffect(() => () => { vivo.current = false }, [])

  function marcar(chave: string, e: Estado, detalhe?: string) {
    if (!vivo.current) return
    setPassos((ps) => ps.map((p) => (p.chave === chave ? { ...p, estado: e, detalhe } : p)))
  }
  function zerar() {
    setPassos(PASSOS.map(([chave, rotulo]) => ({ chave, rotulo, estado: 'espera' })))
    setCodigo(null); setCampos({}); setOriginais({}); setEstado(null); setFotos([]); setCard(null)
  }

  async function lerEstado(cod: number) {
    marcar('pontuacao', 'andando')
    const r = await fetch(`/admin/api/imoveis/olx/${cod}/estado`)
    const j = await lerJson(r)
    if (!r.ok) { marcar('pontuacao', 'erro', erroDe(j, r)); return null }
    setEstado(j)
    const falta = Array.isArray(j.falta) && j.falta.length ? ` · falta: ${j.falta.join(', ')}` : ''
    marcar('pontuacao', 'ok', `${j.pct ?? 0}% do cadastro · ${j.fotos} fotos · ${j.status}${falta}`)
    return j
  }

  async function puxar() {
    const url = link.trim()
    if (!url || rodando) return
    zerar()
    setRodando(true)
    try {
      // 1. o link
      marcar('link', 'andando')
      if (!/^https:\/\/([a-z0-9-]+\.)*olx\.com\.br\//i.test(url)) {
        marcar('link', 'erro', 'esse link não é da OLX: copie o endereço do anúncio (começa com https:// e tem olx.com.br)')
        return
      }
      marcar('link', 'ok')

      // 2 e 3. o anúncio na base raspada e o pré-cadastro
      marcar('anuncio', 'andando')
      const r = await fetch('/admin/api/imoveis/olx/do-link', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }),
      })
      const j = await lerJson(r)
      if (!r.ok) {
        const onde = j?.passo === 'link' ? 'link' : j?.passo === 'cadastro' ? 'cadastro' : 'anuncio'
        if (onde === 'cadastro') marcar('anuncio', 'ok')
        marcar(onde, 'erro', erroDe(j, r))
        return
      }
      marcar('anuncio', 'ok', `${j.titulo || 'anúncio'} · ${j.fonte || ''}`)
      const cod = Number(j.codigo)
      setCodigo(cod)
      marcar('cadastro', 'ok', j.novo ? `#${cod} criado como Rascunho` : `#${cod} já existia (${j.situacao}): abri o que existe, sem duplicar`)
      const c = j.campos || {}
      setCampos(c); setOriginais(c)

      // 4. as fotos: o servidor baixa uma por vez
      const lista: string[] = (j.fotos || []).slice(0, MAX_FOTOS)
      if (!lista.length) {
        marcar('fotos', 'ok', j.fotos_ja ? `já tinha ${j.fotos_ja} fotos` : 'o anúncio não tem fotos')
      } else {
        const erros: string[] = []
        const baixadas: string[] = []
        for (let n = 0; n < lista.length; n++) {
          marcar('fotos', 'andando', `${n + 1} de ${lista.length}…`)
          const rf = await fetch(`/admin/api/imoveis/olx/${cod}/foto`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url: lista[n], ordem: n + 1 }),
          })
          const jf = await lerJson(rf)
          if (rf.ok && jf?.url) { baixadas.push(jf.url); if (vivo.current) setFotos([...baixadas]) }
          else erros.push(`foto ${n + 1}: ${erroDe(jf, rf)}`)
        }
        marcar('fotos', erros.length && !baixadas.length ? 'erro' : 'ok',
               `${baixadas.length} de ${lista.length} baixadas${erros.length ? ` · ${erros.slice(0, 3).join(' · ')}` : ''}`)
      }

      // 5. a pontuação
      await lerEstado(cod)
    } catch (e: any) {
      marcar('anuncio', 'erro', `não consegui falar com o servidor: ${e?.message || e}`)
    } finally {
      if (vivo.current) setRodando(false)
    }
  }

  async function publicar() {
    if (!codigo || rodando) return
    setRodando(true)
    marcar('publicar', 'andando')
    try {
      const corpo: Record<string, any> = { status: 'Disponível', e_parceiro: true }
      for (const c of CAMPOS) {
        const v = campos[c.chave]
        if (String(v ?? '') === String(originais[c.chave] ?? '')) continue
        // como foi digitado: o servidor lê número no jeito brasileiro ("410.000", "89,5")
        corpo[c.chave] = v === '' || v === undefined ? null : String(v).trim()
      }
      const fone = String(lead.phone || '').replace(/\D/g, '')
      if (donoEContato && fone.length >= 10) {
        const nome = String(lead.title || '').replace(/\D/g, '') === fone || !lead.title ? null : lead.title
        corpo.proprietario = { nome, telefone: fone }
      }
      const r = await fetch(`/admin/api/imoveis/${codigo}`, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo),
      })
      const j = await lerJson(r)
      if (!r.ok) {
        // a validação do editar devolve a lista em `detalhes` (ex.: "valor_venda: valor inválido")
        marcar('publicar', 'erro', Array.isArray(j?.detalhes) && j.detalhes.length ? j.detalhes.join(' · ') : erroDe(j, r))
        return
      }
      setOriginais({ ...campos })
      const e = await lerEstado(codigo)
      marcar('publicar', e?.status === 'Disponível' ? 'ok' : 'erro',
             e?.status === 'Disponível' ? `#${codigo} Disponível, parceiro novo: vai aos leads do 8595 (fora do site)`
                                        : `salvou, mas a situação ficou "${e?.status ?? '?'}"`)

      // 7. o card de cliente
      marcar('card', 'andando')
      const rc = await fetch(`/api/imoveis-nay/card/${codigo}?cliente=1`)
      const jc = await lerJson(rc)
      if (!rc.ok || !jc?.card) { marcar('card', 'erro', erroDe(jc, rc)); return }
      setCard(String(jc.card))
      marcar('card', 'ok', `pronto, com ${(jc.fotos || []).length} fotos`)
    } catch (e: any) {
      marcar('publicar', 'erro', `não consegui falar com o servidor: ${e?.message || e}`)
    } finally {
      if (vivo.current) setRodando(false)
    }
  }

  // 8. o lead: a mesma busca da Busca OLX manual (nome ou número)
  useEffect(() => {
    const q = busca.trim()
    if (q.length < 2) { setLeads([]); return }
    const t = setTimeout(async () => {
      try {
        const r = await fetch(`/api/olx/scrap/leads?q=${encodeURIComponent(q)}`)
        const j = await lerJson(r)
        if (vivo.current) setLeads(r.ok ? (j.leads || []).slice(0, 8) : [])
      } catch { /* a lista só não desce */ }
    }, 300)
    return () => clearTimeout(t)
  }, [busca])

  async function enviar(l: { nome: string | null; telefone: string }) {
    if (!codigo) return
    setLeads([]); setBusca('')
    marcar('enviar', 'andando', `para ${l.nome || l.telefone}…`)
    try {
      const r = await fetch('/api/captacao/enviar-imoveis', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ telefone: l.telefone, codigos: [codigo] }),
      })
      const j = await lerJson(r)
      if (!r.ok || !j?.id) { marcar('enviar', 'erro', erroDe(j, r)); return }
      // a Nay do WhatsApp manda em alguns segundos: acompanha até ela dizer
      for (let n = 0; n < 30 && vivo.current; n++) {
        await new Promise((ok) => setTimeout(ok, 3000))
        const re = await fetch(`/api/captacao/enviar-imoveis?id=${j.id}`)
        const je = await lerJson(re)
        if (je?.estado === 'enviado') { marcar('enviar', 'ok', `para ${l.nome || l.telefone}: ${je.resultado || 'enviado'}`); return }
        if (je?.estado === 'falhou') { marcar('enviar', 'erro', `para ${l.nome || l.telefone}: ${je.resultado || 'não saiu'}`); return }
      }
      marcar('enviar', 'erro', 'a fila da Nay do WhatsApp ainda não mandou em 90 s: confira se o serviço nay-olx está no ar')
    } catch (e: any) {
      marcar('enviar', 'erro', `não consegui falar com o servidor: ${e?.message || e}`)
    }
  }

  const icone = (e: Estado) =>
    e === 'ok' ? <CheckCircle size={16} weight="fill" style={{ color: 'var(--wa-green)' }} />
    : e === 'erro' ? <WarningCircle size={16} weight="fill" className="text-red-500" />
    : e === 'andando' ? <CircleNotch size={16} className="animate-spin" style={{ color: 'var(--wa-text-2)' }} />
    : <MinusCircle size={16} style={{ color: 'var(--wa-text-2)', opacity: 0.5 }} />

  const entrada = 'w-full h-9 px-2.5 rounded-lg border bg-transparent text-[13px] outline-none'
  const estiloEntrada = { borderColor: 'var(--wa-divider)', color: 'var(--wa-text)' }
  const publicado = estado?.status === 'Disponível' && estado?.e_parceiro

  const conteudo = (
    <div className="flex flex-col h-full min-h-0" style={{ background: 'var(--wa-panel)', color: 'var(--wa-text)' }}>
      <div className="flex items-center gap-2 px-4 h-[60px] flex-shrink-0" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
        <button type="button" onClick={aoFechar} className="wa-icone-btn" title="Fechar o cadastro"><X size={20} /></button>
        <span className="text-[15px] font-semibold">Cadastrar imóvel</span>
      </div>
      <div className="flex-1 min-h-0 overflow-y-auto px-4 py-3 space-y-4">
        <div>
          <p className="text-[11px] font-semibold uppercase tracking-wide mb-1.5" style={{ color: 'var(--wa-text-2)' }}>Link do anúncio na OLX</p>
          <div className="flex gap-2">
            <input value={link} onChange={(e) => setLink(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void puxar() }}
                   placeholder="https://am.olx.com.br/…" className={entrada} style={estiloEntrada} aria-label="Link do anúncio na OLX" />
            <button type="button" onClick={() => void puxar()} disabled={!link.trim() || rodando} className="wa-botao-principal flex-shrink-0">
              {rodando && !codigo ? 'Puxando…' : 'Puxar'}
            </button>
          </div>
        </div>

        {/* A BARRA DO FUNCIONAMENTO: cada passo do sistema, com o que aconteceu ou o erro */}
        <ol className="space-y-1.5">
          {passos.map((p, n) => (
            <li key={p.chave} className="flex items-start gap-2">
              <span className="mt-[1px] flex-shrink-0">{icone(p.estado)}</span>
              <span className="min-w-0">
                <span className="block text-[13px]" style={{ opacity: p.estado === 'espera' ? 0.55 : 1 }}>{n + 1}. {p.rotulo}</span>
                {p.detalhe && (
                  <span className={`block text-[12px] leading-4 break-words ${p.estado === 'erro' ? 'text-red-500' : ''}`}
                        style={p.estado === 'erro' ? undefined : { color: 'var(--wa-text-2)' }}>{p.detalhe}</span>
                )}
              </span>
            </li>
          ))}
        </ol>

        {codigo && (
          <>
            {estado && (
              <div>
                <div className="flex items-center justify-between text-[12px] mb-1">
                  <span>Cadastro #{codigo}</span><span className="font-semibold">{estado.pct ?? 0}%</span>
                </div>
                <div className="h-2 rounded-full overflow-hidden" style={{ background: 'var(--wa-divider)' }}>
                  <div className="h-full" style={{ width: `${estado.pct ?? 0}%`, background: 'var(--wa-green)' }} />
                </div>
              </div>
            )}

            {fotos.length > 0 && (
              <div className="grid grid-cols-4 gap-1">
                {fotos.slice(0, 8).map((u) => <img key={u} src={u} alt="" className="w-full aspect-square object-cover rounded" loading="lazy" />)}
              </div>
            )}

            <div className="grid grid-cols-2 gap-2">
              {CAMPOS.map((c) => (
                <label key={c.chave} className="block">
                  <span className="block text-[11px] mb-0.5" style={{ color: 'var(--wa-text-2)' }}>{c.rotulo}</span>
                  <input value={campos[c.chave] ?? ''} inputMode={c.numero ? 'decimal' : undefined}
                         onChange={(e) => setCampos((x) => ({ ...x, [c.chave]: e.target.value }))}
                         className={entrada} style={estiloEntrada} />
                </label>
              ))}
            </div>

            {campos.condominio_nome && (
              <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
                Condomínio: <span style={{ color: 'var(--wa-text)' }}>{campos.condominio_nome}</span> (para trocar, edite o imóvel #{codigo} na aba Imóveis)
              </p>
            )}
            <label className="flex items-center gap-2 text-[12px]">
              <input type="checkbox" checked={donoEContato} onChange={(e) => setDonoEContato(e.target.checked)} />
              O contato desta conversa ({lead.title || lead.phone}) é o proprietário
            </label>

            <button type="button" onClick={() => void publicar()} disabled={rodando} className="wa-botao-principal w-full">
              {publicado ? 'Salvar de novo' : 'Publicar imóvel como disponível'}
            </button>
          </>
        )}

        {card && (
          <div>
            <p className="text-[11px] font-semibold uppercase tracking-wide mb-1.5" style={{ color: 'var(--wa-text-2)' }}>O card que vai ao lead</p>
            <p className="text-[12.5px] whitespace-pre-wrap rounded-lg p-2.5" style={{ background: 'var(--wa-row-selected)' }}>{card}</p>
            <p className="text-[11px] font-semibold uppercase tracking-wide mt-3 mb-1.5" style={{ color: 'var(--wa-text-2)' }}>Enviar a um lead (pelo 8595)</p>
            <div className="relative">
              <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome ou número do lead"
                     className={entrada} style={estiloEntrada} aria-label="Buscar o lead" />
              {leads.length > 0 && (
                <div className="absolute z-30 left-0 right-0 mt-1 rounded-lg border shadow-xl max-h-[220px] overflow-y-auto"
                     style={{ background: 'var(--wa-panel)', borderColor: 'var(--wa-divider)' }}>
                  {leads.map((l) => (
                    <button key={l.telefone} type="button" onClick={() => void enviar(l)}
                            className="w-full flex items-center justify-between gap-2 px-3 py-2 text-left text-[13px] hover:opacity-80"
                            style={{ borderBottom: '1px solid var(--wa-divider)' }}>
                      <span className="truncate">{l.nome || l.telefone}</span>
                      <PaperPlaneRight size={14} />
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )

  if (modo === 'gaveta') {
    return (
      <div className="fixed inset-0 z-50 flex justify-end">
        <div className="absolute inset-0 bg-black/40" onClick={aoFechar} />
        <div className="relative w-full max-w-[420px] h-full">{conteudo}</div>
      </div>
    )
  }
  return (
    <aside className="w-[360px] flex-shrink-0 h-full min-h-0" style={{ borderLeft: '1px solid var(--wa-divider)' }}>{conteudo}</aside>
  )
}
