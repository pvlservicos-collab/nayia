'use client'

/**
 * /settings/ia — prompt e configuração da IA.
 *
 * A tela existe pra o prompt ser escrito e revisado com calma. **Nada no app
 * executa isto ainda**: hoje não há nenhuma chamada a provedor de LLM no
 * projeto, e os botões de IA do chat só disparam webhook pra um sistema externo.
 * O aviso no topo diz isso na cara, pra ninguém achar que ligar o botão faz a
 * IA começar a responder cliente.
 */

import { useEffect, useState } from 'react'
import { Robot, FloppyDisk, CheckCircle, Warning } from '@phosphor-icons/react'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

interface AiSettings {
  enabled: boolean
  model: string
  system_prompt: string
  guardrails: string
  updated_at: string | null
  conectado: boolean
  modelos: string[]
}

/** Rótulo e custo por milhão de tokens, pra escolha informada. */
const MODELOS: Record<string, { nome: string; nota: string }> = {
  'claude-opus-5': { nome: 'Claude Opus 5', nota: 'mais capaz — US$ 5 entrada / US$ 25 saída por 1M tokens' },
  'claude-sonnet-5': { nome: 'Claude Sonnet 5', nota: 'equilibrado — US$ 2 / US$ 10 por 1M tokens' },
  'claude-haiku-4-5': { nome: 'Claude Haiku 4.5', nota: 'mais barato e rápido — US$ 1 / US$ 5 por 1M tokens' },
}

const EXEMPLO_PROMPT = `Você é o atendente do TitaCRM, falando por WhatsApp com quem acabou de se cadastrar na Agenda em Ascensão ou no Evento Ascensão.

Seu objetivo é entender o momento da pessoa e marcar uma conversa com o time.

Como falar:
- Português do Brasil, direto e sem formalidade exagerada
- Mensagens curtas, no máximo 3 linhas
- Uma pergunta por vez

O que você sabe sobre a pessoa: nome, de qual fonte veio e, quando for da Agenda, as respostas do quiz (rotina, faróis, onde perde tempo).`

const EXEMPLO_GUARDRAILS = `- Nunca invente preço, data de evento ou condição de pagamento
- Nunca prometa resultado financeiro
- Se a pessoa pedir para falar com humano, encerre e passe adiante na hora
- Se não souber, diga que vai confirmar com o time
- Nunca peça CPF, cartão ou senha`

