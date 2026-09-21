import { useState, useRef, useEffect } from 'react'
import { CustomFieldDefinition, CustomFieldCategory } from '@/lib/types'
import { CaretRight, CaretDown, Check, X, Plus, Trash, SpinnerGap, DotsSixVertical } from '@phosphor-icons/react'
import { useSortable } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
interface Option {
    value: string
    label: string
}

function CustomSelect({
    value,
    onChange,
    options,
    disabled,
    placeholder
}: {
    value: string,
    onChange: (val: string) => void,
    options: Option[],
    disabled?: boolean,
    placeholder?: string
}) {
    const [isOpen, setIsOpen] = useState(false)
    const ref = useRef<HTMLDivElement>(null)

    useEffect(() => {
        function handleClickOutside(event: MouseEvent) {
            if (ref.current && !ref.current.contains(event.target as Node)) {
                setIsOpen(false)
            }
        }
        document.addEventListener("mousedown", handleClickOutside)
        return () => document.removeEventListener("mousedown", handleClickOutside)
    }, [])

    const selected = options.find(o => o.value === value)

    return (
        <div className="relative w-full" ref={ref}>
            <button
                type="button"
                disabled={disabled}
                onClick={() => !disabled && setIsOpen(!isOpen)}
                className={`w-full h-11 px-4 bg-void border border-line rounded-xl text-sm font-medium flex items-center justify-between focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all ${disabled ? 'opacity-70 cursor-not-allowed' : 'hover:bg-panel-2 focus:bg-panel'}`}
            >
                <span className={selected ? 'text-ink' : 'text-muted'}>
                    {selected ? selected.label : placeholder}
                </span>
                <CaretDown size={16} weight="bold" className={`text-muted transition-transform ${isOpen ? 'rotate-180' : ''}`} />
            </button>

            {isOpen && (
                <div className="absolute z-50 w-full mt-1 bg-panel border border-line rounded-xl shadow-lg shadow-black/5 py-1.5 max-h-60 overflow-y-auto animate-in fade-in zoom-in-95 duration-100">
                    {options.map((opt) => {
                        const isSelected = value === opt.value
                        return (
                            <button
                                key={opt.value}
                                type="button"
                                onClick={() => {
                                    onChange(opt.value)
                                    setIsOpen(false)
                                }}
                                className={`w-full px-4 py-2.5 text-left text-sm font-medium transition-colors flex items-center justify-between group ${isSelected ? 'bg-panel-2 text-accent-2' : 'text-muted hover:bg-void hover:text-ink'}`}
                            >
                                <span>{opt.label}</span>
                                {isSelected && <Check size={16} weight="bold" className="text-accent-2" />}
                            </button>
                        )
                    })}
                </div>
            )}
        </div>
    )
}

const FIELD_TYPES = [
    { value: 'text', label: 'Texto Curto' },
    { value: 'number', label: 'Número' },
    { value: 'currency', label: 'Moeda' },
    { value: 'date', label: 'Data' },
    { value: 'datetime', label: 'Data e Hora' },
    { value: 'bool', label: 'Verdadeiro/Falso' },
    { value: 'select', label: 'Seleção Única' },
    { value: 'multi_select', label: 'Múltipla Escolha' },
    { value: 'json', label: 'JSON / Estruturado' }
]

interface FieldItemProps {
    field?: CustomFieldDefinition
    categories: CustomFieldCategory[]
    isEditing: boolean
    onStartEdit?: () => void
    onCancelEdit: () => void
    onSave: (data: any) => Promise<void>
    onDelete?: () => Promise<void>
    defaultCategoryId?: string
}

