import { useState, useRef, useEffect } from 'react'
import { PencilSimple, Trash, Check, X, SpinnerGap } from '@phosphor-icons/react'
import { TagWithStats } from '../useTagsSettings'

const TAG_COLORS = [
    { value: '#ef4444', label: 'Vermelho' },
    { value: '#f97316', label: 'Laranja' },
    { value: '#f59e0b', label: 'Amarelo' },
    { value: '#10b981', label: 'Verde' },
    { value: '#0ea5e9', label: 'Azul Celeste' },
    { value: '#3b82f6', label: 'Azul' },
    { value: '#8b5cf6', label: 'Roxo' },
    { value: '#d946ef', label: 'Fúcsia' },
    { value: '#ec4899', label: 'Rosa' },
    { value: '#64748b', label: 'Cinza' },
]

interface TagCardProps {
    tag?: TagWithStats // Opcional para criação de nova tag
    isEditing: boolean
    onStartEdit?: () => void
    onCancelEdit: () => void
    onSave: (data: { name: string; color: string }) => Promise<void>
    onDelete?: () => void
}

export function TagCard({ tag, isEditing, onStartEdit, onCancelEdit, onSave, onDelete }: TagCardProps) {
    const [name, setName] = useState(tag?.name || '')
    const [color, setColor] = useState(tag?.color || TAG_COLORS[5].value)
    const [isSaving, setIsSaving] = useState(false)
    const inputRef = useRef<HTMLInputElement>(null)

    // Foca o input automaticamente ao entrar em modo de edição
    useEffect(() => {
        if (isEditing) {
            setName(tag?.name || '')
            setColor(tag?.color || TAG_COLORS[5].value)
            setTimeout(() => inputRef.current?.focus(), 50)
        }
    }, [isEditing, tag])

    const handleSave = async () => {
        if (!name.trim()) return
        setIsSaving(true)
        try {
            await onSave({ name: name.trim(), color })
            // Success assumes parent will change isEditing to false
        } catch (err) {
            console.error('Error saving tag:', err)
        } finally {
            setIsSaving(false)
        }
    }

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
            handleSave()
        } else if (e.key === 'Escape') {
            onCancelEdit()
        }
    }

    if (isEditing) {
        return (
            <div className="flex flex-col sm:flex-row sm:items-center gap-4 p-5 bg-panel border border-accent-line rounded-2xl shadow-sm transition-all">
                <div className="flex-1 flex flex-col gap-3.5">
                    <input
                        ref={inputRef}
                        type="text"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        onKeyDown={handleKeyDown}
                        placeholder="Nome da tag..."
                        className="w-full px-4 py-2.5 bg-panel border border-line rounded-xl text-sm text-ink focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all placeholder:text-muted"
                    />

                    <div className="flex items-center gap-2 overflow-x-visible pb-2 pt-1 px-1 custom-scrollbar">
                        {TAG_COLORS.map((c) => (
                            <button
                                key={c.value}
                                onClick={() => setColor(c.value)}
                                className={`
                                    w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center transition-all
                                    ${color === c.value ? 'ring-2 ring-offset-2 ring-accent scale-105 shadow-sm' : 'hover:scale-110 hover:shadow-sm opacity-90 hover:opacity-100'}
                                `}
                                style={{ backgroundColor: c.value }}
                                title={c.label}
                            >
                                {color === c.value && <Check size={14} weight="bold" className="text-white" />}
                            </button>
                        ))}
                    </div>
                </div>

                <div className="flex items-center gap-4 self-end sm:self-center pr-2">
                    <button
                        onClick={onCancelEdit}
                        disabled={isSaving}
                        className="p-1 text-muted hover:text-muted transition-colors"
                        title="Cancelar"
                    >
                        <X size={20} weight="bold" />
                    </button>
                    <button
                        onClick={handleSave}
                        disabled={isSaving || !name.trim()}
                        className="px-5 py-2.5 bg-accent hover:bg-accent text-white text-sm font-medium rounded-xl transition-colors shadow-sm disabled:opacity-50 flex items-center gap-2"
                    >
                        {isSaving ? <SpinnerGap size={18} className="animate-spin" /> : <Check size={18} weight="bold" />}
                        Salvar
                    </button>
                </div>
            </div>
        )
    }

    if (!tag) return null

    return (
        <div className="flex items-center justify-between p-4 bg-panel border border-line rounded-2xl hover:border-accent-line hover:shadow-sm transition-all group">
            <div className="flex flex-col gap-1.5 min-w-0">
                <div className="flex items-center gap-2">
                    {/* Status Dot */}
                    <div
                        className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                        style={{ backgroundColor: tag.color || '#3b82f6' }}
                    />

                    {/* Tag Badge */}
                    <div
                        className="px-2.5 py-0.5 rounded-full text-sm font-medium truncate"
                        style={{
                            backgroundColor: `${tag.color || '#3b82f6'}15`,
                            color: tag.color || '#3b82f6'
                        }}
                    >
                        {tag.name}
                    </div>
                </div>

                {/* Active Leads Count */}
                <div className="text-xs text-muted pl-4.5">
                    {tag.activeLeadsCount} {tag.activeLeadsCount === 1 ? 'lead ativo' : 'leads ativos'}
                </div>
            </div>

            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity focus-within:opacity-100">
                {onStartEdit && (
                    <button
                        onClick={onStartEdit}
                        className="p-2 text-muted hover:text-accent-2 hover:bg-panel-2 rounded-lg transition-colors"
                        title="Editar Tag"
                    >
                        <PencilSimple size={18} weight="bold" />
                    </button>
                )}
                {onDelete && (
                    <button
                        onClick={onDelete}
                        className="p-2 text-muted hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                        title="Excluir Tag"
                    >
                        <Trash size={18} weight="bold" />
                    </button>
                )}
            </div>
        </div>
    )
}
