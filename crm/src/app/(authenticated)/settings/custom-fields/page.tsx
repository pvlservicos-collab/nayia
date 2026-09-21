'use client'

import React, { useEffect, useState, useRef } from 'react'
import ReactDOM from 'react-dom'
import { Plus, CaretDown } from '@phosphor-icons/react'
import { useCustomFieldSettings } from './useCustomFieldSettings'
import { CategoryCard } from './components/CategoryCard'
import { CategoryModal } from './components/CategoryModal'
import { CustomFieldCategory } from '@/lib/types'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import { FieldItem } from './components/FieldItem'
import { useChatButtonSettings } from '@/hooks/useChatButtonSettings'

export default function CustomFieldsSettingsPage() {
    const { categories, fields, loading, fetchData, createCategory, updateCategory, deleteCategory, createField, updateField, updateFieldRanks, deleteField } = useCustomFieldSettings()

    // Modal states for Category
    const [isCategoryModalOpen, setIsCategoryModalOpen] = useState(false)
    const [editingCategory, setEditingCategory] = useState<CustomFieldCategory | null>(null)

    // Inline edit states for Field
    const [editingFieldId, setEditingFieldId] = useState<string | null>(null)

    useEffect(() => {
        fetchData()
    }, [fetchData])

    const handleCreateCategory = async (name: string) => {
        await createCategory(name)
        setIsCategoryModalOpen(false)
    }

    const handleEditCategory = (category: CustomFieldCategory) => {
        setEditingCategory(category)
        setIsCategoryModalOpen(true)
    }

    const handleUpdateCategory = async (name: string) => {
        if (editingCategory) {
            await updateCategory(editingCategory.id, { name })
            setEditingCategory(null)
            setIsCategoryModalOpen(false)
        }
    }

    const handleDeleteCategory = async (id: string) => {
        if (confirm('Tem certeza que deseja excluir esta categoria? Os campos atrelados a ela ficarão sem categoria.')) {
            await deleteCategory(id)
            setEditingCategory(null)
            setIsCategoryModalOpen(false)
        }
    }

    const openNewField = () => {
        // Sets 'new' state so an empty inline editor appears at the top
        setEditingFieldId('new')
    }

    const handleSaveField = async (id: string, data: any) => {
        if (id === 'new') {
            await createField(data)
        } else {
            await updateField(id, data)
        }
        setEditingFieldId(null)
    }

    const handleDeleteField = async (id: string) => {
        await deleteField(id)
        setEditingFieldId(null)
    }

    if (loading && categories.length === 0) {
        return (
            <div className="flex justify-center items-center h-48">
                <LoadingSpinner text="Carregando campos..." size="lg" />
            </div>
        )
    }

    const uncategorizedFields = fields.filter(f => !f.category_id)

    return (
        <div className="max-w-4xl pb-20">
            <div className="flex items-center justify-between mb-8">
                <div>
                    <h1 className="text-2xl font-bold font-display text-ink">Campos Customizados</h1>
                    <p className="text-muted mt-1">Crie e organize as propriedades dos seus leads.</p>
                </div>
                <button
                    onClick={openNewField}
                    disabled={editingFieldId === 'new'}
                    className="flex items-center gap-2 px-4 py-2 bg-accent text-white rounded-lg text-sm font-medium hover:bg-accent-2 transition-colors shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
                >
                    <Plus size={16} weight="bold" />
                    Criar
                </button>
            </div>

            <div className="space-y-6">
                {/* New field inline editor at the top */}
                {editingFieldId === 'new' && (
                    <div className="mb-8 animate-in fade-in slide-in-from-top-2 duration-300">
                        <FieldItem
                            categories={categories}
                            isEditing={true}
                            onCancelEdit={() => setEditingFieldId(null)}
                            onSave={async (data) => await handleSaveField('new', data)}
                        />
                    </div>
                )}

                {/* Render categories */}
                {categories.map((category) => (
                    <CategoryCard
                        key={category.id}
                        category={category}
                        fields={fields.filter(f => f.category_id === category.id)}
                        allCategories={categories}
                        editingFieldId={editingFieldId}
                        onEditCategory={() => handleEditCategory(category)}
                        onStartEditField={setEditingFieldId}
                        onCancelEditField={() => setEditingFieldId(null)}
                        onSaveField={handleSaveField}
                        onDeleteField={handleDeleteField}
                        onReorderFields={updateFieldRanks}
                    />
                ))}

                {/* Uncategorized fields */}
                {(uncategorizedFields.length > 0) && (
                    <CategoryCard
                        category={{ id: 'uncategorized', name: 'Outros Campos', rank: 999 } as any}
                        fields={uncategorizedFields}
                        allCategories={categories}
                        editingFieldId={editingFieldId}
                        onEditCategory={() => { }} // Cannot edit fallback category
                        onStartEditField={setEditingFieldId}
                        onCancelEditField={() => setEditingFieldId(null)}
                        onSaveField={handleSaveField}
                        onDeleteField={handleDeleteField}
                        onReorderFields={updateFieldRanks}
                        isFallback
                    />
                )}

                {/* Add new category button */}
                <button
                    onClick={() => {
                        setEditingCategory(null)
                        setIsCategoryModalOpen(true)
                    }}
                    className="w-full py-4 mt-6 border-2 border-dashed border-line rounded-xl text-muted text-sm font-medium hover:text-accent-2 hover:border-accent hover:bg-panel-2 transition-colors flex items-center justify-center gap-2"
                >
                    <Plus size={16} />
                    Adicionar nova categoria
                </button>
                <p className="text-xs text-muted text-center mt-3">
                    Crie novos agrupamentos para organizar melhor os campos de seus clientes.
                </p>

                {/* Chat Button Toggles Section */}
                <ChatButtonTogglesSection />
            </div>

            {/* Modals */}
            <CategoryModal
                isOpen={isCategoryModalOpen}
                onClose={() => {
                    setIsCategoryModalOpen(false)
                    setEditingCategory(null)
                }}
                category={editingCategory}
                onSubmit={editingCategory ? handleUpdateCategory : handleCreateCategory}
                onDelete={editingCategory ? () => handleDeleteCategory(editingCategory.id) : undefined}
            />
        </div>
    )
}

