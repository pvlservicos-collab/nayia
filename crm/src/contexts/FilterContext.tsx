'use client'

import { createContext, useContext, useState, ReactNode } from 'react'
import { FilterState } from '@/components/Shared/FilterButton'

interface FilterContextType {
    filters: FilterState
    setFilters: (filters: FilterState) => void
}

const defaultFilters: FilterState = {
    integrations: [],
    sellers: [],
    stages: [],
    dateRange: { type: 'all' }
}

const FilterContext = createContext<FilterContextType | undefined>(undefined)

export function FilterProvider({ children }: { children: ReactNode }) {
    const [filters, setFilters] = useState<FilterState>(defaultFilters)

    return (
        <FilterContext.Provider value={{ filters, setFilters }}>
            {children}
        </FilterContext.Provider>
    )
}

export function usePipelineFilters() {
    const context = useContext(FilterContext)
    if (context === undefined) {
        throw new Error('usePipelineFilters must be used within a FilterProvider')
    }
    return context
}