export function FieldItem({ field, categories, isEditing, onStartEdit, onCancelEdit, onSave, onDelete, defaultCategoryId }: FieldItemProps) {
    const inputRef = useRef<HTMLInputElement>(null)

    // Drag and Drop
    const {
        attributes,
        listeners,
        setNodeRef,
        transform,
        transition,
        isDragging,
    } = useSortable({ id: field?.id || 'new', disabled: isEditing || !field })

    const style = {
        transform: CSS.Transform.toString(transform),
        transition,
        zIndex: isDragging ? 50 : 1,
    }

    // Modal / Local states for edit form
    const [name, setName] = useState(field?.name || '')
    const [fieldType, setFieldType] = useState<string>(field?.field_type || 'text')
    const [categoryId, setCategoryId] = useState(field?.category_id || defaultCategoryId || '')
    const [description, setDescription] = useState(field?.schema?.description || '')
    const [options, setOptions] = useState<string[]>(field?.schema?.options || [])

    const [isSaving, setIsSaving] = useState(false)
    const [isDeleting, setIsDeleting] = useState(false)

    useEffect(() => {
        if (isEditing && inputRef.current) {
            inputRef.current.focus()

            let initialCat = field?.category_id || defaultCategoryId || ''
            if (!field && !defaultCategoryId && categories.length > 0) {
                initialCat = categories[categories.length - 1].id
            }

            // Reset state specific to this editing session if field prop changes
            setName(field?.name || '')
            setFieldType(field?.field_type || 'text')
            setCategoryId(initialCat)
            setDescription(field?.schema?.description || '')
            setOptions(field?.schema?.options || [])
        }
    }, [isEditing, field, defaultCategoryId, categories])

    const needsOptions = fieldType === 'select' || fieldType === 'multi_select'

    const handleAddOption = () => {
        setOptions([...options, ''])
    }

    const handleUpdateOption = (index: number, val: string) => {
        const newOptions = [...options]
        newOptions[index] = val
        setOptions(newOptions)
    }

    const handleRemoveOption = (index: number) => {
        setOptions(options.filter((_, i) => i !== index))
    }

    const handleSave = async () => {
        if (!name.trim()) return
        if (needsOptions && options.every(o => !o.trim())) return

        setIsSaving(true)
        try {
            await onSave({
                name: name.trim(),
                field_type: fieldType,
                category_id: categoryId || null,
                description: description.trim(),
                options: needsOptions ? options.filter(o => o.trim()) : []
            })
        } catch (err) {
            console.error('Error saving custom field:', err)
        } finally {
            setIsSaving(false)
        }
    }

    const handleDelete = async () => {
        if (!onDelete || isDeleting) return
        if (confirm('Tem certeza que deseja excluir este campo?')) {
            setIsDeleting(true)
            await onDelete()
            setIsDeleting(false)
        }
    }

    if (isEditing) {
        return (
            <div
                ref={setNodeRef}
                className="p-5 bg-panel border border-accent-line rounded-xl shadow-sm transition-all animate-in fade-in zoom-in-[0.98] duration-200"
            >
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {/* Nome */}
                    <div className="col-span-1 md:col-span-2 space-y-1.5">
                        <label className="text-sm font-semibold text-muted">Nome do Campo</label>
                        <input
                            ref={inputRef}
                            type="text"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            onKeyDown={(e) => { if (e.key === 'Escape') onCancelEdit() }}
                            placeholder="Ex: CPF, Cargo, Escolaridade"
                            className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all font-medium"
                        />
                    </div>

                    {/* Tipo */}
                    <div className="space-y-1.5">
                        <label className="text-sm font-semibold text-muted">Tipo do Campo</label>
                        <CustomSelect
                            value={fieldType}
                            onChange={setFieldType}
                            options={FIELD_TYPES}
                            disabled={!!field} // Cannot change type after creation
                        />
                    </div>

                    {/* Categoria */}
                    <div className="space-y-1.5">
                        <label className="text-sm font-semibold text-muted">Categoria</label>
                        <CustomSelect
                            value={categoryId}
                            onChange={setCategoryId}
                            options={[
                                { value: '', label: 'Nenhuma (Outros Campos)' },
                                ...categories.map(c => ({ value: c.id, label: c.name }))
                            ]}
                            placeholder="Nenhuma (Outros Campos)"
                        />
                    </div>
                </div>

                {/* Descrição */}
                <div className="space-y-1.5 mt-4">
                    <label className="text-sm font-semibold text-muted">Descrição <span className="text-muted font-normal">(Opcional)</span></label>
                    <textarea
                        rows={2}
                        value={description}
                        onChange={e => setDescription(e.target.value)}
                        placeholder="Exemplo de preenchimento ou ajuda para o usuário"
                        className="w-full p-4 bg-void border border-line rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all resize-none"
                    />
                </div>

                {/* Options (Dynamic) */}
                {needsOptions && (
                    <div className="space-y-3 pt-4 mt-4 border-t border-line">
                        <div className="flex items-center justify-between">
                            <label className="text-sm font-semibold text-muted">Opções de Seleção</label>
                            <button
                                type="button"
                                onClick={handleAddOption}
                                className="text-xs font-semibold text-accent-2 hover:text-accent-2 flex items-center gap-1 bg-panel-2 px-2 py-1 rounded"
                            >
                                <Plus weight="bold" /> Adicionar
                            </button>
                        </div>
                        {options.length === 0 && (
                            <p className="text-xs text-orange-600 font-medium bg-orange-50 p-3 rounded-lg">
                                Adicione ao menos uma opção para este campo.
                            </p>
                        )}
                        <div className="space-y-2">
                            {options.map((opt, idx) => (
                                <div key={idx} className="flex items-center gap-2">
                                    <input
                                        type="text"
                                        value={opt}
                                        onChange={e => handleUpdateOption(idx, e.target.value)}
                                        placeholder={`Opção ${idx + 1}`}
                                        className="flex-1 h-9 px-3 bg-panel border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent"
                                    />
                                    <button
                                        type="button"
                                        onClick={() => handleRemoveOption(idx)}
                                        className="p-2 text-muted hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors"
                                    >
                                        <Trash size={16} />
                                    </button>
                                </div>
                            ))}
                        </div>
                    </div>
                )}

                {/* Actions */}
                <div className="flex items-center justify-between mt-6 pt-4 border-t border-line">
                    <div>
                        {field && onDelete && (
                            <button
                                type="button"
                                onClick={handleDelete}
                                disabled={isDeleting}
                                className="text-sm font-medium text-red-500 hover:text-red-600 transition-colors"
                            >
                                {isDeleting ? 'Excluindo...' : 'Excluir'}
                            </button>
                        )}
                    </div>
                    <div className="flex items-center gap-3">
                        <button
                            type="button"
                            onClick={onCancelEdit}
                            disabled={isSaving}
                            className="px-4 py-2 text-sm font-semibold text-muted hover:text-ink transition-colors"
                        >
                            Cancelar
                        </button>
                        <button
                            type="button"
                            onClick={handleSave}
                            disabled={isSaving || !name.trim() || (needsOptions && options.every(o => !o.trim()))}
                            className="px-5 py-2.5 bg-accent hover:bg-accent text-white text-sm font-medium rounded-xl transition-colors shadow-sm disabled:opacity-50 flex items-center gap-2"
                        >
                            {isSaving ? <SpinnerGap size={18} className="animate-spin" /> : <Check size={18} weight="bold" />}
                            Salvar
                        </button>
                    </div>
                </div>
            </div>
        )
    }

    if (!field) return null

    return (
        <div
            ref={setNodeRef}
            style={style}
            onClick={onStartEdit}
            className={`group flex items-center justify-between px-2 py-4 cursor-pointer hover:bg-void transition-colors ${isDragging ? 'opacity-40 relative z-50 bg-panel shadow-xl border border-accent-line rounded-lg scale-[1.02]' : ''}`}
        >
            <div className="flex items-center gap-2 w-full pr-4">
                <div
                    {...attributes}
                    {...listeners}
                    onClick={(e) => e.stopPropagation()}
                    className={`p-1.5 rounded-md cursor-grab active:cursor-grabbing text-muted hover:text-muted hover:bg-panel-2 ${isDragging ? 'text-accent-2' : 'opacity-0 group-hover:opacity-100'} transition-all`}
                >
                    <DotsSixVertical size={20} weight="bold" />
                </div>
                <div className="flex flex-col gap-1 w-full max-w-[85%]">
                    <div className="flex items-center gap-2">
                        <span className="font-semibold text-ink group-hover:text-accent-2 transition-colors">
                            {field.name}
                        </span>
                        <span className="text-xs text-muted font-medium whitespace-nowrap">
                            ({FIELD_TYPES.find(t => t.value === field.field_type)?.label || field.field_type})
                        </span>
                    </div>
                    {field.schema?.description && (
                        <p className="text-sm text-muted truncate">
                            {field.schema.description}
                        </p>
                    )}
                </div>
            </div>

            <div className="text-muted group-hover:text-accent-2 transition-colors flex items-center gap-2 px-4 whitespace-nowrap">
                <span className="text-xs font-semibold opacity-0 group-hover:opacity-100 transition-opacity">Editar</span>
                <CaretRight size={20} weight="bold" />
            </div>
        </div>
    )
}
