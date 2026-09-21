'use client'

import { useState, useRef, useEffect, useCallback } from 'react'
import { Funnel, X } from '@phosphor-icons/react'
import { format, startOfWeek, endOfWeek } from 'date-fns'
import { useIntegrations, useOrganizationMembers, usePipeline } from '@/hooks'
import Avatar from './Avatar'
import CheckboxRow from './CheckboxRow'
import PeriodSelector, { type DateRangeType } from './PeriodSelector'
import FilterSection from './FilterSection'
import ModalFooter from './ModalFooter'
import './FilterButton.css'

export interface FilterState {
  integrations: string[]
  sellers: string[]
  stages: string[]
  dateRange: {
    type: 'all' | 'today' | 'this_week' | 'this_month' | 'custom'
    startDate?: Date
    endDate?: Date
  }
}

interface FilterButtonProps {
  organizationId: string
  onFilterChange: (filters: FilterState) => void
}

export default function FilterButton({ organizationId, onFilterChange }: FilterButtonProps) {
  const [isOpen, setIsOpen] = useState(false)
  const modalRef = useRef<HTMLDivElement>(null)

  // Fetch data
  const { integrations, loading: integrationsLoading } = useIntegrations(organizationId)
  const { members, loading: membersLoading } = useOrganizationMembers(organizationId)
  const { stages, loading: stagesLoading } = usePipeline(organizationId)

  // Applied filter state
  const [selectedIntegrations, setSelectedIntegrations] = useState<string[]>([])
  const [selectedSellers, setSelectedSellers] = useState<string[]>([])
  const [selectedStages, setSelectedStages] = useState<string[]>([])
  const [selectedDateType, setSelectedDateType] = useState<FilterState['dateRange']['type']>('all')
  const [selectedCustomDates, setSelectedCustomDates] = useState<{ start?: Date; end?: Date }>({})

  // Temporary filter state (while modal is open)
  const [tempIntegrations, setTempIntegrations] = useState<string[]>([])
  const [tempSellers, setTempSellers] = useState<string[]>([])
  const [tempStages, setTempStages] = useState<string[]>([])
  const [tempDateType, setTempDateType] = useState<DateRangeType>('custom')
  const [tempCustomDates, setTempCustomDates] = useState<{ start?: Date; end?: Date }>({})

  // Sync temp state when opening
  useEffect(() => {
    if (isOpen) {
      setTempIntegrations(selectedIntegrations)
      setTempSellers(selectedSellers)
      setTempStages(selectedStages)
      // Map the applied type ('all'|'this_month') -> valid temp type ('today'|'this_week'|'custom')
      const typeMap: Record<string, DateRangeType> = {
        all: 'custom',
        today: 'today',
        this_week: 'this_week',
        this_month: 'custom',
        custom: 'custom',
      }
      setTempDateType(typeMap[selectedDateType] || 'custom')
      setTempCustomDates(selectedCustomDates)
    }
  }, [isOpen, selectedIntegrations, selectedSellers, selectedStages, selectedDateType, selectedCustomDates])

  // Close modal when pressing Escape
  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsOpen(false)
    }
    if (isOpen) {
      document.addEventListener('keydown', handleEsc)
      return () => document.removeEventListener('keydown', handleEsc)
    }
  }, [isOpen])

  const toggleIntegration = (id: string) =>
    setTempIntegrations((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    )

  const toggleSeller = (id: string) =>
    setTempSellers((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    )

  const toggleStage = (id: string) =>
    setTempStages((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    )

  const applyFilters = useCallback(() => {
    setSelectedIntegrations(tempIntegrations)
    setSelectedSellers(tempSellers)
    setSelectedStages(tempStages)
    setSelectedDateType(tempDateType)
    setSelectedCustomDates(tempCustomDates)

    const filters: FilterState = {
      integrations: tempIntegrations,
      sellers: tempSellers,
      stages: tempStages,
      dateRange: {
        type: tempDateType,
        startDate: tempCustomDates.start,
        endDate: tempCustomDates.end,
      },
    }
    onFilterChange(filters)
    setIsOpen(false)
  }, [tempIntegrations, tempSellers, tempStages, tempDateType, tempCustomDates, onFilterChange])

  const clearFilters = useCallback(() => {
    setTempIntegrations([])
    setTempSellers([])
    setTempStages([])
    setTempDateType('custom')
    setTempCustomDates({})
    setSelectedIntegrations([])
    setSelectedSellers([])
    setSelectedStages([])
    setSelectedDateType('all')
    setSelectedCustomDates({})
    onFilterChange({
      integrations: [],
      sellers: [],
      stages: [],
      dateRange: { type: 'all' },
    })
    setIsOpen(false)
  }, [onFilterChange])

  // Build active filter pills
  const getActiveFilters = () => {
    const filters: Array<{
      type: 'integration' | 'seller' | 'stage' | 'date'
      label: string
      value?: string
    }> = []

    if (selectedIntegrations.length === integrations.length && integrations.length > 0) {
      filters.push({ type: 'integration', label: 'TODOS OS CANAIS' })
    } else {
      selectedIntegrations.forEach((id) => {
        const i = integrations.find((x) => x.id === id)
        if (i) filters.push({ type: 'integration', label: i.name.toUpperCase(), value: id })
      })
    }

    selectedSellers.forEach((id) => {
      const m = members.find((x) => x.id === id)
      if (m) filters.push({ type: 'seller', label: m.profiles.full_name.toUpperCase(), value: id })
    })

    selectedStages.forEach((id) => {
      const s = stages.find((x) => x.id === id)
      if (s) filters.push({ type: 'stage', label: s.name.toUpperCase(), value: id })
    })

    if (selectedDateType !== 'all') {
      if (selectedDateType === 'custom' && selectedCustomDates.start && selectedCustomDates.end) {
        filters.push({
          type: 'date',
          label: `${format(selectedCustomDates.start, 'dd/MM/yyyy')} A ${format(selectedCustomDates.end, 'dd/MM/yyyy')}`,
        })
      } else if (selectedDateType === 'today') {
        filters.push({ type: 'date', label: 'HOJE' })
      } else if (selectedDateType === 'this_week') {
        filters.push({ type: 'date', label: 'ESTA SEMANA' })
      }
    }

    return filters
  }

  const removeActiveFilter = (type: 'integration' | 'seller' | 'stage' | 'date', value?: string) => {
    if (type === 'integration' && value) {
      const upd = selectedIntegrations.filter((id) => id !== value)
      setSelectedIntegrations(upd)
      onFilterChange({ integrations: upd, sellers: selectedSellers, stages: selectedStages, dateRange: { type: selectedDateType, ...selectedCustomDates } })
    } else if (type === 'seller' && value) {
      const upd = selectedSellers.filter((id) => id !== value)
      setSelectedSellers(upd)
      onFilterChange({ integrations: selectedIntegrations, sellers: upd, stages: selectedStages, dateRange: { type: selectedDateType, ...selectedCustomDates } })
    } else if (type === 'stage' && value) {
      const upd = selectedStages.filter((id) => id !== value)
      setSelectedStages(upd)
      onFilterChange({ integrations: selectedIntegrations, sellers: selectedSellers, stages: upd, dateRange: { type: selectedDateType, ...selectedCustomDates } })
    } else if (type === 'date') {
      setSelectedDateType('all')
      setSelectedCustomDates({})
      onFilterChange({ integrations: selectedIntegrations, sellers: selectedSellers, stages: selectedStages, dateRange: { type: 'all' } })
    }
  }

  const activeFilters = getActiveFilters()

  return (
    <>
      {/* Trigger button + active filter chips */}
      <div className="flex items-center gap-3 flex-wrap">
        <button
          onClick={() => setIsOpen(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-accent text-white rounded-lg text-sm font-medium hover:bg-accent-2 active:bg-accent-2 transition-all shadow-sm"
        >
          <Funnel size={16} weight="fill" />
          Filtrar
        </button>

        {activeFilters.map((filter, idx) => (
          <div
            key={idx}
            className="group flex items-center gap-1.5 px-3 py-1.5 bg-panel-2 border border-accent-line text-accent-2 rounded-full text-xs font-bold hover:border-accent transition-all cursor-pointer"
          >
            <span className="whitespace-nowrap">{filter.label}</span>
            <button
              onClick={(e) => {
                e.stopPropagation()
                removeActiveFilter(filter.type, filter.value)
              }}
              className="opacity-0 group-hover:opacity-100 hover:bg-panel rounded-full p-0.5 transition-all"
            >
              <X size={12} weight="bold" />
            </button>
          </div>
        ))}
      </div>

      {/* Modal overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center pt-20 px-4"
          style={{ backgroundColor: 'rgba(2, 3, 6, 0.5)', backdropFilter: 'blur(2px)' }}
          onClick={(e) => {
            if (e.target === e.currentTarget) setIsOpen(false)
          }}
        >
          <div
            ref={modalRef}
            className="bg-panel border border-line rounded-2xl shadow-2xl w-full max-w-[1100px] overflow-hidden filter-modal-enter"
          >
            {/* ===== GRID: 4 columns (Custom widths for calendar space) ===== */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-[0.8fr_1.4fr_1fr_0.8fr] p-8 pb-6 gap-y-6">
              {/* ── COL 1: CANAIS ── */}
              <div className="lg:pr-6 lg:border-r lg:border-line">
                <FilterSection title="Canais">
                  <div className="space-y-0.5">
                    {integrationsLoading ? (
                      <p className="text-sm text-muted animate-pulse">Carregando...</p>
                    ) : integrations.length === 0 ? (
                      <div className="py-4 text-center">
                        <p className="text-sm text-muted">Nenhum canal configurado</p>
                        <p className="text-xs text-accent-2 mt-1 cursor-pointer hover:underline">
                          + Adicionar canal
                        </p>
                      </div>
                    ) : (
                      integrations.map((integration) => (
                        <CheckboxRow
                          key={integration.id}
                          label={integration.name}
                          checked={tempIntegrations.includes(integration.id)}
                          onChange={() => toggleIntegration(integration.id)}
                        />
                      ))
                    )}
                  </div>
                </FilterSection>
              </div>

              {/* ── COL 2: PERÍODO ── */}
              <div className="lg:px-6 lg:border-r lg:border-line">
                <FilterSection title="Período">
                  <PeriodSelector
                    selectedType={tempDateType}
                    startDate={tempCustomDates.start}
                    endDate={tempCustomDates.end}
                    onTypeChange={setTempDateType}
                    onRangeChange={(start, end) => setTempCustomDates({ start, end })}
                  />
                </FilterSection>
              </div>

              {/* ── COL 3: VENDEDOR ── */}
              <div className="lg:px-6 lg:border-r lg:border-line">
                <FilterSection title="Vendedor">
                  <div className="space-y-0.5">
                    {membersLoading ? (
                      <p className="text-sm text-muted animate-pulse">Carregando...</p>
                    ) : members.length === 0 ? (
                      <div className="py-4 text-center">
                        <p className="text-sm text-muted">Nenhum vendedor cadastrado</p>
                        <p className="text-xs text-accent-2 mt-1 cursor-pointer hover:underline">
                          + Cadastrar vendedor
                        </p>
                      </div>
                    ) : (
                      members.map((member) => (
                        <CheckboxRow
                          key={member.id}
                          label={member.profiles.full_name}
                          checked={tempSellers.includes(member.id)}
                          onChange={() => toggleSeller(member.id)}
                          icon={
                            <Avatar
                              name={member.profiles.full_name}
                              imageUrl={member.profiles.avatar_url}
                              size="sm"
                            />
                          }
                        />
                      ))
                    )}
                  </div>
                </FilterSection>
              </div>

              {/* ── COL 4: STATUS ── */}
              <div className="lg:pl-6">
                <FilterSection title="Status">
                  <div className="space-y-0.5">
                    {stagesLoading ? (
                      <p className="text-sm text-gray-400 animate-pulse">Carregando...</p>
                    ) : stages.length === 0 ? (
                      <div className="py-4 text-center">
                        <p className="text-sm text-gray-400">Pipeline sem estágios</p>
                      </div>
                    ) : (
                      stages.map((stage) => (
                        <CheckboxRow
                          key={stage.id}
                          label={stage.name}
                          checked={tempStages.includes(stage.id)}
                          onChange={() => toggleStage(stage.id)}
                        />
                      ))
                    )}
                  </div>
                </FilterSection>
              </div>
            </div>

            {/* ===== FOOTER ===== */}
            <ModalFooter onClear={clearFilters} onApply={applyFilters} />
          </div>
        </div>
      )}
    </>
  )
}