// ── Custom Position Dropdown ──
const POSITION_OPTIONS = [
    { value: 'chat' as const, label: 'Na área do Chat (rodapé)' },
    { value: 'sidebar' as const, label: 'No Menu Direito (Painel do Lead)' },
]

function PositionDropdown({ value, onChange, disabled }: { value: 'chat' | 'sidebar', onChange: (v: 'chat' | 'sidebar') => void, disabled?: boolean }) {
    const [open, setOpen] = useState(false)
    const triggerRef = useRef<HTMLButtonElement>(null)
    const panelRef = useRef<HTMLDivElement>(null)
    const selected = POSITION_OPTIONS.find(o => o.value === value) || POSITION_OPTIONS[0]

    // Close on outside click
    useEffect(() => {
        if (!open) return
        const handler = (e: MouseEvent) => {
            const target = e.target as Node
            if (triggerRef.current?.contains(target)) return
            if (panelRef.current?.contains(target)) return
            setOpen(false)
        }
        document.addEventListener('mousedown', handler)
        return () => document.removeEventListener('mousedown', handler)
    }, [open])

    // Calculate portal position
    const getPortalStyle = (): React.CSSProperties => {
        if (!triggerRef.current) return {}
        const rect = triggerRef.current.getBoundingClientRect()
        return {
            position: 'fixed',
            top: rect.bottom + 4,
            left: rect.left,
            width: rect.width,
            zIndex: 9999,
        }
    }

    return (
        <div className="relative">
            <button
                ref={triggerRef}
                type="button"
                onClick={() => !disabled && setOpen(!open)}
                className="w-full bg-void border border-line text-ink text-sm rounded-lg p-2.5 outline-none transition-colors cursor-pointer flex items-center justify-between hover:border-line focus:ring-2 focus:ring-accent focus:border-accent"
                tabIndex={disabled ? -1 : 0}
            >
                <span>{selected.label}</span>
                <CaretDown size={16} weight="bold" className={`text-muted transition-transform duration-200 ${open ? 'rotate-180' : ''}`} />
            </button>
            {open && typeof document !== 'undefined' && ReactDOM.createPortal(
                <div ref={panelRef} style={getPortalStyle()} className="bg-panel border border-line rounded-lg shadow-lg overflow-hidden">
                    {POSITION_OPTIONS.map((option) => (
                        <button
                            key={option.value}
                            type="button"
                            onClick={() => { onChange(option.value); setOpen(false) }}
                            className={`w-full text-left px-3 py-2.5 text-sm transition-colors ${option.value === value ? 'bg-panel-2 text-accent-2 font-medium' : 'text-muted hover:bg-void'}`}
                        >
                            {option.label}
                        </button>
                    ))}
                </div>,
                document.body
            )}
        </div>
    )
}

