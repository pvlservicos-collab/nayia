'use client'

/**
 * Cadastro de lead à mão (Tel, 26/09/2026: "cria la no pipeline uma aba
 * adicionar lead manualmente").
 *
 * É outro cadastro, não o `NovoLeadManualModal`: aquele era do projeto
 * anterior e pedia "fonte" entre agenda_ascensao, site_evento e indicação --
 * nada que exista aqui. Este pede o que a Imob Easy usa: nome, telefone, por
 * qual dos dois números a conversa vai acontecer, e em que etapa ele entra.
 *
 * A LINHA É OBRIGATÓRIA de propósito. Sem ela o lead não aparece em nenhuma
 * das duas abas do chat (elas filtram pelo tipo da integração), e a pessoa
 * cadastraria alguém que some da tela no mesmo instante.
 */
import { useEffect, useState } from 'react'
import { X } from '@phosphor-icons/react'

interface Integracao {
  id: string
  name: string
  type: string
}

interface Etapa {
  id: string
  name: string
}

interface Props {
  etapas: Etapa[]
  onClose: () => void
  onCriado: (lead: any) => void
}

/** O rótulo que a pessoa entende, por tipo de integração. */
const NOME_DA_LINHA: Record<string, string> = {
  whatsapp_zapi: 'WhatsApp Parceria · (92) 9445-3618',
  whatsapp_zapi_captacao: 'WhatsApp Captação (Z-API)',
  whatsapp_cloud_official: 'WhatsApp API oficial · (92) 8456-0874',
}

export default function NovoLeadImobEasy({ etapas, onClose, onCriado }: Props) {
  const [integracoes, setIntegracoes] = useState<Integracao[]>([])
  const [form, setForm] = useState({ nome: '', telefone: '', integracao: '', etapa: '' })
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  useEffect(() => {
    fetch('/api/integrations')
      .then((r) => r.json())
      .then((j) => {
        const lista: Integracao[] = (j?.data || []).filter((i: Integracao) =>
          i.type === 'whatsapp_zapi' || i.type === 'whatsapp_zapi_captacao' || i.type === 'whatsapp_cloud_official')
        setIntegracoes(lista)
        if (lista.length && !form.integracao) {
          setForm((f) => ({ ...f, integracao: lista[0].id }))
        }
      })
      .catch(() => setIntegracoes([]))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  /** Só dígitos, com o 55 na frente — é o formato que o resto do CRM usa. */
  function telefoneLimpo(bruto: string) {
    const d = bruto.replace(/\D/g, '')
    if (!d) return ''
    return d.startsWith('55') ? d : '55' + d
  }

  async function salvar(e: React.FormEvent) {
    e.preventDefault()
    setErro(null)

    const nome = form.nome.trim()
    const fone = telefoneLimpo(form.telefone)
    if (!nome) return setErro('Diga o nome do lead.')
    if (fone.length < 12) return setErro('O telefone parece incompleto — use DDD + número.')
    if (!form.integracao) return setErro('Escolha por qual número a conversa vai acontecer.')

    setSalvando(true)
    try {
      const res = await fetch('/api/leads', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: nome,
          phone: fone,
          source: 'manual',
          integration_id: form.integracao,
          stage_id: form.etapa || undefined,
        }),
      })
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'não consegui salvar')
      // `existed` = já havia alguém com esse telefone. Abrir o que existe é
      // melhor que criar um segundo e partir a conversa em dois lugares.
      onCriado(j.data)
      onClose()
    } catch (e: any) {
      setErro(e?.message || 'não consegui salvar')
    } finally {
      setSalvando(false)
    }
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60"
         onClick={onClose}>
      <form
        onClick={(e) => e.stopPropagation()}
        onSubmit={salvar}
        className="w-full max-w-sm bg-panel border border-line rounded-2xl p-5 space-y-3"
      >
        <div className="flex items-center justify-between">
          <h2 className="text-base font-bold text-ink">Adicionar lead</h2>
          <button type="button" onClick={onClose} className="text-muted hover:text-ink">
            <X size={18} />
          </button>
        </div>

        {erro && (
          <div className="bg-red-500/10 border border-red-500/30 text-red-400 text-xs rounded-lg px-3 py-2">
            {erro}
          </div>
        )}

        <label className="block">
          <span className="block text-xs text-muted mb-1">Nome</span>
          <input
            value={form.nome}
            onChange={(e) => setForm({ ...form, nome: e.target.value })}
            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
            placeholder="Como você chama essa pessoa"
            autoFocus
          />
        </label>

        <label className="block">
          <span className="block text-xs text-muted mb-1">WhatsApp</span>
          <input
            value={form.telefone}
            onChange={(e) => setForm({ ...form, telefone: e.target.value })}
            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
            placeholder="(92) 99999-9999"
            inputMode="tel"
          />
        </label>

        <label className="block">
          <span className="block text-xs text-muted mb-1">Conversa por qual número</span>
          <select
            value={form.integracao}
            onChange={(e) => setForm({ ...form, integracao: e.target.value })}
            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
          >
            {integracoes.length === 0 && <option value="">(nenhum número configurado)</option>}
            {integracoes.map((i) => (
              <option key={i.id} value={i.id}>{NOME_DA_LINHA[i.type] || i.name}</option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="block text-xs text-muted mb-1">Etapa</span>
          <select
            value={form.etapa}
            onChange={(e) => setForm({ ...form, etapa: e.target.value })}
            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
          >
            <option value="">(a primeira da lista)</option>
            {etapas.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>

        <button
          type="submit"
          disabled={salvando}
          className="w-full bg-accent text-black font-bold py-2.5 rounded-lg text-sm disabled:opacity-50"
        >
          {salvando ? 'Salvando...' : 'Adicionar'}
        </button>
      </form>
    </div>
  )
}
