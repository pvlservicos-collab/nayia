import { useState, useEffect, useMemo } from 'react'
import { CustomFieldCategory, CustomFieldDefinition } from '@/lib/types'
import { FieldItem } from './FieldItem'

import {
    DndContext,
    closestCenter,
    KeyboardSensor,
    PointerSensor,
    useSensor,
    useSensors,
    DragEndEvent,
} from '@dnd-kit/core'
import {
    arrayMove,
    SortableContext,
    sortableKeyboardCoordinates,
    verticalListSortingStrategy,
} from '@dnd-kit/sortable'

interface CategoryCardProps {
    category: CustomFieldCategory
    fields: CustomFieldDefinition[]
    allCategories: CustomFieldCategory[]
    editingFieldId: string | null
    onEditCategory: () => void
    onStartEditField: (fieldId: string) => void
    onCancelEditField: () => void
    onSaveField: (id: string, data: any) => Promise<void>
    onDeleteField: (id: string) => Promise<void>
    onReorderFields: (updates: { id: string, rank: number }[]) => Promise<void>
    isFallback?: boolean
}

export function CategoryCard({
    category,
    fields,
    allCategories,
    editingFieldId,
    onEditCategory,
    onStartEditField,
    onCancelEditField,
    onSaveField,
    onDeleteField,
    onReorderFields,
    isFallback
}: CategoryCardProps) {
    const isAddingNewHere = editingFieldId === `new-${category.id}`

    // Optimistic state for drag and drop
    const [localFields, setLocalFields] = useState(fields)

    // Sync when props change (from DB sync or parent updates)
    useEffect(() => {
        setLocalFields(fields)
    }, [fields])

    const [isMounted, setIsMounted] = useState(false)
    useEffect(() => {
        setIsMounted(true)
    }, [])

    const sensors = useSensors(
        useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
        useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
    )

    const itemIds = useMemo(() => localFields.map(f => f.id), [localFields])

    const handleDragEnd = (event: DragEndEvent) => {
        const { active, over } = event
        if (!over || active.id === over.id) return

        // Cannot drag if we are currently editing inline to avoid layout jumps
        if (editingFieldId) return

        setLocalFields((items) => {
            const oldIndex = items.findIndex(item => item.id === active.id)
            const newIndex = items.findIndex(item => item.id === over.id)
            const newItems = arrayMove(items, oldIndex, newIndex)

            // Fire save update to parent using spaced out ranks, outside of the render cycle
            const updates = newItems.map((item, index) => ({ id: item.id, rank: index * 1000 + 1000 }))
            setTimeout(() => onReorderFields(updates), 0)

            return newItems
        })
    }

    return (
        <div className="mb-8">
            {/* Category Header */}
            <div className="flex items-center justify-between mb-3 px-2">
                <div className="flex items-center gap-3">
                    <h2 className="text-sm font-bold text-muted uppercase tracking-wider font-display">
                        {category.name}
                    </h2>
                    {!isFallback && (
                        <button
                            onClick={onEditCategory}
                            className="text-muted hover:text-accent-2 transition-colors text-xs"
                        >
                            Editar
                        </button>
                    )}
                </div>
                <div className="flex items-center gap-4">
                    <span className="text-xs font-semibold text-muted bg-panel-2 px-2 py-0.5 rounded-full">
                        {localFields.length} {localFields.length === 1 ? 'CAMPO' : 'CAMPOS'}
                    </span>
                </div>
            </div>

            {/* Fields List */}
            <div className="bg-panel rounded-xl border border-line overflow-hidden shadow-sm">
                {(localFields.length === 0 && !isAddingNewHere) ? (
                    <div className="px-6 py-8 text-center text-sm text-muted">
                        Nenhum campo nesta categoria.
                    </div>
                ) : !isMounted ? (
                    <div className="px-6 py-8 text-center text-sm text-muted">
                        Carregando campos...
                    </div>
                ) : (
                    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
                        <SortableContext items={itemIds} strategy={verticalListSortingStrategy}>
                            <div className="divide-y divide-line flex flex-col">
                                {localFields.map((field) => (
                                    <FieldItem
                                        key={field.id}
                                        field={field}
                                        categories={allCategories}
                                        isEditing={editingFieldId === field.id}
                                        onStartEdit={() => onStartEditField(field.id)}
                                        onCancelEdit={onCancelEditField}
                                        onSave={(data: any) => onSaveField(field.id, data)}
                                        onDelete={() => onDeleteField(field.id)}
                                    />
                                ))}

                                {isAddingNewHere && (
                                    <div className="animate-in fade-in slide-in-from-top-2 duration-300">
                                        <FieldItem
                                            categories={allCategories}
                                            isEditing={true}
                                            defaultCategoryId={isFallback ? undefined : category.id}
                                            onCancelEdit={onCancelEditField}
                                            onSave={(data: any) => onSaveField('new', data)}
                                        />
                                    </div>
                                )}
                            </div>
                        </SortableContext>
                    </DndContext>
                )}

                {/* Add new field to THIS category */}
                {!isAddingNewHere && (
                    <div className="bg-void px-6 py-3 border-t border-line">
                        <button
                            onClick={() => onStartEditField(`new-${category.id}`)}
                            className="text-sm font-semibold text-accent-2 hover:text-accent-2 transition-colors"
                        >
                            + Adicionar campo
                        </button>
                    </div>
                )}
            </div>
        </div>
    )
}
