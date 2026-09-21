'use client'

import { useRef, useState } from 'react'
import { X, Image as ImageIcon, VideoCamera, FileAudio, FileText, Trash, Plus, ArrowUp, ArrowDown, Clock, Stack, MagnifyingGlass } from '@phosphor-icons/react'
import { QuickReply, QuickReplyInput, QuickReplyStepInput } from '@/hooks/useQuickReplies'
import { QUICK_REPLY_VARIABLES, interpolateQuickReply } from '@/lib/quickReplyVariables'
import { uploadClientFile } from '@/lib/blobClient'

interface QuickReplyModalProps {
  scope: 'shared' | 'personal'
  quickReply?: QuickReply | null
  existingCategories: string[]
  /** Respostas já cadastradas, pra puxar conteúdo pronto pra dentro de um passo da
   * sequência — não inclui a própria resposta sendo editada. */
  allQuickReplies?: QuickReply[]
  onSave: (input: QuickReplyInput) => Promise<void>
  onClose: () => void
}

const MAX_STEP_DELAY_SECONDS = 300

const SAMPLE_LEAD = { name: 'Maria Souza', phone: '5511999998888', agentName: 'Você' }

function mediaTypeFromFile(file: File): string {
  if (file.type.startsWith('image/')) return 'image'
  if (file.type.startsWith('video/')) return 'video'
  if (file.type.startsWith('audio/')) return 'audio'
  return 'document'
}

function MediaIcon({ mediaType, size = 18 }: { mediaType: string | null; size?: number }) {
  const props = { size, className: 'text-muted flex-shrink-0' }
  if (mediaType === 'image') return <ImageIcon {...props} />
  if (mediaType === 'video') return <VideoCamera {...props} />
  if (mediaType === 'audio') return <FileAudio {...props} />
  return <FileText {...props} />
}

/** Upload compartilhado entre o campo de mídia único e cada passo da sequência. */
async function uploadMediaFile(file: File): Promise<
  | { ok: true; mediaUrl: string; mediaType: string; mediaFilename: string; mediaMimetype: string }
  | { ok: false; error: string }
> {
  if (file.size > 16 * 1024 * 1024) {
    return { ok: false, error: 'Arquivo muito grande. Máximo: 16MB (limite de mídia do WhatsApp).' }
  }
  try {
    const url = await uploadClientFile(file, 'chat-media', 'quick-reply')
    return { ok: true, mediaUrl: url, mediaType: mediaTypeFromFile(file), mediaFilename: file.name, mediaMimetype: file.type }
  } catch (err: any) {
    return { ok: false, error: err.message || 'Erro ao enviar arquivo.' }
  }
}

/** Anexar/trocar/remover uma mídia — reaproveitado no modo único e em cada passo da sequência. */
function MediaAttachField({
  mediaUrl,
  mediaType,
  mediaFilename,
  uploading,
  onUpload,
  onRemove,
}: {
  mediaUrl: string | null
  mediaType: string | null
  mediaFilename: string | null
  uploading: boolean
  onUpload: (file: File) => void
  onRemove: () => void
}) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  return (
    <div>
      {mediaUrl ? (
        <div className="flex items-center gap-3 px-3 py-2 border border-line rounded-lg">
          <MediaIcon mediaType={mediaType} />
          <span className="flex-1 text-sm text-muted truncate">{mediaFilename || 'Arquivo anexado'}</span>
          <button type="button" onClick={onRemove} className="text-muted hover:text-red-500">
            <Trash size={16} />
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={uploading}
          className="w-full px-3 py-2 border border-dashed border-line rounded-lg text-sm text-muted hover:border-line hover:text-muted transition-colors disabled:opacity-50"
        >
          {uploading ? 'Enviando...' : 'Anexar foto, vídeo, áudio ou documento'}
        </button>
      )}
      <input
        ref={fileInputRef}
        type="file"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0]
          e.target.value = ''
          if (file) onUpload(file)
        }}
      />
    </div>
  )
}

