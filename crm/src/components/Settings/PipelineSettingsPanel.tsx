'use client'

import { useState, useEffect, useRef } from 'react'
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
    useSortable
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { Plus, Trash, DotsSixVertical, DotsThreeVertical, CaretDown, X } from '@phosphor-icons/react'
import { Pipeline, PipelineStage } from '@/lib/types'
import { useAuth, usePipeline } from '@/hooks'
import { getStageColor, STAGE_COLORS } from '@/lib/stageColors'

// Embedded Sortable Item for Stages
function SortableStageItem({
    stage,
    isGoalsEnabled,
    onUpdateGoalLocal,
    onDelete,
    onUpdateNameLocal,
    onUpdateColorLocal,
    onSaveStage
}: {
    stage: PipelineStage
    isGoalsEnabled: boolean
    onUpdateGoalLocal: (id: string, goal: number) => void
    onUpdateNameLocal: (id: string, name: string) => void
    onUpdateColorLocal: (id: string, color: string) => void
    onSaveStage: (id: string, overrides?: Partial<PipelineStage>) => void
    onDelete: (id: string) => void
}) {
    const {
        attributes,
        listeners,
        setNodeRef,
        transform,
        transition,
        isDragging
    } = useSortable({ id: stage.id })

    const [isColorPickerOpen, setIsColorPickerOpen] = useState(false)

    const style = {
        transform: CSS.Transform.toString(transform),
        transition,
        zIndex: isDragging ? 10 : (isColorPickerOpen ? 50 : 1),
    }

    return (
        <div
            ref={setNodeRef}
            style={style}
            className={`flex items-center justify-between p-3 mb-3 bg-white border rounded-xl shadow-sm transition-shadow ${isDragging ? 'shadow-md border-blue-300' : 'border-gray-200'}`}
        >
            <div className="flex items-center gap-3 flex-1">
                <div {...attributes} {...listeners} className="cursor-grab hover:text-blue-600 text-gray-400 p-1">
                    <DotsSixVertical size={20} weight="bold" />
                </div>

                {/* Custom Color Selector Popup */}
                <div className="relative">
                    <button
                        type="button"
                        onClick={() => setIsColorPickerOpen(!isColorPickerOpen)}
                        className="w-6 h-6 rounded-md border-0 p-0 cursor-pointer flex-shrink-0 appearance-none hover:ring-2 hover:ring-blue-100 transition-all outline-none flex items-center justify-center relative cursor-pointer"
                        title="Escolher cor da etapa"
                    >
                        {/* Inner visual block to represent color */}
                        <div
                            className="w-full h-full rounded shadow-[inset_0_2px_4px_rgba(0,0,0,0.1)]"
                            style={{ backgroundColor: stage.color || getStageColor(stage.rank).bar }}
                        />
                    </button>

                    {isColorPickerOpen && (
                        <>
                            {/* Invisible overlay to close on click outside */}
                            <div
                                className="fixed inset-0 z-40"
                                onClick={() => setIsColorPickerOpen(false)}
                            />

                            {/* Color picker dropdown */}
                            <div className="absolute top-10 left-0 z-50 bg-white border border-gray-200 rounded-xl shadow-lg p-3 w-48 flex flex-wrap gap-2 animate-in fade-in slide-in-from-top-2 duration-200">
                                {STAGE_COLORS.map((c, i) => (
                                    <button
                                        key={c.bar}
                                        type="button"
                                        onClick={() => {
                                            onUpdateColorLocal(stage.id, c.bar)
                                            onSaveStage(stage.id, { color: c.bar })
                                            setIsColorPickerOpen(false)
                                        }}
                                        className="w-8 h-8 rounded-full border border-gray-200 hover:scale-110 transition-transform shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                                        style={{ backgroundColor: c.bar }}
                                        title={`Cor ${i + 1}`}
                                    />
                                ))}
                            </div>
                        </>
                    )}
                </div>

                <input
                    type="text"
                    value={stage.name}
                    onChange={(e) => onUpdateNameLocal(stage.id, e.target.value)}
                    onBlur={() => onSaveStage(stage.id)}
                    className="font-bold text-gray-900 bg-transparent border border-transparent rounded-lg py-1.5 px-3 flex-1 min-w-0 hover:bg-gray-50 focus:bg-white focus:border-blue-300 focus:ring-2 focus:ring-blue-100 transition-all outline-none"
                />

                {isGoalsEnabled && (
                    <div className="flex items-center gap-2 mr-4 bg-gray-50 px-2 py-1 rounded-lg border border-gray-200">
                        <span className="text-xs font-semibold text-gray-500 uppercase tracking-widest">Meta</span>
                        <input
                            type="number"
                            min="0"
                            value={stage.target_volume || 0}
                            onChange={(e) => onUpdateGoalLocal(stage.id, parseInt(e.target.value) || 0)}
                            onBlur={() => onSaveStage(stage.id)}
                            className="w-16 bg-transparent border-none focus:ring-0 p-0 text-right font-medium text-gray-900"
                        />
                    </div>
                )}
            </div>

            <button
                onClick={() => onDelete(stage.id)}
                className="text-gray-400 hover:text-red-600 p-2 transition-colors"
            >
                <Trash size={20} />
            </button>
        </div>
    )
}


