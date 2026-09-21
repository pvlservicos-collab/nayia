'use client'

/**
 * Tela da integração Z-API — o número dos disparos e da automação.
 *
 * Três passos, na ordem em que precisam acontecer: credenciais → webhooks →
 * conectar o número. A ordem importa e por isso a tela não é um formulário só:
 * sem credencial não dá pra falar com a instância, e sem webhook a instância
 * conecta mas nenhuma mensagem chega no CRM — que é a falha mais difícil de
 * perceber, porque o WhatsApp funciona normalmente no celular.
 */

import Link from 'next/link'
import { useCallback, useEffect, useState } from 'react'
import {
  ArrowLeft, CheckCircle, Warning, DeviceMobile, Copy, ArrowsClockwise,
  ChatsCircle, Lightning,
} from '@phosphor-icons/react'
import { useAuth } from '@/hooks'

interface EstadoIntegracao {
  id: string
  status: string
  instance_id: string | null
  tem_instance_token: boolean
  tem_client_token: boolean
  instancia: { connected: boolean; smartphoneConnected?: boolean; error?: string | null } | null
  instancia_erro: string | null
  aviso_resposta_grupo: string | null
  grupos: { id: string; nome: string | null }[]
}

export default function ZapiPage() {
  const { organizationId } = useAuth()

  const [estado, setEstado] = useState<EstadoIntegracao | null>(null)
  const [carregando, setCarregando] = useState(true)
  const [form, setForm] = useState({ instance_id: '', instance_token: '', client_token: '' })
  const [salvando, setSalvando] = useState(false)
  const [qrcode, setQrcode] = useState<string | null>(null)
  const [mensagem, setMensagem] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null)
  const [importando, setImportando] = useState(false)

  const webhookUrl = organizationId
    ? `${typeof window !== 'undefined' ? window.location.origin : ''}/api/webhooks/zapi?org_id=${organizationId}`
    : ''

  const carregar = useCallback(async () => {
    setCarregando(true)
    try {
      const res = await fetch('/api/integrations/zapi')
      const data = await res.json()
      setEstado(data)
      if (data?.instance_id) setForm((f) => ({ ...f, instance_id: data.instance_id }))
    } catch {
      setEstado(null)
    } finally {
      setCarregando(false)
    }
  }, [])

  useEffect(() => { carregar() }, [carregar])

  const avisar = (tipo: 'ok' | 'erro', texto: string) => {
    setMensagem({ tipo, texto })
    setTimeout(() => setMensagem(null), 6000)
  }

  async function salvarCredenciais(e: React.FormEvent) {
    e.preventDefault()
    setSalvando(true)
    try {
      const res = await fetch('/api/integrations/zapi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data?.error || 'Falha ao salvar.')
      avisar('ok', 'Credenciais salvas.')
      setForm((f) => ({ ...f, instance_token: '', client_token: '' }))
      await carregar()
    } catch (err: any) {
      avisar('erro', err.message)
    } finally {
      setSalvando(false)
    }
  }

  async function definirAviso(grupo: string | null) {
    try {
      const res = await fetch('/api/integrations/zapi', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ acao: 'aviso', grupo }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data?.error || 'Falha ao salvar o aviso.')
      avisar('ok', grupo ? 'Aviso ligado.' : 'Aviso desligado.')
      await carregar()
    } catch (err: any) {
      avisar('erro', err.message)
    }
  }

  async function acao(nome: 'qrcode' | 'webhooks' | 'desconectar') {
    try {
      const res = await fetch('/api/integrations/zapi', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ acao: nome, url: webhookUrl }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data?.error || 'Falha na ação.')

      if (nome === 'qrcode') {
        setQrcode(data.qrcode)
        if (!data.qrcode) avisar('ok', 'A instância já está conectada — não há QR code para ler.')
      }
      if (nome === 'webhooks') avisar('ok', 'Webhooks apontados para este CRM.')
      if (nome === 'desconectar') { setQrcode(null); avisar('ok', 'Instância desconectada.'); }
      await carregar()
    } catch (err: any) {
      avisar('erro', err.message)
    }
  }

  /**
   * Importa as conversas em páginas até acabar.
   *
   * O laço fica no navegador porque cada invocação da Vercel tem teto de tempo —
   * mesmo caminho da ressincronização da Agenda.
   */
  async function importarConversas() {
    setImportando(true)
    let pagina = 1
    let criados = 0
    let existentes = 0
    try {
      for (let volta = 0; volta < 40; volta++) {
        const res = await fetch('/api/integrations/zapi/chats', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ pagina }),
        })
        const data = await res.json()
        if (!res.ok) throw new Error(data?.error || 'Falha ao importar conversas.')
        criados += data.criados
        existentes += data.existentes
        if (data.fim || !data.proxima_pagina) break
        pagina = data.proxima_pagina
      }
      avisar('ok', `${criados} conversa(s) importada(s); ${existentes} já existiam no CRM.`)
    } catch (err: any) {
      avisar('erro', err.message)
    } finally {
      setImportando(false)
    }
  }

  const conectado = estado?.instancia?.connected === true
  // Client-Token não entra: é opcional (ver o passo 1), e exigi-lo aqui
  // travaria os botões de quem tem uma conta sem a trava de segurança ligada.
  const temCredenciais = !!estado?.tem_instance_token

  return (
    <div className="p-4 sm:p-8 max-w-5xl mx-auto">
      <div className="flex items-center gap-4 mb-8">
        <Link href="/settings/integrations" className="p-2 -ml-2 hover:bg-panel-2 rounded-full transition-colors text-muted">
          <ArrowLeft size={20} />
        </Link>
        <div>
          <h1 className="text-2xl font-bold text-ink">WhatsApp — Z-API (disparos e automação)</h1>
          <p className="text-muted text-sm mt-1">
            É por este número que o funil e todo disparo automático saem.
          </p>
        </div>
      </div>

      {mensagem && (
        <div className={`mb-6 rounded-lg px-4 py-3 text-sm border ${
          mensagem.tipo === 'ok'
            ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400'
            : 'bg-red-500/10 border-red-500/30 text-red-400'
        }`}>
          {mensagem.texto}
        </div>
      )}

      {/* Estado atual */}
      <div className="bg-panel border rounded-xl p-6 mb-6 flex items-center gap-4">
        {carregando ? (
          <div className="w-10 h-10 border-4 border-line border-t-accent rounded-full animate-spin" />
        ) : conectado ? (
          <CheckCircle size={40} weight="fill" className="text-emerald-500 flex-shrink-0" />
        ) : (
          <Warning size={40} weight="fill" className="text-yellow-500 flex-shrink-0" />
        )}
        <div className="min-w-0">
          <p className="font-bold text-ink">
            {carregando ? 'Verificando…' : conectado ? 'Número conectado' : 'Número não conectado'}
          </p>
          <p className="text-sm text-muted">
            {estado?.instancia_erro
              ? estado.instancia_erro
              : conectado
                ? 'Disparos e automação estão saindo por aqui.'
                : temCredenciais
                  ? 'Credenciais salvas. Falta ler o QR code com o celular.'
                  : 'Preencha as credenciais da instância abaixo.'}
          </p>
        </div>
        <button onClick={carregar} className="btn btn-outline btn-sm ml-auto flex-shrink-0">
          <ArrowsClockwise size={14} /> Atualizar
        </button>
      </div>

      {/* Passo 1 — credenciais */}
      <form onSubmit={salvarCredenciais} className="bg-panel border rounded-xl p-6 mb-6">
        <h2 className="font-bold text-ink mb-1">1. Credenciais da instância</h2>
        <p className="text-sm text-muted mb-4">
          Estão no painel da Z-API. O <strong>Client-Token</strong> é opcional: só precisa
          se a sua conta tiver a trava de segurança ligada (Admin → Segurança). Se as
          chamadas começarem a voltar 403, é ele que está faltando.
        </p>

        <div className="grid gap-4 sm:grid-cols-3">
          <label className="block">
            <span className="text-[11px] font-bold uppercase tracking-wider text-muted">ID da instância</span>
            <input
              value={form.instance_id}
              onChange={(e) => setForm({ ...form, instance_id: e.target.value })}
              className="field mt-1"
              placeholder="3D9A..."
            />
          </label>
          <label className="block">
            <span className="text-[11px] font-bold uppercase tracking-wider text-muted">Token da instância</span>
            <input
              type="password"
              value={form.instance_token}
              onChange={(e) => setForm({ ...form, instance_token: e.target.value })}
              className="field mt-1"
              placeholder={estado?.tem_instance_token ? '•••••••• (salvo)' : ''}
            />
          </label>
          <label className="block">
            <span className="text-[11px] font-bold uppercase tracking-wider text-muted">
              Client-Token <span className="normal-case font-medium text-muted/70">(opcional)</span>
            </span>
            <input
              type="password"
              value={form.client_token}
              onChange={(e) => setForm({ ...form, client_token: e.target.value })}
              className="field mt-1"
              placeholder={estado?.tem_client_token ? '•••••••• (salvo)' : ''}
            />
          </label>
        </div>

        <button
          type="submit"
          disabled={salvando || !form.instance_id || !form.instance_token}
          className="btn btn-primary btn-sm mt-4 disabled:opacity-40"
        >
          {salvando ? 'Salvando…' : 'Salvar credenciais'}
        </button>
      </form>

      {/* Passo 2 — webhooks */}
      <div className="bg-panel border rounded-xl p-6 mb-6">
        <h2 className="font-bold text-ink mb-1">2. Webhooks</h2>
        <p className="text-sm text-muted mb-4">
          É o que faz as mensagens aparecerem no chat. O botão aponta os quatro webhooks da
          Z-API (recebida, status, conectado, desconectado) para este endereço de uma vez.
        </p>
        <div className="flex items-center gap-2 mb-4">
          <code className="flex-1 text-xs bg-void border rounded-lg px-3 py-2 text-muted break-all">
            {webhookUrl || '—'}
          </code>
          <button
            onClick={() => navigator.clipboard.writeText(webhookUrl)}
            className="btn btn-outline btn-sm flex-shrink-0"
            title="Copiar"
          >
            <Copy size={14} />
          </button>
        </div>
        <button onClick={() => acao('webhooks')} disabled={!temCredenciais} className="btn btn-primary btn-sm disabled:opacity-40">
          <Lightning size={14} weight="bold" /> Apontar webhooks para este CRM
        </button>
      </div>

      {/* Passo 3 — conectar */}
      <div className="bg-panel border rounded-xl p-6 mb-6">
        <h2 className="font-bold text-ink mb-1">3. Conectar o número</h2>
        <p className="text-sm text-muted mb-4">
          No celular: WhatsApp → Aparelhos conectados → Conectar um aparelho.
        </p>

        {qrcode && (
          <img src={qrcode} alt="QR code da Z-API" className="w-56 h-56 rounded-lg border mb-4 bg-white" />
        )}

        <div className="flex flex-wrap gap-2">
          <button onClick={() => acao('qrcode')} disabled={!temCredenciais} className="btn btn-primary btn-sm disabled:opacity-40">
            <DeviceMobile size={14} weight="bold" /> Gerar QR code
          </button>
          {conectado && (
            <button onClick={() => acao('desconectar')} className="btn btn-outline btn-sm">
              Desconectar
            </button>
          )}
        </div>
      </div>

      {/* Aviso no grupo quando o lead responde a automação */}
      <div className="bg-panel border rounded-xl p-6 mb-6">
        <h2 className="font-bold text-ink mb-1">Avisar no grupo quando o lead responder a mensagem automática</h2>
        <p className="text-sm text-muted mb-4">
          Toda vez que um lead responder a mensagem do funil, sai um recado no grupo escolhido
          com o nome, o telefone, a fonte, o que ele escreveu e o link da conversa no CRM.
        </p>
        <select
          value={estado?.aviso_resposta_grupo || ''}
          onChange={(e) => definirAviso(e.target.value || null)}
          disabled={!temCredenciais}
          className="field max-w-sm disabled:opacity-40"
        >
          <option value="">Desligado</option>
          {(estado?.grupos || []).map((g) => (
            <option key={g.id} value={g.id}>{g.nome || g.id}</option>
          ))}
        </select>
        {estado && estado.grupos?.length === 0 && (
          <p className="text-xs text-muted mt-2">
            Nenhum grupo importado ainda — o aviso só pode ir para um grupo que exista no CRM.
          </p>
        )}
      </div>

      {/* Importar conversas */}
      <div className="bg-panel border rounded-xl p-6">
        <h2 className="font-bold text-ink mb-1">Importar conversas existentes</h2>
        <p className="text-sm text-muted mb-4">
          Cria um lead para cada conversa que já existe no aparelho — nome e telefone.
          <strong className="text-ink"> As mensagens antigas não vêm</strong>: a Z-API não guarda
          histórico e não tem endpoint para buscá-lo. A conversa no CRM começa a partir das
          mensagens que chegarem daqui pra frente. Grupos são ignorados.
        </p>
        <button onClick={importarConversas} disabled={!conectado || importando} className="btn btn-outline btn-sm disabled:opacity-40">
          <ChatsCircle size={14} weight="bold" />
          {importando ? 'Importando…' : 'Importar conversas'}
        </button>
      </div>
    </div>
  )
}
