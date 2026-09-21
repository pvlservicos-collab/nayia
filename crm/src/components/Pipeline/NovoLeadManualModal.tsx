'use client'

/**
 * Cadastro manual de lead — serve as três fontes do Pipeline.
 *
 * É o jeito de um lead entrar no CRM digitado por gente. Nasceu pra "Indicação",
 * mas Agenda e site também precisam: a pessoa manda os dados por mensagem, ou o
 * formulário dela falhou, e alguém do time registra na hora sem sair do Kanban.
 *
 * A fonte muda o rótulo, um campo ou outro e — o que mais importa — se a
 * mensagem automática daquela fonte sai ou não (Agenda e site têm funil;
 * Indicação não tem). Quem cadastra decide na hora, no interruptor do rodapé.
 *
 * Manda pra POST /api/ingest/leads/<fonte> — a MESMA porta de entrada das
 * fontes externas, e não um endpoint próprio. Assim o lead digitado passa pela
 * mesma normalização de telefone (o DDI 55 que a Cloud API exige), o mesmo
 * dedupe e o mesmo registro em lead_source_submissions que os outros. Um
 * caminho separado teria dado, mais cedo ou mais tarde, um lead que existe na
 * lista mas não recebe mensagem. A rota aceita a sessão do navegador
 * (src/lib/api-auth.ts), então não há chave de API envolvida aqui.
 */

import { useMemo, useState } from 'react'
import { X, UserPlus, Plus, Trash } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { camposAdicionaveis, LEAD_SOURCES, type LeadSourceKey } from '@/lib/leadSources'

/** Fontes com funil de atendimento — só nelas a mensagem automática existe. */
const FONTES_COM_AUTOMACAO: LeadSourceKey[] = ['agenda_ascensao', 'site_evento']

interface Props {
  /** Em qual fonte o lead entra: muda o rótulo, os campos e o funil. */
  source: LeadSourceKey
  onClose: () => void
  /** Chamado depois de gravar, pra lista do Kanban recarregar. */
  onCreated: () => void
}