export default function PipelineSettingsPanel() {
    const { organizationId } = useAuth()
    const {
        pipelines,
        stages,
        selectedPipelineId,
        selectPipeline,
        loading,
        createPipeline,
        updatePipeline,
        deletePipeline,
        updatePipelineSettings,
        createStage,
        updateStage,
        deleteStage,
        reorderStages
    } = usePipeline(organizationId || '')

    const [localStages, setLocalStages] = useState<PipelineStage[]>([])
    const [activePipeline, setActivePipeline] = useState<Pipeline | null>(null)
    const [errorMsg, setErrorMsg] = useState<string | null>(null)
    const [isCreatingPipeline, setIsCreatingPipeline] = useState(false)
    const [newPipelineName, setNewPipelineName] = useState('')
    const [isDropdownOpen, setIsDropdownOpen] = useState(false)
    const [isRottenDropdownOpen, setIsRottenDropdownOpen] = useState(false)
    const [isEditingPipelineName, setIsEditingPipelineName] = useState(false)
    const [editPipelineName, setEditPipelineName] = useState('')
    const [isPipelineMenuOpen, setIsPipelineMenuOpen] = useState(false)
    const exceptionsEndRef = useRef<HTMLDivElement>(null)

    useEffect(() => {
        if (isRottenDropdownOpen) {
            setTimeout(() => {
                exceptionsEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
            }, 200)
        }
    }, [isRottenDropdownOpen])

    // Sync local state when selected pipeline/stages change
    useEffect(() => {
        setLocalStages(stages)
        if (selectedPipelineId) {
            const pipe = pipelines.find(p => p.id === selectedPipelineId) || null
            setActivePipeline(pipe)
        }
    }, [stages, selectedPipelineId, pipelines])

    const sensors = useSensors(
        useSensor(PointerSensor, {
            activationConstraint: { distance: 8 },
        }),
        useSensor(KeyboardSensor, {
            coordinateGetter: sortableKeyboardCoordinates,
        })
    )

    const handleDragEnd = async (event: DragEndEvent) => {
        const { active, over } = event

        if (active.id !== over?.id && selectedPipelineId) {
            let newlyOrderedStages: PipelineStage[] = []

            setLocalStages((items) => {
                const oldIndex = items.findIndex((i) => i.id === active.id)
                const newIndex = items.findIndex((i) => i.id === over?.id)

                const newOrder = arrayMove(items, oldIndex, newIndex)
                newlyOrderedStages = newOrder.map((stage, index) => ({ ...stage, rank: index * 10 }))
                return newlyOrderedStages
            })

            try {
                await reorderStages(selectedPipelineId, newlyOrderedStages)
            } catch (err: any) {
                setErrorMsg(err.message || 'Erro ao reordenar etapas.')
            }
        }
    }

    const handleCreatePipeline = async () => {
        if (!newPipelineName.trim()) return
        try {
            await createPipeline(newPipelineName.trim())
            setIsCreatingPipeline(false)
            setNewPipelineName('')
        } catch (err: any) {
            setErrorMsg(err.message || 'Erro ao criar pipeline.')
        }
    }

    const handleSavePipelineName = async () => {
        if (!activePipeline || !editPipelineName.trim() || editPipelineName.trim() === activePipeline.name) {
            setIsEditingPipelineName(false)
            return
        }
        try {
            await updatePipeline(activePipeline.id, { name: editPipelineName.trim() })
            setIsEditingPipelineName(false)
        } catch (err: any) {
            setErrorMsg(err.message || 'Erro ao atualizar pipeline.')
        }
    }

    const handleDeletePipeline = async () => {
        if (!activePipeline) return
        if (!window.confirm(`Tem certeza que deseja excluir o pipeline "${activePipeline.name}"?`)) return

        try {
            await deletePipeline(activePipeline.id)
            setIsPipelineMenuOpen(false)
        } catch (err: any) {
            setErrorMsg(err.message || 'Erro ao excluir pipeline.')
        }
    }

    const handleCreateStage = async () => {
        if (!selectedPipelineId) return
        try {
            await createStage(selectedPipelineId, 'Nova Etapa')
        } catch (err: any) {
            setErrorMsg(err.message || 'Erro ao criar etapa.')
        }
    }

    const handleDeleteStage = async (id: string) => {
        if (!selectedPipelineId) return
        try {
            await deleteStage(id, selectedPipelineId)
            setErrorMsg(null)
        } catch (err: any) {
            setErrorMsg(err.message || 'Erro ao excluir etapa.')
        }
    }

    const handleUpdateNameLocal = (id: string, name: string) => {
        setLocalStages(prev => prev.map(s => s.id === id ? { ...s, name } : s))
    }

    const handleUpdateColorLocal = (id: string, color: string) => {
        setLocalStages(prev => prev.map(s => s.id === id ? { ...s, color } : s))
    }

    const handleUpdateGoalLocal = (id: string, target_volume: number) => {
        setLocalStages(prev => prev.map(s => s.id === id ? { ...s, target_volume } : s))
    }

    const handleSaveStage = async (id: string, overrides?: Partial<PipelineStage>) => {
        if (!selectedPipelineId) return
        const stage = localStages.find(s => s.id === id)
        if (!stage) return

        try {
            await updateStage(id, selectedPipelineId, {
                name: overrides?.name ?? stage.name,
                color: overrides?.color ?? stage.color,
                target_volume: overrides?.target_volume ?? stage.target_volume
            })
        } catch (err: any) {
            setErrorMsg(err.message || 'Erro ao atualizar etapa.')
        }
    }

    const toggleGoals = async () => {
        if (!selectedPipelineId || !activePipeline) return
        const currentSettings = activePipeline.settings || {}
        await updatePipelineSettings(selectedPipelineId, { ...currentSettings, goals_enabled: !currentSettings.goals_enabled })
    }

    const toggleRotten = async () => {
        if (!selectedPipelineId || !activePipeline) return
        const currentSettings = activePipeline.settings || {}
        await updatePipelineSettings(selectedPipelineId, { ...currentSettings, rotten_enabled: !currentSettings.rotten_enabled })
    }

    const rottenExceptions: string[] = activePipeline?.settings?.rotten_exceptions || []

    const addRottenException = async (stageId: string) => {
        if (!selectedPipelineId || !activePipeline || !stageId) return
        const currentSettings = activePipeline.settings || {}
        const currentExceptions = currentSettings.rotten_exceptions || []

        if (!currentExceptions.includes(stageId)) {
            await updatePipelineSettings(selectedPipelineId, {
                ...currentSettings,
                rotten_exceptions: [...currentExceptions, stageId]
            })
        }
    }

    const removeRottenException = async (stageId: string) => {
        if (!selectedPipelineId || !activePipeline) return
        const currentSettings = activePipeline.settings || {}
        const currentExceptions = currentSettings.rotten_exceptions || []

        await updatePipelineSettings(selectedPipelineId, {
            ...currentSettings,
            rotten_exceptions: currentExceptions.filter((id: string) => id !== stageId)
        })
    }

    if (loading) return <div className="animate-pulse flex space-x-4"><div className="flex-1 space-y-4 py-1"><div className="h-4 bg-gray-200 rounded w-3/4"></div><div className="space-y-2"><div className="h-4 bg-gray-200 rounded"></div><div className="h-4 bg-gray-200 rounded w-5/6"></div></div></div></div>

    const isGoalsEnabled = activePipeline?.settings?.goals_enabled || false
    const isRottenEnabled = activePipeline?.settings?.rotten_enabled || false

    return (
        <div className="space-y-10">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-gray-900 pb-1">Configurações do Pipeline</h1>
                <p className="text-sm text-gray-500">Gerencie as etapas e o fluxo do seu processo comercial.</p>
            </div>

            {/* Select Pipeline Area */}
            <div className="space-y-3">
                <label className="text-xs font-bold text-gray-500 uppercase tracking-widest">Selecionar Pipeline</label>

                <div className={`flex flex-col bg-white border ${isDropdownOpen ? 'border-blue-600 shadow-sm' : 'border-gray-200'} rounded-xl overflow-hidden transition-colors`}>
                    {/* Header */}
                    <div className="w-full flex items-center bg-white z-20 pr-2">
                        {isEditingPipelineName ? (
                            <div className="flex-1 flex items-center px-4 py-2">
                                <input
                                    type="text"
                                    autoFocus
                                    value={editPipelineName}
                                    onChange={(e) => setEditPipelineName(e.target.value)}
                                    onKeyDown={(e) => e.key === 'Enter' && handleSavePipelineName()}
                                    onBlur={handleSavePipelineName}
                                    className="w-full font-semibold text-gray-900 bg-gray-50 border border-blue-300 rounded-lg py-1.5 px-3 focus:outline-none focus:ring-2 focus:ring-blue-100"
                                />
                            </div>
                        ) : (
                            <button
                                onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                                className="flex-1 flex items-center justify-between px-4 py-3 text-gray-900 font-semibold focus:outline-none cursor-pointer text-left"
                            >
                                <span>{activePipeline?.name || 'Selecione um pipeline'}</span>
                                <CaretDown className={`text-gray-400 transition-transform duration-200 ${isDropdownOpen ? 'rotate-180 text-blue-600' : ''}`} size={20} />
                            </button>
                        )}

                        {!isEditingPipelineName && activePipeline && (
                            <div className="relative flex-shrink-0 ml-1">
                                <button
                                    onClick={() => setIsPipelineMenuOpen(!isPipelineMenuOpen)}
                                    className="p-2 text-gray-400 hover:text-gray-900 rounded-lg hover:bg-gray-100 transition-colors"
                                    title="Opções do Pipeline"
                                >
                                    <DotsThreeVertical size={20} weight="bold" />
                                </button>

                                {isPipelineMenuOpen && (
                                    <>
                                        <div
                                            className="fixed inset-0 z-40"
                                            onClick={() => setIsPipelineMenuOpen(false)}
                                        />
                                        <div className="absolute right-0 top-full mt-1 z-50 bg-white border border-gray-200 rounded-xl shadow-lg w-48 py-1 animate-in fade-in slide-in-from-top-2 duration-200">
                                            <button
                                                onClick={() => {
                                                    setEditPipelineName(activePipeline.name)
                                                    setIsEditingPipelineName(true)
                                                    setIsPipelineMenuOpen(false)
                                                }}
                                                className="w-full text-left px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50 hover:text-blue-600 transition-colors font-medium"
                                            >
                                                Editar nome
                                            </button>
                                            <button
                                                onClick={handleDeletePipeline}
                                                className="w-full text-left px-4 py-2.5 text-sm text-red-600 hover:bg-red-50 transition-colors font-medium"
                                            >
                                                Excluir pipeline
                                            </button>
                                        </div>
                                    </>
                                )}
                            </div>
                        )}
                    </div>

                    {/* Expandable Options Area (Inline) */}
                    <div className={`grid transition-all duration-200 ease-in-out ${isDropdownOpen ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0'}`}>
                        <div className="overflow-hidden">
                            <div className="flex flex-col border-t border-gray-100">
                                {pipelines.map(p => (
                                    <button
                                        key={p.id}
                                        onClick={() => {
                                            selectPipeline(p.id)
                                            setIsDropdownOpen(false)
                                        }}
                                        className={`w-full text-left px-4 py-3 hover:bg-blue-600 hover:text-white transition-colors flex items-center justify-between ${p.id === selectedPipelineId ? 'bg-blue-600 text-white font-semibold' : 'bg-white text-gray-700'}`}
                                    >
                                        {p.name}
                                    </button>
                                ))}

                                {isCreatingPipeline ? (
                                    <div className="flex items-center gap-2 p-3 border-t border-dashed border-gray-200 bg-gray-50">
                                        <input
                                            type="text"
                                            autoFocus
                                            value={newPipelineName}
                                            onChange={e => setNewPipelineName(e.target.value)}
                                            onKeyDown={e => e.key === 'Enter' && handleCreatePipeline()}
                                            placeholder="Nome do pipeline..."
                                            className="flex-1 bg-white border border-gray-200 rounded-lg px-3 py-2 text-sm text-gray-900 focus:ring-2 focus:ring-blue-600 focus:outline-none shadow-sm"
                                        />
                                        <button onClick={handleCreatePipeline} className="px-3 py-2 bg-blue-600 text-white text-sm font-bold rounded-lg hover:bg-blue-700 transition-colors">
                                            Salvar
                                        </button>
                                        <button onClick={() => setIsCreatingPipeline(false)} className="p-2 text-gray-400 hover:text-gray-600">
                                            <X size={16} />
                                        </button>
                                    </div>
                                ) : (
                                    <button
                                        onClick={() => setIsCreatingPipeline(true)}
                                        className="w-full py-3 px-4 border-t border-dashed border-gray-200 bg-white text-blue-600 font-semibold hover:bg-blue-50 transition-colors flex items-center justify-center gap-2"
                                    >
                                        <Plus weight="bold" /> Adicionar pipeline
                                    </button>
                                )}
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {errorMsg && (
                <div className="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded-lg flex items-center justify-between">
                    <span className="text-sm font-medium">{errorMsg}</span>
                    <button onClick={() => setErrorMsg(null)}><X weight="bold" /></button>
                </div>
            )}

            {activePipeline && (
                <>
                    {/* Stages List */}
                    <div className="space-y-3">
                        <div className="flex justify-between items-end mb-4">
                            <h2 className="text-base font-bold text-gray-900">Etapas do Funil</h2>
                            <span className="text-xs font-bold text-gray-400 uppercase tracking-widest">Arraste para reordenar</span>
                        </div>

                        <DndContext
                            sensors={sensors}
                            collisionDetection={closestCenter}
                            onDragEnd={handleDragEnd}
                        >
                            <SortableContext
                                items={localStages.map(s => s.id)}
                                strategy={verticalListSortingStrategy}
                            >
                                <div className="flex flex-col gap-3">
                                    {localStages.map(stage => (
                                        <SortableStageItem
                                            key={stage.id}
                                            stage={stage}
                                            isGoalsEnabled={isGoalsEnabled}
                                            onUpdateGoalLocal={handleUpdateGoalLocal}
                                            onUpdateNameLocal={handleUpdateNameLocal}
                                            onUpdateColorLocal={handleUpdateColorLocal}
                                            onSaveStage={handleSaveStage}
                                            onDelete={handleDeleteStage}
                                        />
                                    ))}
                                </div>
                            </SortableContext>
                        </DndContext>

                        <button onClick={handleCreateStage} className="w-full py-4 mt-2 border-2 border-dashed border-gray-200 rounded-xl text-blue-600 font-semibold hover:bg-blue-50 hover:border-blue-300 transition-colors flex items-center justify-center gap-2">
                            <Plus weight="bold" /> Adicionar nova etapa
                        </button>
                    </div>

                    {/* General Settings */}
                    <div className="space-y-4">
                        <h2 className="text-xs font-bold text-gray-500 uppercase tracking-widest mb-4">Configurações Gerais do Pipeline</h2>

                        <div className="bg-white border border-gray-200 rounded-xl shadow-sm divide-y divide-gray-100 overflow-hidden">
                            {/* Meta de Leads */}
                            <div className="p-5 flex items-center justify-between">
                                <div>
                                    <h3 className="font-bold text-gray-900">Meta de leads por etapa do funil</h3>
                                    <p className="text-sm text-gray-500">Defina objetivos de volume para cada estágio.</p>
                                </div>
                                <button
                                    onClick={toggleGoals}
                                    className={`w-12 h-6 rounded-full transition-colors relative ${isGoalsEnabled ? 'bg-blue-600' : 'bg-gray-200'}`}
                                >
                                    <span className={`absolute top-1 left-1 bg-white w-4 h-4 rounded-full transition-transform ${isGoalsEnabled ? 'translate-x-6' : 'translate-x-0'}`} />
                                </button>
                            </div>

                            {/* Rotten */}
                            <div className="p-5">
                                <div className="flex items-center justify-between mb-4">
                                    <div>
                                        <h3 className="font-bold text-gray-900">Rotatividade de Leads (Rotten)</h3>
                                        <p className="text-sm text-gray-500">Alertar leads parados por mais de 5 dias.</p>
                                    </div>
                                    <button
                                        onClick={toggleRotten}
                                        className={`w-12 h-6 rounded-full transition-colors relative ${isRottenEnabled ? 'bg-blue-600' : 'bg-gray-200'}`}
                                    >
                                        <span className={`absolute top-1 left-1 bg-white w-4 h-4 rounded-full transition-transform ${isRottenEnabled ? 'translate-x-6' : 'translate-x-0'}`} />
                                    </button>
                                </div>

                                {isRottenEnabled && (
                                    <div className="pt-2 animate-in fade-in slide-in-from-top-2 duration-300">
                                        <label className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-2 block">Etapas de exceção (onde não será ativado)</label>
                                        <div className="flex items-center gap-2 flex-wrap p-2 border border-gray-200 rounded-lg bg-gray-50 min-h-[46px]">
                                            {rottenExceptions.map(stageId => {
                                                const stage = localStages.find(s => s.id === stageId)
                                                if (!stage) return null
                                                return (
                                                    <div key={stageId} className="flex items-center gap-1 bg-white border border-gray-200 text-sm font-medium px-2 py-1 rounded-md shadow-sm">
                                                        <span className="w-2 h-2 rounded-full" style={{ backgroundColor: stage.color || getStageColor(stage.rank).bar }} />
                                                        {stage.name}
                                                        <button
                                                            onClick={() => removeRottenException(stageId)}
                                                            className="text-gray-400 hover:text-red-600 focus:outline-none ml-1 transition-colors"
                                                            title="Remover exceção"
                                                        >
                                                            <X size={12} weight="bold" />
                                                        </button>
                                                    </div>
                                                )
                                            })}

                                            <div className="relative">
                                                <button
                                                    onClick={() => setIsRottenDropdownOpen(!isRottenDropdownOpen)}
                                                    className="flex items-center gap-1 text-sm py-1.5 px-2 text-blue-600 font-medium hover:text-accent-2 transition-colors focus:outline-none"
                                                >
                                                    <span>+ Adicionar Exceção</span>
                                                    <CaretDown weight="bold" className={`transition-transform duration-200 ${isRottenDropdownOpen ? 'rotate-180' : ''}`} />
                                                </button>

                                                {isRottenDropdownOpen && (
                                                    <div
                                                        className="fixed inset-0 z-40"
                                                        onClick={() => setIsRottenDropdownOpen(false)}
                                                    />
                                                )}

                                                <div
                                                    className={`grid transition-[grid-template-rows] duration-200 ease-out w-full ${isRottenDropdownOpen ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}
                                                >
                                                    <div className="overflow-hidden w-full -mx-1 px-1">
                                                        <div className="mt-2 w-full bg-white border border-gray-200 rounded-xl shadow-sm py-1">
                                                            {localStages.filter(s => !rottenExceptions.includes(s.id)).length === 0 ? (
                                                                <div className="px-4 py-3 text-sm text-gray-500 text-center">Nenhuma etapa disponível</div>
                                                            ) : (
                                                                localStages
                                                                    .filter(s => !rottenExceptions.includes(s.id))
                                                                    .map(s => (
                                                                        <button
                                                                            key={s.id}
                                                                            onClick={() => {
                                                                                addRottenException(s.id)
                                                                                setIsRottenDropdownOpen(false)
                                                                            }}
                                                                            className="w-full text-left px-4 py-2.5 text-sm text-gray-700 hover:bg-blue-50 hover:text-blue-600 transition-colors flex items-center gap-2 relative z-50"
                                                                        >
                                                                            <span className="w-2 h-2 rounded-full" style={{ backgroundColor: s.color || getStageColor(s.rank).bar }} />
                                                                            <span className="truncate">{s.name}</span>
                                                                        </button>
                                                                    ))
                                                            )}
                                                        </div>
                                                        <div ref={exceptionsEndRef} className="h-8 bg-transparent" />
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                )}
                            </div>
                        </div>
                    </div>
                </>
            )}
        </div>
    )
}
