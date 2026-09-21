'use client'

/**
 * Painel "Como enviar leads" — o que se manda pra quem vai configurar o envio do
 * outro lado.
 *
 * A URL do endpoint sai de window.location.origin em vez de vir de env: assim
 * ela está sempre certa em qualquer ambiente (local, preview, produção) sem
 * ninguém precisar lembrar de atualizar uma variável.
 */

import { useEffect, useMemo, useState } from 'react'
import { Copy, Check, Key, Trash } from '@phosphor-icons/react'
import type { LeadSourceTab } from './types'

interface ApiToken {
  id: string
  name: string
  lastUsedAt: string | null
  createdAt: string
}

/** Exemplo de corpo por fonte, com os nomes de campo exatos que a API espera. */
const EXAMPLES: Record<string, unknown> = {
  agenda_ascensao: {
    source: 'agenda_ascensao',
    id: 1234,
    nome: 'Maria Silva',
    whatsapp: '5511987654321',
    email: '',
    instagram: '@mariasilva',
    area: 'Empresário',
    aumento: 'R$10.000-R$25.000/mês',
    investimento: 'Até R$4.000',
    criado_em: '2026-09-07T14:32:00-03:00',
    agenda: {
      uid: 87,
      phase: 'done',
      a1: {
        bed: '23:30', wake: '06:30', ws: '09:00', we: '18:00',
        wdays: [0, 1, 2, 3, 4], commute: 25,
        meetAM: 60, meetPM: 90, meetEve: 0,
        bfT: '07:00', bfD: 30, lunchT: '12:30', lunchD: 60, dinT: '20:00', dinD: 45,
        train: true, trainDays: [0, 2, 4], trainT: '07:30', trainD: 60, trainCom: 10,
        ppl: true,
        pplWkDays: [3], pplWkT: '21:00', pplWkD: 60,
        pplWeDays: [5, 6], pplWeT: '15:00', pplWeD: 180,
        vazAM: 30, vazAMp: 'começo', vazPM: 45, vazPMp: 'fim',
      },
      real: [
        { id: 1, t: 'Dormir', s: 0, d: 390, c: 'sono', day: 0 },
        { id: 2, t: 'Treino', s: 450, d: 60, c: 'f3', day: 0 },
        { id: 3, t: 'Expediente', s: 540, d: 540, c: 'f1', day: 0 },
      ],
    },
  },
  site_evento: {
    source: 'site_evento',
    nome: 'João Souza',
    email: 'joao@exemplo.com',
    whatsapp: '5511912345678',
  },
}

function CopyButton({ value, label = 'Copiar' }: { value: string; label?: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <button
      type="button"
      onClick={async () => {
        await navigator.clipboard.writeText(value)
        setCopied(true)
        setTimeout(() => setCopied(false), 1800)
      }}
      className="btn btn-outline btn-sm flex-shrink-0"
    >
      {copied ? <Check size={14} weight="bold" /> : <Copy size={14} weight="bold" />}
      {copied ? 'Copiado' : label}
    </button>
  )
}