export default function NovoLeadManualModal({ source, onClose, onCreated }: Props) {
  const { profileName } = useAuth()
  const fonte = LEAD_SOURCES[source]
  const ehIndicacao = source === 'indicacao'
  const temAutomacao = FONTES_COM_AUTOMACAO.includes(source)
  // Ligado por padrão: cadastrar um lead de Agenda/site à mão é registrar quem
  // acabou de se inscrever, e o normal é ele receber a mesma mensagem de quem
  // entrou pelo formulário. Quem está só arrumando um cadastro antigo desliga.
  const [enviarAutomacao, setEnviarAutomacao] = useState(true)
  const [form, setForm] = useState({
    nome: '',
    whatsapp: '',
    instagram: '',
    email: '',
    indicado_por: '',
    observacao: '',
  })
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  /**
   * Campos que a pessoa acrescentou à mão.
   *
   * O catálogo sai das outras fontes (camposAdicionaveis), então o que for
   * digitado aqui cai na MESMA chave que a Agenda e o site usam — "Área de
   * atuação" digitada vira `area`, igual à do quiz. Se fosse lista própria,
   * daria dois campos com o mesmo nome e conteúdos que nunca se encontram.
   */
  const [extras, setExtras] = useState<
    { key: string; label: string; valor: string; fontesTexto: string }[]
  >([])
  const [listaAberta, setListaAberta] = useState(false)

  const disponiveis = useMemo(
    () => camposAdicionaveis(extras.map((c) => c.key)),
    [extras]
  )

  const set = (campo: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setForm((atual) => ({ ...atual, [campo]: e.target.value }))

  // 10 dígitos = fixo com DDD; 11 = celular. Menos que isso não dá pra falar
  // com a pessoa, e é melhor barrar aqui do que gravar um lead inalcançável.
  const digitos = form.whatsapp.replace(/\D/g, '')
  const podeSalvar = form.nome.trim().length > 1 && digitos.length >= 10 && !salvando

  async function salvar(e: React.FormEvent) {
    e.preventDefault()
    if (!podeSalvar) return
    setSalvando(true)
    setErro(null)
    try {
      const camposExtras = Object.fromEntries(
        extras.filter((c) => c.valor.trim()).map((c) => [c.key, c.valor.trim()])
      )
      const res = await fetch(`/api/ingest/leads/${source}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...form,
          ...camposExtras,
          // A Agenda identifica o lead pelo id que o site dela gera, e exige um.
          // O cadastro manual não tem esse id, então cria o seu, preso ao
          // telefone: registrar a mesma pessoa de novo atualiza o cadastro em
          // vez de criar outro, e o prefixo deixa claro que não veio do site.
          ...(source === 'agenda_ascensao' ? { id: `manual-${digitos}` } : {}),
          cadastrado_por: profileName || null,
          // A ingestão só pula o funil quando mandam pular — ver `semAutomacao`
          // em src/lib/ingest.ts.
          ...(temAutomacao && !enviarAutomacao ? { sem_automacao: true } : {}),
        }),
      })
      const corpo = await res.json().catch(() => ({}))
      if (!res.ok) throw new Error(corpo?.error || `Erro ${res.status}`)
      onCreated()
      onClose()
    } catch (err: any) {
      setErro(err?.message || 'Não foi possível cadastrar o lead.')
    } finally {
      setSalvando(false)
    }
  }

  return (
    <div className="fixed inset-0 z-[90] flex items-center justify-center p-4" role="dialog" aria-modal="true">
      <div className="absolute inset-0 bg-black/55 backdrop-blur-sm" onClick={onClose} />

      <form
        onSubmit={salvar}
        className="glass-raised relative z-10 w-full max-w-md rounded-2xl flex flex-col max-h-[90vh]"
      >
        <div className="relative flex items-start justify-between gap-3 px-5 py-4 flex-shrink-0">
          <div className="min-w-0">
            <h2 className="text-base font-bold text-ink flex items-center gap-2">
              <UserPlus size={18} weight="bold" className="text-accent-2" />
              {ehIndicacao ? 'Nova indicação' : `Novo lead — ${fonte.label}`}
            </h2>
            <p className="text-xs text-muted mt-0.5">
              Entra no Kanban na primeira etapa, com você como responsável.
            </p>
          </div>
          <button type="button" onClick={onClose} className="btn-icon w-9 h-9 flex-shrink-0" aria-label="Fechar">
            <X size={18} />
          </button>
          <div className="absolute bottom-0 left-0 right-0 h-px hairline-x" />
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3 scrollbar-hide">
          <Campo label="Nome" obrigatorio>
            <input
              autoFocus
              value={form.nome}
              onChange={set('nome')}
              placeholder={ehIndicacao ? 'Nome de quem foi indicado' : 'Nome do lead'}
              className="field"
            />
          </Campo>

          <Campo label="WhatsApp" obrigatorio dica="Com DDD. O 55 é acrescentado sozinho.">
            <input
              value={form.whatsapp}
              onChange={set('whatsapp')}
              inputMode="tel"
              placeholder="(11) 91234-5678"
              className="field"
            />
          </Campo>

          <Campo label="Instagram">
            <input value={form.instagram} onChange={set('instagram')} placeholder="@perfil" className="field" />
          </Campo>

          <Campo label="E-mail">
            <input value={form.email} onChange={set('email')} type="email" placeholder="opcional" className="field" />
          </Campo>

          {ehIndicacao && (
            <Campo label="Indicado por" dica="Quem trouxe essa pessoa.">
              <input value={form.indicado_por} onChange={set('indicado_por')} placeholder="Nome de quem indicou" className="field" />
            </Campo>
          )}

          <Campo label="Observação" dica="Contexto que ajuda no primeiro contato.">
            <textarea
              value={form.observacao}
              onChange={set('observacao')}
              rows={3}
              placeholder={ehIndicacao ? 'Ex.: sócio do André, quer montar rotina de treino' : 'Ex.: mandou os dados por mensagem, formulário não enviou'}
              className="field resize-none"
            />
          </Campo>

          {extras.map((campo, i) => (
            <Campo key={campo.key} label={campo.label} dica={`Mesmo campo de: ${campo.fontesTexto}`}>
              <div className="flex items-center gap-1.5">
                <input
                  autoFocus
                  value={campo.valor}
                  onChange={(e) =>
                    setExtras((atual) =>
                      atual.map((c, j) => (j === i ? { ...c, valor: e.target.value } : c))
                    )
                  }
                  className="field flex-1"
                />
                <button
                  type="button"
                  onClick={() => setExtras((atual) => atual.filter((_, j) => j !== i))}
                  className="btn-icon w-8 h-8 flex-shrink-0"
                  aria-label={`Remover ${campo.label}`}
                >
                  <Trash size={14} />
                </button>
              </div>
            </Campo>
          ))}

          <div className="relative">
            <button
              type="button"
              onClick={() => setListaAberta((v) => !v)}
              className="btn btn-outline btn-sm w-full"
              disabled={disponiveis.length === 0}
            >
              <Plus size={13} weight="bold" />
              {disponiveis.length === 0 ? 'Todos os campos já adicionados' : 'Adicionar campo'}
            </button>

            {listaAberta && disponiveis.length > 0 && (
              <>
                {/* Clicar fora fecha — sem isso a lista fica presa por cima do
                    formulário e atrapalha quem só queria continuar digitando. */}
                <div className="fixed inset-0 z-10" onClick={() => setListaAberta(false)} />
                <div className="absolute z-20 left-0 right-0 bottom-full mb-1 panel rounded-xl max-h-[240px] overflow-y-auto scrollbar-hide py-1">
                  {disponiveis.map((campo) => (
                    <button
                      key={campo.key}
                      type="button"
                      onClick={() => {
                        setExtras((atual) => [
                          ...atual,
                          { key: campo.key, label: campo.label, valor: '', fontesTexto: campo.fontes.join(', ') },
                        ])
                        setListaAberta(false)
                      }}
                      className="w-full text-left px-3 py-1.5 hover:bg-white/5 transition-colors"
                    >
                      <span className="block text-xs text-ink">{campo.label}</span>
                      <span className="block text-[10px] text-muted">{campo.fontes.join(', ')}</span>
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>

          {temAutomacao && (
            <label className="flex items-start gap-2.5 rounded-xl border border-white/[0.08] bg-white/[0.03] px-3 py-2.5 cursor-pointer">
              <input
                type="checkbox"
                checked={enviarAutomacao}
                onChange={(e) => setEnviarAutomacao(e.target.checked)}
                className="mt-0.5 w-4 h-4 accent-[var(--blue)] flex-shrink-0"
              />
              <span className="min-w-0">
                <span className="block text-xs font-semibold text-ink">Enviar a mensagem automática</span>
                <span className="block text-[10px] text-muted leading-snug">
                  A mesma que sai para quem preenche o formulário de {fonte.label}, dois minutos
                  depois. Desmarque para cadastrar sem mandar nada no WhatsApp.
                </span>
              </span>
            </label>
          )}

          {erro && (
            <p className="text-xs text-red-400 bg-red-500/10 border border-red-500/25 rounded-lg px-3 py-2">
              {erro}
            </p>
          )}
        </div>

        <div className="relative flex items-center justify-end gap-2 px-5 py-3 flex-shrink-0">
          <div className="absolute top-0 left-0 right-0 h-px hairline-x" />
          <button type="button" onClick={onClose} className="btn btn-outline btn-sm">
            Cancelar
          </button>
          <button type="submit" disabled={!podeSalvar} className="btn btn-primary btn-sm disabled:opacity-40">
            {salvando ? 'Cadastrando…' : 'Cadastrar lead'}
          </button>
        </div>
      </form>
    </div>
  )
}

function Campo({
  label,
  dica,
  obrigatorio,
  children,
}: {
  label: string
  dica?: string
  obrigatorio?: boolean
  children: React.ReactNode
}) {
  return (
    <label className="block">
      <span className="text-[11px] font-bold uppercase tracking-wider text-muted">
        {label}
        {obrigatorio && <span className="text-red-400 ml-0.5">*</span>}
      </span>
      {dica && <span className="block text-[10px] text-muted/70 mb-1">{dica}</span>}
      <div className={dica ? '' : 'mt-1'}>{children}</div>
    </label>
  )
}
