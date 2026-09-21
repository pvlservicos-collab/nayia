'use client'

import { useState, useEffect } from 'react'
import { CalendarBlank, CaretLeft, CaretRight } from '@phosphor-icons/react'
import { DayPicker } from 'react-day-picker'
import { format, parse, startOfWeek, endOfWeek, isSameDay } from 'date-fns'
import { ptBR } from 'date-fns/locale'
import 'react-day-picker/dist/style.css'

export type DateRangeType = 'today' | 'this_week' | 'custom'

interface PeriodSelectorProps {
    selectedType: DateRangeType
    startDate?: Date
    endDate?: Date
    onTypeChange: (type: DateRangeType) => void
    onRangeChange: (start?: Date, end?: Date) => void
}

const PERIOD_OPTIONS: { id: DateRangeType; label: string }[] = [
    { id: 'today', label: 'Hoje' },
    { id: 'this_week', label: 'Esta Semana' },
    { id: 'custom', label: 'Personalizado' },
]

export default function PeriodSelector({
    selectedType,
    startDate,
    endDate,
    onTypeChange,
    onRangeChange,
}: PeriodSelectorProps) {
    const [startInput, setStartInput] = useState('')
    const [endInput, setEndInput] = useState('')

    // Sync inputs from parent dates
    useEffect(() => {
        setStartInput(startDate ? format(startDate, 'dd/MM/yyyy') : '')
        setEndInput(endDate ? format(endDate, 'dd/MM/yyyy') : '')
    }, [startDate, endDate])

    const handleTypeChange = (type: DateRangeType) => {
        onTypeChange(type)
        if (type === 'today') {
            const today = new Date()
            onRangeChange(today, today)
        } else if (type === 'this_week') {
            const today = new Date()
            onRangeChange(startOfWeek(today, { weekStartsOn: 0 }), endOfWeek(today, { weekStartsOn: 0 }))
        }
        // 'custom' keeps whatever dates are set
    }

    const parseDateInput = (input: string): Date | undefined => {
        const cleaned = input.replace(/[^\d/]/g, '')
        if (cleaned.length === 10) {
            const parsed = parse(cleaned, 'dd/MM/yyyy', new Date())
            return !isNaN(parsed.getTime()) ? parsed : undefined
        }
        return undefined
    }

    // Auto-format input with slashes
    const formatInputMask = (raw: string): string => {
        const digits = raw.replace(/\D/g, '').slice(0, 8)
        if (digits.length <= 2) return digits
        if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`
        return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`
    }

    const handleStartInput = (e: React.ChangeEvent<HTMLInputElement>) => {
        const masked = formatInputMask(e.target.value)
        setStartInput(masked)
        const date = parseDateInput(masked)
        if (date) onRangeChange(date, endDate)
    }

    const handleEndInput = (e: React.ChangeEvent<HTMLInputElement>) => {
        const masked = formatInputMask(e.target.value)
        setEndInput(masked)
        const date = parseDateInput(masked)
        if (date) onRangeChange(startDate, date)
    }

    return (
        <div className="flex flex-col gap-5">
            {/* Radio row */}
            <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
                {PERIOD_OPTIONS.map((opt) => (
                    <label
                        key={opt.id}
                        className="flex items-center gap-2 cursor-pointer group select-none"
                        onClick={() => handleTypeChange(opt.id)}
                    >
                        <span
                            className={`
                w-[18px] h-[18px] rounded-full border-2 flex items-center justify-center transition-all
                ${selectedType === opt.id
                                    ? 'border-blue-600'
                                    : 'border-gray-300 group-hover:border-gray-400'}
              `}
                        >
                            {selectedType === opt.id && (
                                <span className="w-[10px] h-[10px] rounded-full bg-blue-600" />
                            )}
                        </span>
                        <span
                            className={`text-sm font-medium transition-colors whitespace-nowrap ${selectedType === opt.id
                                    ? 'text-gray-900'
                                    : 'text-gray-500 group-hover:text-gray-700'
                                }`}
                        >
                            {opt.label}
                        </span>
                    </label>
                ))}
            </div>

            {/* Custom date picker area */}
            {selectedType === 'custom' && (
                <div className="space-y-4">
                    {/* DE / ATÉ inputs */}
                    <div className="flex items-center gap-3">
                        <div className="flex-1 min-w-0">
                            <label className="block text-[10px] font-bold uppercase text-gray-400 mb-1.5 tracking-wider">
                                De
                            </label>
                            <div className="flex items-center gap-2 px-3 py-2.5 bg-gray-50 border border-gray-200 rounded-xl hover:border-gray-300 focus-within:border-blue-500 focus-within:ring-2 focus-within:ring-blue-100 transition-all">
                                <CalendarBlank size={16} className="text-gray-400 flex-shrink-0" />
                                <input
                                    type="text"
                                    value={startInput}
                                    onChange={handleStartInput}
                                    placeholder="DD/MM/AAAA"
                                    maxLength={10}
                                    className="w-full min-w-0 bg-transparent text-sm font-semibold text-gray-800 placeholder-gray-300 outline-none"
                                />
                            </div>
                        </div>

                        <span className="text-gray-300 mt-5 font-light">—</span>

                        <div className="flex-1 min-w-0">
                            <label className="block text-[10px] font-bold uppercase text-gray-400 mb-1.5 tracking-wider">
                                Até
                            </label>
                            <div className="flex items-center gap-2 px-3 py-2.5 bg-gray-50 border border-gray-200 rounded-xl hover:border-gray-300 focus-within:border-blue-500 focus-within:ring-2 focus-within:ring-blue-100 transition-all">
                                <CalendarBlank size={16} className="text-gray-400 flex-shrink-0" />
                                <input
                                    type="text"
                                    value={endInput}
                                    onChange={handleEndInput}
                                    placeholder="DD/MM/AAAA"
                                    maxLength={10}
                                    className="w-full min-w-0 bg-transparent text-sm font-semibold text-gray-800 placeholder-gray-300 outline-none"
                                />
                            </div>
                        </div>
                    </div>

                    {/* Calendar card */}
                    <div className="filter-calendar-card">
                        <DayPicker
                            mode="range"
                            selected={
                                startDate && endDate
                                    ? { from: startDate, to: endDate }
                                    : startDate
                                        ? { from: startDate, to: startDate }
                                        : undefined
                            }
                            onSelect={(range) => {
                                if (range) {
                                    let s = range.from
                                    let e = range.to
                                    // If end < start, swap
                                    if (s && e && e < s) {
                                        const tmp = s; s = e; e = tmp
                                    }
                                    onRangeChange(s, e)
                                }
                            }}
                            locale={ptBR}
                            showOutsideDays
                            classNames={{
                                root: 'rdp-revitalized',
                                months: 'rdp-months-rev',
                                month: 'rdp-month-rev',
                                month_caption: 'rdp-caption-rev',
                                caption_label: 'rdp-caption-label-rev',
                                nav: 'rdp-nav-rev',
                                button_previous: 'rdp-nav-btn-rev',
                                button_next: 'rdp-nav-btn-rev',
                                month_grid: 'rdp-table-rev',
                                weekdays: 'rdp-head-row-rev',
                                weekday: 'rdp-head-cell-rev',
                                week: 'rdp-row-rev',
                                day: 'rdp-day-rev',
                                day_button: 'rdp-day-btn-rev',
                                selected: 'rdp-selected-rev',
                                range_start: 'rdp-range-start-rev',
                                range_end: 'rdp-range-end-rev',
                                range_middle: 'rdp-range-middle-rev',
                                today: 'rdp-today-rev',
                                outside: 'rdp-outside-rev',
                                disabled: 'rdp-disabled-rev',
                                hidden: 'rdp-hidden-rev',
                            }}
                        />
                    </div>
                </div>
            )}
        </div>
    )
}