export default function IaSettingsPage() {
  const [settings, setSettings] = useState<AiSettings | null>(null)
  const [carregando, setCarregando] = useState(true)
  const [salvando, setSalvando] = useState(false)
  const [salvo, setSalvo] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  useEffect(() => {
    let cancelado = false
    fetch('/api/ai-settings')
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (!cancelado && j?.data) setSettings(j.data) })
      .catch(() => { if (!cancelado) setErro('Não foi possível carregar a configuração.') })
      .finally(() => { if (!cancelado) setCarregando(false) })
    return () => { cancelado = true }
  }, [])

  const salvar = async () => {
    if (!settings) return
    setSalvando(true)
    setErro(null)
    try {
      const res = await fetch('/api/ai-settings', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          enabled: settings.enabled,
          model: settings.model,
          system_prompt: settings.system_prompt,
          guardrails: settings.guardrails,
        }),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Falha ao salvar.')
      setSettings(json.data)
      setSalvo(true)
      setTimeout(() => setSalvo(false), 2500)
    } catch (e: any) {
      setErro(e.message || 'Falha ao salvar.')
    } finally {
      setSalvando(false)
    }
  }

  const set = <K extends keyof AiSettings>(campo: K, valor: AiSettings[K]) =>
    setSettings((s) => (s ? { ...s, [campo]: valor } : s))

  if (carregando) {
    return (
      <div className="flex items-center justify-center py-24">
        <LoadingSpinner text="Carregando…" size="lg" />
      </div>
    )
  }

  if (!settings) {
    return (
      <div className="glass rounded-2xl px-6 py-12 text-center">
        <p className="text-sm text-red-300">{erro || 'Configuração indisponível.'}</p>
      </div>
    )
  }

  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <h1 className="text-2xl font-bold text-ink">Inteligência Artificial</h1>
        <p className="text-sm text-muted mt-1">
          O prompt que a IA vai seguir ao falar com seus leads.
        </p>
      </div>

      {/* O aviso mais importante da tela: nada disto roda ainda. */}
      <div className="glass rounded-2xl border-amber-500/30 p-4 flex gap-3">
        <Warning size={20} weight="fill" className="text-amber-400 flex-shrink-0 mt-0.5" />
        <div className="text-xs text-muted leading-relaxed">
          <p className="text-ink font-semibold mb-1">Ainda não está conectada</p>
          <p>
            Não existe nenhuma IA ligada ao sistema hoje. Esta tela guarda a
            configuração para quando ela for conectada — ligar a chave abaixo{' '}
            <span className="text-ink">não faz a IA começar a responder</span>.
          </p>
          <p className="mt-2">
            Os botões "Pausar IA" e "Sugerir próximos passos" que aparecem no chat
            disparam um webhook para um sistema externo (n8n ou similar); quem
            responde é aquele sistema, não este.
          </p>
        </div>
      </div>

      {/* Chave mestra */}
      <div className="glass rounded-2xl p-5">
        <label className="flex items-start gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={settings.enabled}
            onChange={(e) => set('enabled', e.target.checked)}
            className="mt-0.5 w-4 h-4 accent-[var(--blue)] flex-shrink-0"
          />
          <span>
            <span className="flex items-center gap-2 text-sm font-semibold text-ink">
              <Robot size={16} weight="fill" className={settings.enabled ? 'text-accent-2' : 'text-muted'} />
              Ativar a IA no atendimento
            </span>
            <span className="block text-xs text-muted mt-1">
              Desligada por padrão. Deixe assim até revisar o prompt e conectar o
              provedor — com ela ligada, a IA responde no lugar de uma pessoa.
            </span>
          </span>
        </label>
      </div>

      {/* Modelo */}
      <div className="glass rounded-2xl p-5">
        <p className="text-[11px] font-bold uppercase tracking-wider text-muted mb-3">Modelo</p>
        <div className="space-y-2">
          {settings.modelos.map((id) => {
            const meta = MODELOS[id]
            return (
              <label
                key={id}
                className={`flex items-start gap-3 rounded-xl px-3.5 py-3 border cursor-pointer transition-colors ${
                  settings.model === id
                    ? 'border-accent/40 bg-accent/[0.07]'
                    : 'border-white/[0.07] hover:bg-white/[0.04]'
                }`}
              >
                <input
                  type="radio"
                  name="modelo"
                  checked={settings.model === id}
                  onChange={() => set('model', id)}
                  className="mt-0.5 accent-[var(--blue)] flex-shrink-0"
                />
                <span className="min-w-0">
                  <span className="block text-sm text-ink">{meta?.nome ?? id}</span>
                  <span className="block text-[11px] text-muted">{meta?.nota}</span>
                  <code className="block text-[10px] text-muted/70 mt-0.5">{id}</code>
                </span>
              </label>
            )
          })}
        </div>
      </div>

      {/* Prompt */}
      <div className="glass rounded-2xl p-5">
        <div className="flex items-center justify-between mb-2">
          <p className="text-[11px] font-bold uppercase tracking-wider text-muted">
            Prompt — quem a IA é e como fala
          </p>
          {!settings.system_prompt && (
            <button
              onClick={() => set('system_prompt', EXEMPLO_PROMPT)}
              className="btn btn-outline btn-sm"
            >
              Usar exemplo
            </button>
          )}
        </div>
        <textarea
          value={settings.system_prompt}
          onChange={(e) => set('system_prompt', e.target.value)}
          rows={14}
          placeholder="Descreva quem a IA é, o objetivo da conversa e como ela deve falar…"
          className="field !py-3 font-mono !text-[12px] leading-relaxed resize-y"
        />
        <p className="text-[11px] text-muted mt-2">
          {settings.system_prompt.length} caracteres. Seja concreto sobre o
          objetivo da conversa — é o que mais muda o comportamento.
        </p>
      </div>

      {/* Guardrails */}
      <div className="glass rounded-2xl p-5">
        <div className="flex items-center justify-between mb-2">
          <p className="text-[11px] font-bold uppercase tracking-wider text-muted">
            Regras que ela nunca pode quebrar
          </p>
          {!settings.guardrails && (
            <button
              onClick={() => set('guardrails', EXEMPLO_GUARDRAILS)}
              className="btn btn-outline btn-sm"
            >
              Usar exemplo
            </button>
          )}
        </div>
        <textarea
          value={settings.guardrails}
          onChange={(e) => set('guardrails', e.target.value)}
          rows={8}
          placeholder="Uma regra por linha…"
          className="field !py-3 font-mono !text-[12px] leading-relaxed resize-y"
        />
        <p className="text-[11px] text-muted mt-2">
          Separado do prompt de propósito: dá pra revisar o que é proibido sem
          reler o texto inteiro.
        </p>
      </div>

      {erro && (
        <div className="glass rounded-xl border-red-500/30 px-4 py-3">
          <p className="text-sm text-red-300">{erro}</p>
        </div>
      )}

      <div className="flex items-center gap-3">
        <button onClick={salvar} disabled={salvando} className="btn btn-primary">
          <FloppyDisk size={16} weight="bold" />
          {salvando ? 'Salvando…' : 'Salvar'}
        </button>
        {salvo && (
          <span className="flex items-center gap-1.5 text-xs text-emerald-400">
            <CheckCircle size={15} weight="fill" />
            Salvo
          </span>
        )}
        {settings.updated_at && !salvo && (
          <span className="text-[11px] text-muted">
            Última alteração em {new Date(settings.updated_at).toLocaleString('pt-BR')}
          </span>
        )}
      </div>
    </div>
  )
}