// ── Chat Button Toggles Section ──
function ChatButtonTogglesSection() {
    const { settings, loading, updateSettings } = useChatButtonSettings()

    const toggles = [
        { key: 'pausar_ia' as const, label: 'Pausar IA', description: 'Botão para pausar a resposta automática da IA no chat' },
        { key: 'sugerir_passos' as const, label: 'Sugerir próximos passos', description: 'Botão para a IA sugerir as próximas ações com o lead' },
        { key: 'sinalizar_ajuste' as const, label: 'Sinalizar ajuste', description: 'Botão para sinalizar que a conversa precisa de ajuste' },
        { key: 'resumir_conversa' as const, label: 'Resumir conversa', description: 'Botão para a IA resumir a conversa com o lead' },
    ]

    if (loading) return null

    return (
        <div className="mt-10 pt-8 border-t border-line">
            <div className="mb-6">
                <h2 className="text-lg font-bold text-ink">Botões do Chat</h2>
                <p className="text-muted text-sm mt-1">Ative ou desative os botões de ação exibidos na janela de conversa com o lead.</p>
            </div>
            <div className="space-y-1">
                {toggles.map((toggle) => {
                    const config = settings[toggle.key]
                    return (
                        <div key={toggle.key} className="bg-panel border border-line rounded-xl overflow-hidden hover:bg-void transition-colors group">
                            <label className="flex items-center justify-between px-4 py-3.5 cursor-pointer">
                                <div>
                                    <p className="text-sm font-semibold text-ink">{toggle.label}</p>
                                    <p className="text-xs text-muted mt-0.5">{toggle.description}</p>
                                </div>
                                <div className="relative">
                                    <input
                                        type="checkbox"
                                        checked={config.enabled}
                                        onChange={(e) => updateSettings({ [toggle.key]: { ...config, enabled: e.target.checked } })}
                                        className="sr-only peer"
                                    />
                                    <div className="w-11 h-6 bg-panel-2 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-accent-line rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-panel after:border-line after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-accent transition-colors" />
                                </div>
                            </label>

                            {/* Configuration Options */}
                            <div className={`grid transition-[grid-template-rows,opacity,margin] duration-300 ease-in-out ${config.enabled ? 'grid-rows-[1fr] opacity-100 mt-2' : 'grid-rows-[0fr] opacity-0 mt-0 pointer-events-none'}`}>
                                <div className="overflow-hidden">
                                    <div className="px-4 pb-4 space-y-4">
                                        <div>
                                            <label className="block text-xs font-medium text-muted mb-1">
                                                Webhook URL
                                            </label>
                                            <input
                                                type="url"
                                                value={config.webhook_url}
                                                onChange={(e) => updateSettings({ [toggle.key]: { ...config, webhook_url: e.target.value } })}
                                                placeholder="https://exemplo.com/webhook"
                                                className="w-full border border-line rounded-lg px-3 py-2 text-sm text-ink placeholder-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-colors"
                                                tabIndex={config.enabled ? 0 : -1}
                                            />
                                            <p className="text-[11px] text-muted mt-1">
                                                URL que receberá um POST com os dados do lead quando o botão for clicado.
                                            </p>
                                        </div>

                                        <div>
                                            <label className="block text-xs font-medium text-muted mb-1">
                                                Posição do Botão
                                            </label>
                                            <PositionDropdown
                                                value={(config.position || 'chat') as 'chat' | 'sidebar'}
                                                onChange={(v) => updateSettings({ [toggle.key]: { ...config, position: v } })}
                                                disabled={!config.enabled}
                                            />
                                            <p className="text-[11px] text-muted mt-1">
                                                Escolha onde este botão deve aparecer para evitar duplicações.
                                            </p>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    )
                })}
            </div>
        </div>
    )
}

