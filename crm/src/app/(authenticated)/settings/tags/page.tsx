'use client'

import { useState, useMemo } from 'react'
import { Plus, MagnifyingGlass } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { useTagsSettings, TagWithStats } from './useTagsSettings'
import { TagCard } from './components/TagCard'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import NotAuthorized from '@/components/Shared/NotAuthorized'

export default function TagsSettingsPage() {
    const { organizationId, loading: authLoading, roleName, isMaster, permissions } = useAuth()
    const { tags, loading: tagsLoading, createTag, updateTag, deleteTag } = useTagsSettings(organizationId)

    const [editingTagId, setEditingTagId] = useState<string | null>(null)
    const [searchTerm, setSearchTerm] = useState('')

    // Apenas Admins e Master podem acessar
    const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']

    // Filtragem de tags
    const filteredTags = useMemo(() => {
        if (!searchTerm) return tags
        const lowerSearch = searchTerm.toLowerCase()
        return tags.filter(t => t.name.toLowerCase().includes(lowerSearch))
    }, [tags, searchTerm])

    if (!authLoading && !isAdmin) {
        return <NotAuthorized />
    }

    const handleCreateTagClick = () => {
        setSearchTerm('') // Limpa a busca para garantir que o input de nova tag apareça
        setEditingTagId('new')
    }

    const handleEditTagClick = (tagId: string) => {
        setEditingTagId(tagId)
    }

    const handleDeleteTag = async (tagId: string) => {
        if (confirm('Tem certeza que deseja excluir esta tag? Ela será removida de todos os leads associados.')) {
            try {
                await deleteTag(tagId)
                if (editingTagId === tagId) setEditingTagId(null)
            } catch (err) {
                alert('Erro ao excluir tag. Tente novamente.')
            }
        }
    }

    const handleSaveTag = async (data: { name: string; color: string }) => {
        if (editingTagId === 'new') {
            await createTag(data)
        } else if (editingTagId) {
            await updateTag(editingTagId, data)
        }
        setEditingTagId(null)
    }

    return (
        <div className="max-w-3xl mx-auto space-y-6">
            {/* Header Area */}
            <div className="flex flex-col gap-4">
                <div className="flex items-center justify-between">
                    <h1 className="text-2xl font-bold text-ink">Tags</h1>
                    <button
                        onClick={handleCreateTagClick}
                        disabled={editingTagId === 'new'}
                        className="px-4 py-2 bg-accent hover:bg-accent-2 text-white text-sm font-semibold rounded-lg transition-colors shadow-sm flex items-center justify-center gap-2 disabled:opacity-50"
                    >
                        <Plus size={16} weight="bold" />
                        Criar nova
                    </button>
                </div>

                {/* Search Input */}
                <div className="relative">
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <MagnifyingGlass className="text-muted" size={18} />
                    </div>
                    <input
                        type="text"
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        placeholder="Buscar tags..."
                        className="block w-full pl-10 pr-3 py-2.5 border border-line rounded-xl leading-5 bg-panel placeholder-muted focus:outline-none focus:bg-panel focus:ring-2 focus:ring-accent focus:border-accent sm:text-sm transition-all shadow-sm"
                    />
                </div>
            </div>

            {/* Content Area - Tags List */}
            <div className="space-y-3">
                {editingTagId === 'new' && (
                    <TagCard
                        isEditing={true}
                        onCancelEdit={() => setEditingTagId(null)}
                        onSave={handleSaveTag}
                    />
                )}

                {tagsLoading ? (
                    <div className="py-12 flex justify-center bg-panel rounded-2xl border border-line shadow-sm">
                        <LoadingSpinner text="Carregando tags..." />
                    </div>
                ) : filteredTags.length > 0 ? (
                    filteredTags.map((tag) => (
                        <TagCard
                            key={tag.id}
                            tag={tag}
                            isEditing={editingTagId === tag.id}
                            onStartEdit={() => handleEditTagClick(tag.id)}
                            onCancelEdit={() => setEditingTagId(null)}
                            onSave={handleSaveTag}
                            onDelete={() => handleDeleteTag(tag.id)}
                        />
                    ))
                ) : editingTagId !== 'new' ? (
                    <div className="text-center py-12 bg-panel rounded-2xl border border-line shadow-sm">
                        <div className="w-12 h-12 bg-void rounded-full flex items-center justify-center mx-auto mb-3">
                            <MagnifyingGlass size={24} className="text-muted" />
                        </div>
                        <h3 className="text-sm font-medium text-ink mb-1">
                            {searchTerm ? 'Nenhuma tag encontrada' : 'Nenhuma tag criada'}
                        </h3>
                        <p className="text-sm text-muted max-w-sm mx-auto">
                            {searchTerm
                                ? `Não encontramos resultados para "${searchTerm}".`
                                : 'Crie tags para categorizar e organizar seus leads de forma visual.'}
                        </p>
                    </div>
                ) : null}
            </div>
        </div>
    )
}
