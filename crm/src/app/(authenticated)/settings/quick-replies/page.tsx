'use client'

import { useState, useMemo } from 'react'
import { Plus, Lightning, Image as ImageIcon, VideoCamera, FileAudio, FileText, PencilSimple, Trash } from '@phosphor-icons/react'
import { useAuth, useQuickReplies } from '@/hooks'
import { QuickReply, QuickReplyInput } from '@/hooks/useQuickReplies'
import QuickReplyModal from './components/QuickReplyModal'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

function MediaBadge({ mediaType }: { mediaType: string | null }) {
  if (!mediaType) return null
  const props = { size: 14, className: 'text-muted flex-shrink-0' }
  if (mediaType === 'image') return <ImageIcon {...props} />
  if (mediaType === 'video') return <VideoCamera {...props} />
  if (mediaType === 'audio') return <FileAudio {...props} />
  return <FileText {...props} />
}

function QuickReplyRow({
  qr,
  canManage,
  onEdit,
  onDelete,
}: {
  qr: QuickReply
  canManage: boolean
  onEdit: () => void
  onDelete: () => void
}) {
  return (
    <div className="flex items-center gap-3 px-4 py-3 bg-panel border border-line rounded-xl shadow-sm">
      <Lightning size={16} weight="fill" className="text-accent-2 flex-shrink-0" />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="text-sm font-semibold text-ink">/{qr.shortcut}</span>
          <MediaBadge mediaType={qr.mediaType} />
          {qr.category && (
            <span className="px-1.5 py-0.5 bg-panel-2 text-muted text-[10px] font-semibold rounded uppercase tracking-wide">
              {qr.category}
            </span>
          )}
        </div>
        {qr.content && <p className="text-xs text-muted truncate mt-0.5">{qr.content}</p>}
      </div>
      {canManage && (
        <div className="flex items-center gap-1 flex-shrink-0">
          <button onClick={onEdit} className="p-1.5 text-muted hover:text-accent-2 hover:bg-panel-2 rounded-lg transition-colors">
            <PencilSimple size={16} />
          </button>
          <button onClick={onDelete} className="p-1.5 text-muted hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors">
            <Trash size={16} />
          </button>
        </div>
      )}
    </div>
  )
}

export default function QuickRepliesSettingsPage() {
  const { organizationId, roleName, isMaster, permissions, loading: authLoading } = useAuth()
  const { shared, personal, loading, createQuickReply, updateQuickReply, deleteQuickReply } = useQuickReplies(organizationId)

  const canManageShared =
    isMaster ||
    roleName?.toLowerCase() === 'administrador' ||
    roleName?.toLowerCase() === 'owner' ||
    !!(permissions as any)?.settings?.manage_quick_replies

  const [modalState, setModalState] = useState<{ scope: 'shared' | 'personal'; quickReply: QuickReply | null } | null>(null)

  const existingCategories = useMemo(() => {
    const set = new Set<string>()
    for (const qr of shared) if (qr.category) set.add(qr.category)
    return [...set].sort()
  }, [shared])

  const handleSave = async (input: QuickReplyInput) => {
    if (modalState?.quickReply) {
      await updateQuickReply(modalState.quickReply.id, input)
    } else {
      await createQuickReply(input)
    }
    setModalState(null)
  }

  const handleDelete = async (qr: QuickReply) => {
    if (!confirm(`Excluir a resposta rápida "/${qr.shortcut}"?`)) return
    await deleteQuickReply(qr.id)
  }

  if (authLoading || loading) {
    return (
      <div className="py-12 flex justify-center">
        <LoadingSpinner text="Carregando respostas rápidas..." />
      </div>
    )
  }

  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-ink">Respostas Rápidas</h1>
        <p className="text-sm text-muted mt-1">
          Crie atalhos de texto, foto, áudio ou vídeo para agilizar o atendimento. Digite &quot;/&quot; no chat para usá-los.
        </p>
      </div>

      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-bold text-muted uppercase tracking-wide">Biblioteca da Empresa</h2>
          {canManageShared && (
            <button
              onClick={() => setModalState({ scope: 'shared', quickReply: null })}
              className="px-3 py-1.5 bg-accent hover:bg-accent-2 text-white text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5"
            >
              <Plus size={14} weight="bold" /> Nova
            </button>
          )}
        </div>
        {shared.length === 0 ? (
          <p className="text-sm text-muted italic px-1">Nenhuma resposta compartilhada ainda.</p>
        ) : (
          <div className="space-y-2">
            {shared.map((qr) => (
              <QuickReplyRow
                key={qr.id}
                qr={qr}
                canManage={canManageShared}
                onEdit={() => setModalState({ scope: 'shared', quickReply: qr })}
                onDelete={() => handleDelete(qr)}
              />
            ))}
          </div>
        )}
        {!canManageShared && (
          <p className="text-xs text-muted">Você pode usar a biblioteca da empresa no chat, mas só um administrador pode editá-la.</p>
        )}
      </section>

      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-bold text-muted uppercase tracking-wide">Meus Atalhos Pessoais</h2>
          <button
            onClick={() => setModalState({ scope: 'personal', quickReply: null })}
            className="px-3 py-1.5 bg-accent hover:bg-accent-2 text-white text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5"
          >
            <Plus size={14} weight="bold" /> Novo
          </button>
        </div>
        {personal.length === 0 ? (
          <p className="text-sm text-muted italic px-1">Você ainda não tem atalhos pessoais.</p>
        ) : (
          <div className="space-y-2">
            {personal.map((qr) => (
              <QuickReplyRow
                key={qr.id}
                qr={qr}
                canManage
                onEdit={() => setModalState({ scope: 'personal', quickReply: qr })}
                onDelete={() => handleDelete(qr)}
              />
            ))}
          </div>
        )}
      </section>

      {modalState && (
        <QuickReplyModal
          scope={modalState.scope}
          quickReply={modalState.quickReply}
          existingCategories={existingCategories}
          allQuickReplies={[...shared, ...personal].filter((qr) => qr.id !== modalState.quickReply?.id)}
          onSave={handleSave}
          onClose={() => setModalState(null)}
        />
      )}
    </div>
  )
}
