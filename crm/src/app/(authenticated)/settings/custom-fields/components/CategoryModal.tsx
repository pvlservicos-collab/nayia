import { useState, useEffect } from 'react'
import { CustomFieldCategory } from '@/lib/types'
import { X } from '@phosphor-icons/react'

interface CategoryModalProps {
    isOpen: boolean
    onClose: () => void
    category: CustomFieldCategory | null
    onSubmit: (name: string) => Promise<void>
    onDelete?: () => Promise<void>
}

export function CategoryModal({ isOpen, onClose, category, onSubmit, onDelete }: CategoryModalProps) {
    const [name, setName] = useState('')
    const [isSubmitting, setIsSubmitting] = useState(false)
    const [isDeleting, setIsDeleting] = useState(false)

    useEffect(() => {
        if (isOpen) {
            setName(category?.name || '')
            setIsSubmitting(false)
            setIsDeleting(false)
        }
    }, [isOpen, category])

    if (!isOpen) return null

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        if (!name.trim() || isSubmitting) return

        try {
            setIsSubmitting(true)
            await onSubmit(name.trim())
        } catch (err) {
            console.error(err)
        } finally {
            setIsSubmitting(false)
        }
    }

    const handleDelete = async () => {
        if (!onDelete || isDeleting) return
        try {
            setIsDeleting(true)
            await onDelete()
        } catch (error) {
            console.error(error)
            setIsDeleting(false)
        }
    }

    return (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 modal-overlay-enter p-4">
            <div className="bg-panel rounded-2xl w-full max-w-md overflow-hidden shadow-2xl modal-content-enter">
                <div className="px-6 py-4 border-b border-line flex items-center justify-between">
                    <h2 className="text-lg font-bold font-display text-ink">
                        {category ? 'Editar Categoria' : 'Nova Categoria'}
                    </h2>
                    <button
                        onClick={onClose}
                        className="text-muted hover:text-muted transition-colors p-1 rounded-full hover:bg-panel-2"
                    >
                        <X size={20} weight="bold" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="p-6 space-y-6">
                    <div className="space-y-1.5">
                        <label className="text-sm font-semibold text-muted">Name da Categoria</label>
                        <input
                            type="text"
                            required
                            value={name}
                            onChange={e => setName(e.target.value)}
                            placeholder="Ex: Dados Pessoais"
                            className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all font-medium"
                        />
                    </div>

                    <div className="flex items-center justify-between pt-2">
                        <div>
                            {category && onDelete && (
                                <button
                                    type="button"
                                    onClick={handleDelete}
                                    disabled={isDeleting || isSubmitting}
                                    className="text-red-500 hover:text-red-700 text-sm font-semibold transition-colors disabled:opacity-50"
                                >
                                    {isDeleting ? 'Excluindo...' : 'Excluir categoria'}
                                </button>
                            )}
                        </div>

                        <div className="flex items-center gap-3">
                            <button
                                type="button"
                                onClick={onClose}
                                disabled={isSubmitting || isDeleting}
                                className="px-5 py-2.5 text-sm font-semibold text-muted hover:text-ink transition-colors"
                            >
                                Cancelar
                            </button>
                            <button
                                type="submit"
                                disabled={!name.trim() || isSubmitting || isDeleting}
                                className="px-6 py-2.5 bg-accent text-white rounded-xl text-sm font-bold hover:bg-accent-2 transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-md shadow-blue-600/20"
                            >
                                {isSubmitting ? 'Salvando...' : 'Salvar'}
                            </button>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    )
}
