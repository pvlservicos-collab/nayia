'use client'

import { useState } from 'react'
import { Funnel, X } from '@phosphor-icons/react'

interface FilterChip {
  id: string
  label: string
}

const DEFAULT_FILTERS: FilterChip[] = [
  { id: 'channel', label: 'TODOS OS CANAIS' },
  { id: 'period', label: 'ESTA SEMANA' },
]

export default function FilterBar() {
  const [filters, setFilters] = useState<FilterChip[]>(DEFAULT_FILTERS)

  const removeFilter = (id: string) => {
    setFilters((prev) => prev.filter((f) => f.id !== id))
  }

  return (
    <div className="bg-white border-b border-gray-200 px-6 py-2.5 flex items-center gap-3">
      {/* Filter Icon + Label */}
      <div className="flex items-center gap-2 text-gray-500">
        <Funnel size={16} />
        <span className="text-sm font-medium">Filtros Ativos:</span>
      </div>

      {/* Chips */}
      <div className="flex items-center gap-2">
        {filters.map((filter) => (
          <button
            key={filter.id}
            onClick={() => removeFilter(filter.id)}
            className="flex items-center gap-1.5 px-3 py-1 bg-blue-50 text-blue-600 rounded-full text-xs font-semibold hover:bg-blue-100 transition-colors"
          >
            {filter.label}
            <X size={12} weight="bold" />
          </button>
        ))}
      </div>
    </div>
  )
}