export default function ApiPanel({ sources, activeSource }: { sources: LeadSourceTab[]; activeSource: string }) {
  const [tokens, setTokens] = useState<ApiToken[]>([])
  const [newToken, setNewToken] = useState<string | null>(null)
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // origin só existe no cliente; no primeiro render (SSR) fica o placeholder.
  const [origin, setOrigin] = useState('')
  useEffect(() => setOrigin(window.location.origin), [])

  const base = origin || 'https://SEU-DOMINIO'
  const endpoint = `${base}/api/ingest/leads`
  // Variante com a fonte na URL — e a que se cola no plugin do WordPress, que
  // manda so os campos do formulario e nao consegue acrescentar um `source`.
  const webhookUrl = `${base}/api/ingest/leads/${activeSource}`

  const loadTokens = async () => {
    try {
      const res = await fetch('/api/tokens')
      if (!res.ok) return
      const json = await res.json()
      setTokens(json.data || [])
    } catch {
      /* lista de tokens é secundária — a tela funciona sem ela */
    }
  }
  useEffect(() => { loadTokens() }, [])

  const generate = async () => {
    setGenerating(true)
    setError(null)
    try {
      const res = await fetch('/api/tokens', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: 'Ingestão de leads' }),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Falha ao gerar a chave.')
      // O valor em claro vem só nesta resposta — o banco guarda só o hash.
      setNewToken(json.data?.token ?? null)
      await loadTokens()
    } catch (err: any) {
      setError(err.message || 'Falha ao gerar a chave.')
    } finally {
      setGenerating(false)
    }
  }

  const revoke = async (id: string) => {
    await fetch(`/api/tokens?id=${id}`, { method: 'DELETE' })
    await loadTokens()
  }

  const example = useMemo(
    () => JSON.stringify(EXAMPLES[activeSource] ?? EXAMPLES.site_evento, null, 2),
    [activeSource]
  )

  const curl = useMemo(
    () =>
      `curl -X POST ${webhookUrl} \\\n` +
      `  -H "Authorization: Bearer SUA_CHAVE" \\\n` +
      `  -H "Content-Type: application/json" \\\n` +
      `  -d '${JSON.stringify(EXAMPLES[activeSource] ?? EXAMPLES.site_evento)}'`,
    [webhookUrl, activeSource]
  )

  const activeDef = sources.find((s) => s.key === activeSource)

  return (
    <div className="glass rounded-2xl p-5 space-y-5">
      <div>
        <h2 className="text-sm font-semibold text-ink">Como enviar leads para esta aba</h2>
        <p className="text-xs text-muted mt-1">
          Duas formas de chamar o mesmo endpoint: com a fonte na URL (webhook) ou no
          corpo (API). Dai pra frente e o mesmo log e o mesmo funil.
        </p>
      </div>

      <Field
        label="Webhook — formulario do WordPress"
        hint="cole no campo Webhook URL do plugin"
      >
        <div className="flex items-center gap-2">
          <code className="glass-sunken rounded-lg px-3 py-2 text-xs text-ink flex-1 min-w-0 overflow-x-auto whitespace-nowrap">
            POST {webhookUrl}
          </code>
          <CopyButton value={webhookUrl} />
        </div>
        <p className="text-[11px] text-muted mt-1.5 leading-relaxed">
          A fonte vai na URL, entao o formulario so precisa mandar os campos. Aceita
          formulario (urlencoded/multipart) alem de JSON, e reconhece nomes de campo
          comuns — <code className="text-accent-2">your-name</code>,{' '}
          <code className="text-accent-2">telefone</code>,{' '}
          <code className="text-accent-2">celular</code>,{' '}
          <code className="text-accent-2">e-mail</code>. Se o plugin nao deixar mandar
          cabecalho, acrescente <code className="text-accent-2">?key=SUA_CHAVE</code> no
          fim da URL.
        </p>
      </Field>

      <Field label="API — sistema proprio" hint="a fonte vai no corpo, em source">
        <div className="flex items-center gap-2">
          <code className="glass-sunken rounded-lg px-3 py-2 text-xs text-ink flex-1 min-w-0 overflow-x-auto whitespace-nowrap">
            POST {endpoint}
          </code>
          <CopyButton value={endpoint} />
        </div>
      </Field>

      <Field label="Autenticação">
        <code className="glass-sunken rounded-lg px-3 py-2 text-xs text-ink block overflow-x-auto whitespace-nowrap">
          Authorization: Bearer SUA_CHAVE
        </code>
      </Field>

      <Field label="Chave de API">
        {newToken && (
          <div className="glass-accent glass rounded-xl p-3 mb-3">
            <p className="text-[11px] text-accent-2 font-semibold mb-2">
              Copie agora — esta chave não pode ser vista de novo.
            </p>
            <div className="flex items-center gap-2">
              <code className="glass-sunken rounded-lg px-3 py-2 text-xs text-ink flex-1 min-w-0 overflow-x-auto whitespace-nowrap">
                {newToken}
              </code>
              <CopyButton value={newToken} />
            </div>
          </div>
        )}

        {error && <p className="text-xs text-red-400 mb-2">{error}</p>}

        <div className="flex items-center gap-2 mb-3">
          <button onClick={generate} disabled={generating} className="btn btn-primary btn-sm">
            <Key size={14} weight="bold" />
            {generating ? 'Gerando…' : 'Gerar nova chave'}
          </button>
        </div>

        {tokens.length > 0 && (
          <ul className="panel rounded-xl divide-y divide-white/5">
            {tokens.map((token) => (
              <li key={token.id} className="flex items-center gap-3 px-3.5 py-2.5">
                <div className="min-w-0 flex-1">
                  <p className="text-xs text-ink truncate">{token.name}</p>
                  <p className="text-[10px] text-muted">
                    Criada em {new Date(token.createdAt).toLocaleDateString('pt-BR')}
                    {token.lastUsedAt
                      ? ` · usada por último em ${new Date(token.lastUsedAt).toLocaleString('pt-BR')}`
                      : ' · nunca usada'}
                  </p>
                </div>
                <button
                  onClick={() => revoke(token.id)}
                  className="btn-icon w-8 h-8 flex-shrink-0 hover:!text-red-400"
                  title="Revogar chave"
                >
                  <Trash size={14} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </Field>

      <Field
        label={`Corpo da requisição — ${activeDef?.label ?? activeSource}`}
        hint={
          activeDef?.required.length
            ? `Obrigatórios: ${activeDef.required.join(', ')}`
            : undefined
        }
      >
        <div className="relative">
          <pre className="glass-sunken rounded-xl p-3.5 text-[11px] text-ink overflow-x-auto leading-relaxed">
            {example}
          </pre>
          <div className="absolute top-2.5 right-2.5">
            <CopyButton value={example} label="Copiar JSON" />
          </div>
        </div>
      </Field>

      <Field label="Exemplo pronto (curl)">
        <div className="relative">
          <pre className="glass-sunken rounded-xl p-3.5 text-[11px] text-muted overflow-x-auto leading-relaxed">
            {curl}
          </pre>
          <div className="absolute top-2.5 right-2.5">
            <CopyButton value={curl} label="Copiar" />
          </div>
        </div>
      </Field>

      <p className="text-[11px] text-muted leading-relaxed">
        Respostas: <span className="text-ink">201</span> com o id do registro ·{' '}
        <span className="text-ink">400</span> com a lista de campos que faltaram ou fonte
        inválida · <span className="text-ink">401</span> chave ausente, inválida ou revogada.
        Reenviar o mesmo lead{' '}
        {activeSource === 'agenda_ascensao' ? (
          <>(mesmo <code className="text-accent-2">id</code>)</>
        ) : (
          <>(mesmo <code className="text-accent-2">whatsapp</code>)</>
        )}{' '}
        atualiza a linha em vez de duplicar.
      </p>
    </div>
  )
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-[11px] font-bold uppercase tracking-wider text-muted mb-2">
        {label}
        {hint && <span className="ml-2 font-medium normal-case tracking-normal text-muted/70">{hint}</span>}
      </p>
      {children}
    </div>
  )
}