/** Bolha compacta de pré-visualização — uma por passo, na ordem de envio. */
function StepPreviewChip({ step, index }: { step: QuickReplyStepInput; index: number }) {
  const label = step.content?.trim()
    ? (step.content.length > 40 ? step.content.slice(0, 40) + '…' : step.content)
    : null
  return (
    <div className="flex items-center gap-1.5 px-2.5 py-1.5 bg-void border border-line rounded-lg text-xs text-muted">
      <span className="font-mono text-muted">{index + 1}</span>
      {step.mediaType && <MediaIcon mediaType={step.mediaType} size={13} />}
      {label ? <span className="truncate max-w-[220px]">{label}</span> : !step.mediaType && <span className="italic text-muted">vazio</span>}
      {!!step.delaySeconds && (
        <span className="flex items-center gap-0.5 text-amber-600">
          <Clock size={12} weight="bold" /> {step.delaySeconds}s
        </span>
      )}
    </div>
  )
}

export default function QuickReplyModal({ scope, quickReply, existingCategories, allQuickReplies = [], onSave, onClose }: QuickReplyModalProps) {
  const [shortcut, setShortcut] = useState(quickReply?.shortcut || '')
  const [category, setCategory] = useState(quickReply?.category || '')

  // Modo único
  const [content, setContent] = useState(quickReply?.content || '')
  const [mediaUrl, setMediaUrl] = useState<string | null>(quickReply?.mediaUrl || null)
  const [mediaType, setMediaType] = useState<string | null>(quickReply?.mediaType || null)
  const [mediaFilename, setMediaFilename] = useState<string | null>(quickReply?.mediaFilename || null)
  const [mediaMimetype, setMediaMimetype] = useState<string | null>(quickReply?.mediaMimetype || null)
  const [uploading, setUploading] = useState(false)

  // Modo sequência
  const hadSteps = !!quickReply?.steps?.length
  const [mode, setMode] = useState<'single' | 'sequence'>(hadSteps ? 'sequence' : 'single')
  const [steps, setSteps] = useState<QuickReplyStepInput[]>(
    hadSteps
      ? quickReply!.steps!.map((s) => ({
          content: s.content,
          mediaUrl: s.mediaUrl,
          mediaType: s.mediaType,
          mediaMimetype: s.mediaMimetype,
          mediaFilename: s.mediaFilename,
          delaySeconds: s.delaySeconds || 0,
        }))
      : []
  )
  const [uploadingSteps, setUploadingSteps] = useState<Set<number>>(new Set())
  const [reusePickerOpen, setReusePickerOpen] = useState(false)
  const [reuseFilter, setReuseFilter] = useState('')

  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const contentRef = useRef<HTMLTextAreaElement>(null)

  const isEditing = !!quickReply

  const insertVariable = (token: string) => {
    const el = contentRef.current
    if (!el) {
      setContent((c) => c + token)
      return
    }
    const start = el.selectionStart ?? content.length
    const end = el.selectionEnd ?? content.length
    const next = content.slice(0, start) + token + content.slice(end)
    setContent(next)
    requestAnimationFrame(() => {
      el.focus()
      el.selectionStart = el.selectionEnd = start + token.length
    })
  }

  const handleFileChange = async (file: File) => {
    setUploading(true)
    setError(null)
    const result = await uploadMediaFile(file)
    setUploading(false)
    if (!result.ok) {
      setError(result.error)
      return
    }
    setMediaUrl(result.mediaUrl)
    setMediaType(result.mediaType)
    setMediaFilename(result.mediaFilename)
    setMediaMimetype(result.mediaMimetype)
  }

  const removeMedia = () => {
    setMediaUrl(null)
    setMediaType(null)
    setMediaFilename(null)
    setMediaMimetype(null)
  }

  // ── Sequência: adicionar/remover/reordenar/editar passos ──
  const addStep = () => setSteps((s) => [...s, { content: '', mediaUrl: null, mediaType: null, mediaMimetype: null, mediaFilename: null, delaySeconds: 0 }])
  const removeStep = (i: number) => setSteps((s) => s.filter((_, idx) => idx !== i))
  const moveStep = (i: number, dir: -1 | 1) =>
    setSteps((s) => {
      const j = i + dir
      if (j < 0 || j >= s.length) return s
      const next = [...s]
      ;[next[i], next[j]] = [next[j], next[i]]
      return next
    })
  const updateStepContent = (i: number, value: string) =>
    setSteps((s) => s.map((st, idx) => (idx === i ? { ...st, content: value } : st)))
  const updateStepMedia = (i: number, media: Partial<QuickReplyStepInput>) =>
    setSteps((s) => s.map((st, idx) => (idx === i ? { ...st, ...media } : st)))
  const updateStepDelay = (i: number, value: number) =>
    setSteps((s) =>
      s.map((st, idx) => (idx === i ? { ...st, delaySeconds: Math.max(0, Math.min(MAX_STEP_DELAY_SECONDS, Math.round(value) || 0)) } : st))
    )

  // Puxa o conteúdo de uma resposta já cadastrada pro fim da sequência — copia os
  // valores pro passo (não fica ligado à original: editar/apagar ela depois não afeta
  // a sequência já montada). Se a resposta escolhida já for uma sequência, traz todos
  // os passos dela (com o delay de cada um) em vez de só o primeiro.
  const insertFromExisting = (qr: QuickReply) => {
    const newSteps: QuickReplyStepInput[] =
      qr.steps && qr.steps.length > 0
        ? qr.steps.map((s) => ({
            content: s.content,
            mediaUrl: s.mediaUrl,
            mediaType: s.mediaType,
            mediaMimetype: s.mediaMimetype,
            mediaFilename: s.mediaFilename,
            delaySeconds: s.delaySeconds || 0,
          }))
        : [{ content: qr.content, mediaUrl: qr.mediaUrl, mediaType: qr.mediaType, mediaMimetype: qr.mediaMimetype, mediaFilename: qr.mediaFilename, delaySeconds: 0 }]
    setSteps((s) => [...s, ...newSteps])
    setReusePickerOpen(false)
    setReuseFilter('')
  }

  const reuseMatches = allQuickReplies.filter((qr) => {
    const needle = reuseFilter.trim().toLowerCase()
    if (!needle) return true
    return qr.shortcut.toLowerCase().includes(needle) || qr.content.toLowerCase().includes(needle)
  })

  const handleStepFileChange = async (i: number, file: File) => {
    setUploadingSteps((prev) => new Set(prev).add(i))
    setError(null)
    const result = await uploadMediaFile(file)
    setUploadingSteps((prev) => {
      const next = new Set(prev)
      next.delete(i)
      return next
    })
    if (!result.ok) {
      setError(result.error)
      return
    }
    updateStepMedia(i, { mediaUrl: result.mediaUrl, mediaType: result.mediaType, mediaFilename: result.mediaFilename, mediaMimetype: result.mediaMimetype })
  }

  // ── Alternar entre os dois modos sem perder o que já foi digitado ──
  const switchToSequence = () => {
    if (mode === 'sequence') return
    if (steps.length === 0) {
      setSteps(
        content.trim() || mediaUrl
          ? [{ content, mediaUrl, mediaType, mediaMimetype, mediaFilename, delaySeconds: 0 }]
          : [{ content: '', mediaUrl: null, mediaType: null, mediaMimetype: null, mediaFilename: null, delaySeconds: 0 }]
      )
    }
    setMode('sequence')
  }
  const switchToSingle = () => {
    if (mode === 'single') return
    if (steps.length > 1 && !confirm('Voltar pra mensagem única mantém só o 1º passo da sequência e descarta o resto. Continuar?')) return
    const first = steps[0]
    if (first) {
      setContent(first.content || '')
      setMediaUrl(first.mediaUrl || null)
      setMediaType(first.mediaType || null)
      setMediaMimetype(first.mediaMimetype || null)
      setMediaFilename(first.mediaFilename || null)
    }
    setMode('single')
  }

  const handleSubmit = async () => {
    setError(null)
    const cleanShortcut = shortcut.trim().replace(/^\/+/, '')
    if (!cleanShortcut) {
      setError('Informe um atalho.')
      return
    }
    if (/\s/.test(cleanShortcut)) {
      setError('O atalho não pode conter espaços.')
      return
    }

    if (mode === 'sequence') {
      if (steps.length === 0) {
        setError('Adicione pelo menos uma mensagem à sequência.')
        return
      }
      const emptyIdx = steps.findIndex((s) => !s.content?.trim() && !s.mediaUrl)
      if (emptyIdx !== -1) {
        setError(`Passo ${emptyIdx + 1}: informe um texto ou anexe uma mídia.`)
        return
      }
    } else if (!content.trim() && !mediaUrl) {
      setError('Informe um texto ou anexe uma mídia.')
      return
    }

    try {
      setSaving(true)
      await onSave({
        scope,
        shortcut: cleanShortcut,
        category: category.trim() || null,
        content: mode === 'single' ? content : '',
        mediaUrl: mode === 'single' ? mediaUrl : null,
        mediaType: mode === 'single' ? mediaType : null,
        mediaMimetype: mode === 'single' ? mediaMimetype : null,
        mediaFilename: mode === 'single' ? mediaFilename : null,
        // Manda 'steps' (mesmo array vazio) só quando precisa mexer na sequência —
        // sequência nova, ou voltando de sequência pra única (limpa os passos antigos).
        // undefined = não mexe (JSON.stringify descarta a chave, API nem olha pra ela).
        steps: mode === 'sequence' ? steps : hadSteps ? [] : undefined,
      })
    } catch (err: any) {
      setError(err.message || 'Erro ao salvar.')
    } finally {
      setSaving(false)
    }
  }

  const preview = interpolateQuickReply(content, {
    name: SAMPLE_LEAD.name,
    phone: SAMPLE_LEAD.phone,
    agentName: SAMPLE_LEAD.agentName,
  })

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className={`bg-panel rounded-2xl shadow-xl w-full ${mode === 'sequence' ? 'max-w-2xl' : 'max-w-lg'} max-h-[90dvh] overflow-y-auto transition-[max-width]`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-6 py-4 border-b border-line">
          <h3 className="text-lg font-bold text-ink">
            {isEditing ? 'Editar resposta rápida' : scope === 'shared' ? 'Nova resposta compartilhada' : 'Novo atalho pessoal'}
          </h3>
          <button onClick={onClose} className="text-muted hover:text-muted">
            <X size={20} />
          </button>
        </div>

        <div className="p-6 space-y-4">
          {error && (
            <div className="px-3 py-2 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg">{error}</div>
          )}

          <div className="flex gap-4">
            <div className="flex-1">
              <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Atalho</label>
              <div className="flex items-center gap-1.5 px-3 py-2 border border-line rounded-lg focus-within:ring-2 focus-within:ring-accent focus-within:border-accent">
                <span className="text-muted font-mono text-sm">/</span>
                <input
                  value={shortcut}
                  onChange={(e) => setShortcut(e.target.value)}
                  placeholder="promo-fim-de-ano"
                  className="flex-1 text-sm focus:outline-none"
                />
              </div>
            </div>
            <div className="flex-1">
              <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Categoria (opcional)</label>
              <input
                list="quick-reply-categories"
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                placeholder="Ex: Vendas, Pós-venda..."
                className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent"
              />
              <datalist id="quick-reply-categories">
                {existingCategories.map((c) => (
                  <option key={c} value={c} />
                ))}
              </datalist>
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Tipo de resposta</label>
            <div className="inline-flex rounded-lg border border-line p-0.5 bg-void">
              <button
                type="button"
                onClick={switchToSingle}
                className={`px-3 py-1.5 text-sm font-semibold rounded-md transition-colors ${
                  mode === 'single' ? 'bg-panel text-ink shadow-sm' : 'text-muted hover:text-muted'
                }`}
              >
                Mensagem única
              </button>
              <button
                type="button"
                onClick={switchToSequence}
                className={`px-3 py-1.5 text-sm font-semibold rounded-md transition-colors ${
                  mode === 'sequence' ? 'bg-panel text-ink shadow-sm' : 'text-muted hover:text-muted'
                }`}
              >
                Sequência de mensagens
              </button>
            </div>
            {mode === 'sequence' && (
              <p className="mt-1.5 text-xs text-muted">
                Manda tudo em ordem, com um clique só — cada passo vira uma mensagem separada no WhatsApp (ex: áudio de apresentação + foto do produto).
              </p>
            )}
          </div>

          {mode === 'single' ? (
            <>
              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="block text-xs font-semibold text-muted uppercase tracking-wide">Mensagem</label>
                  <div className="flex gap-1">
                    {QUICK_REPLY_VARIABLES.map((v) => (
                      <button
                        key={v.token}
                        type="button"
                        onClick={() => insertVariable(v.token)}
                        title={v.label}
                        className="px-2 py-0.5 text-[11px] font-mono bg-panel-2 hover:bg-panel-2 text-muted rounded transition-colors"
                      >
                        {v.token}
                      </button>
                    ))}
                  </div>
                </div>
                <textarea
                  ref={contentRef}
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                  rows={4}
                  placeholder="Digite a mensagem..."
                  className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent resize-none"
                />
                {content.trim() && (
                  <p className="mt-1.5 text-xs text-muted italic truncate">Prévia: &quot;{preview}&quot;</p>
                )}
              </div>

              <div>
                <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Mídia (opcional)</label>
                <MediaAttachField
                  mediaUrl={mediaUrl}
                  mediaType={mediaType}
                  mediaFilename={mediaFilename}
                  uploading={uploading}
                  onUpload={handleFileChange}
                  onRemove={removeMedia}
                />
              </div>
            </>
          ) : (
            <div className="space-y-3">
              <label className="block text-xs font-semibold text-muted uppercase tracking-wide">
                Passos ({steps.length})
              </label>
              {steps.map((step, i) => (
                <div key={i} className="border border-line rounded-xl p-3 space-y-2 bg-void">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-muted">Passo {i + 1}</span>
                    <div className="flex items-center gap-1">
                      <button type="button" onClick={() => moveStep(i, -1)} disabled={i === 0} className="p-1 text-muted hover:text-muted disabled:opacity-25 disabled:hover:text-muted">
                        <ArrowUp size={14} />
                      </button>
                      <button type="button" onClick={() => moveStep(i, 1)} disabled={i === steps.length - 1} className="p-1 text-muted hover:text-muted disabled:opacity-25 disabled:hover:text-muted">
                        <ArrowDown size={14} />
                      </button>
                      <button type="button" onClick={() => removeStep(i)} className="p-1 text-muted hover:text-red-500">
                        <Trash size={14} />
                      </button>
                    </div>
                  </div>
                  <textarea
                    value={step.content || ''}
                    onChange={(e) => updateStepContent(i, e.target.value)}
                    rows={2}
                    placeholder="Texto (opcional)..."
                    className="w-full px-3 py-2 border border-line rounded-lg text-sm bg-panel focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent resize-none"
                  />
                  <MediaAttachField
                    mediaUrl={step.mediaUrl || null}
                    mediaType={step.mediaType || null}
                    mediaFilename={step.mediaFilename || null}
                    uploading={uploadingSteps.has(i)}
                    onUpload={(file) => handleStepFileChange(i, file)}
                    onRemove={() => updateStepMedia(i, { mediaUrl: null, mediaType: null, mediaMimetype: null, mediaFilename: null })}
                  />
                  {i < steps.length - 1 && (
                    <div className="flex items-center gap-1.5 pt-1">
                      <Clock size={13} className="text-muted flex-shrink-0" />
                      <span className="text-xs text-muted">Aguardar</span>
                      <input
                        type="number"
                        min={0}
                        max={MAX_STEP_DELAY_SECONDS}
                        value={step.delaySeconds || 0}
                        onChange={(e) => updateStepDelay(i, Number(e.target.value))}
                        className="w-16 px-2 py-1 border border-line rounded-md text-sm text-center bg-panel focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent"
                      />
                      <span className="text-xs text-muted">segundos antes do próximo passo</span>
                    </div>
                  )}
                </div>
              ))}

              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={addStep}
                  className="flex-1 flex items-center justify-center gap-1.5 px-3 py-2 border border-dashed border-line rounded-lg text-sm font-semibold text-muted hover:border-accent hover:text-accent-2 transition-colors"
                >
                  <Plus size={14} weight="bold" /> Adicionar mensagem
                </button>
                {allQuickReplies.length > 0 && (
                  <button
                    type="button"
                    onClick={() => setReusePickerOpen((v) => !v)}
                    className={`flex-1 flex items-center justify-center gap-1.5 px-3 py-2 border rounded-lg text-sm font-semibold transition-colors ${
                      reusePickerOpen
                        ? 'border-accent text-accent-2 bg-panel-2'
                        : 'border-dashed border-line text-muted hover:border-accent hover:text-accent-2'
                    }`}
                  >
                    <Stack size={14} weight="bold" /> Usar resposta pronta
                  </button>
                )}
              </div>

              {reusePickerOpen && (
                <div className="border border-line rounded-xl p-2 space-y-2 bg-panel">
                  <div className="flex items-center gap-1.5 px-2 py-1.5 border border-line rounded-lg">
                    <MagnifyingGlass size={14} className="text-muted flex-shrink-0" />
                    <input
                      autoFocus
                      value={reuseFilter}
                      onChange={(e) => setReuseFilter(e.target.value)}
                      placeholder="Buscar por atalho ou texto..."
                      className="flex-1 text-sm focus:outline-none"
                    />
                  </div>
                  <div className="max-h-[180px] overflow-y-auto space-y-0.5">
                    {reuseMatches.length === 0 ? (
                      <p className="px-2 py-3 text-xs text-muted text-center">Nenhuma resposta encontrada.</p>
                    ) : (
                      reuseMatches.map((qr) => (
                        <button
                          key={qr.id}
                          type="button"
                          onClick={() => insertFromExisting(qr)}
                          className="w-full flex items-center gap-2 px-2 py-1.5 text-left rounded-lg hover:bg-void transition-colors"
                        >
                          {qr.steps && qr.steps.length > 0 ? (
                            <Stack size={14} className="text-muted flex-shrink-0" />
                          ) : (
                            <MediaIcon mediaType={qr.mediaType} size={14} />
                          )}
                          <span className="text-sm font-semibold text-ink">/{qr.shortcut}</span>
                          <span className="text-xs text-muted truncate flex-1">
                            {qr.steps && qr.steps.length > 0 ? `${qr.steps.length} passos` : qr.content}
                          </span>
                        </button>
                      ))
                    )}
                  </div>
                </div>
              )}

              {steps.length > 0 && (
                <div>
                  <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Prévia da ordem de envio</label>
                  <div className="flex flex-col gap-1">
                    {steps.map((s, i) => (
                      <StepPreviewChip key={i} step={s} index={i} />
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>

        <div className="flex justify-end gap-2 px-6 py-4 border-t border-line">
          <button onClick={onClose} className="px-4 py-2 text-sm font-semibold text-muted hover:bg-void rounded-lg transition-colors">
            Cancelar
          </button>
          <button
            onClick={handleSubmit}
            disabled={saving || uploading || uploadingSteps.size > 0}
            className="px-4 py-2 bg-accent hover:bg-accent-2 text-white text-sm font-semibold rounded-lg transition-colors disabled:opacity-50"
          >
            {saving ? 'Salvando...' : 'Salvar'}
          </button>
        </div>
      </div>
    </div>
  )
}
