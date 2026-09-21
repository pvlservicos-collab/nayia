'use client'

import { useState, useRef, useEffect } from 'react'

interface CustomFieldMultiSelectProps {
  options: string[]
  value: string[]
  onChange: (val: string[]) => void
  placeholder?: string
}

export default function CustomFieldMultiSelect({ options, value, onChange, placeholder = 'Selecione...' }: CustomFieldMultiSelectProps) {
  const [isOpen, setIsOpen] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false)
      }
    }
    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside)
    }
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [isOpen])

  const toggleOption = (opt: string) => {
    if (value.includes(opt)) {
      onChange(value.filter((v) => v !== opt))
    } else {
      onChange([...value, opt])
    }
  }

  const displayText = value.length > 0 ? value.join(', ') : ''

  return (
    <div className="relative w-full" ref={containerRef}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between text-[13px] font-medium border-b border-[var(--chat-border)] pb-1 focus:outline-none focus:border-[var(--chat-accent)] bg-transparent text-left cursor-pointer transition-colors hover:border-[var(--chat-accent)] gap-1"
      >
        <span className={`truncate ${displayText ? 'text-[var(--chat-text-secondary)]' : 'text-[var(--chat-text-tertiary)]'}`}>{displayText || placeholder}</span>
        <svg className={`w-3.5 h-3.5 text-[var(--chat-text-muted)] flex-shrink-0 transition-transform duration-200 ${isOpen ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" /></svg>
      </button>

      {isOpen && (
        <div className="glass-raised absolute z-50 w-full mt-1.5 rounded-xl py-1 max-h-48 overflow-y-auto">
          {value.length > 0 && (
            <button
              type="button"
              className="w-full text-left px-3 py-2 text-[13px] text-[var(--chat-text-muted)] hover:bg-[var(--chat-bg-hover)] transition-colors border-b border-[var(--chat-border)]"
              onClick={() => {
                onChange([])
              }}
            >
              Limpar seleção
            </button>
          )}

          {options.map((opt) => {
            const isSelected = value.includes(opt)
            return (
              <button
                key={opt}
                type="button"
                className={`w-full text-left px-3 py-2 text-[13px] hover:bg-[var(--chat-bg-hover)] flex items-center gap-2 transition-colors ${isSelected ? 'text-[var(--chat-accent)]' : 'text-[var(--chat-text-secondary)]'}`}
                onClick={() => toggleOption(opt)}
              >
                <div className={`w-4 h-4 rounded border-2 flex items-center justify-center flex-shrink-0 transition-colors ${isSelected ? 'bg-[var(--chat-accent)] border-[var(--chat-accent)]' : 'border-[var(--chat-border)] bg-transparent'}`}>
                  {isSelected && (
                    <svg className="w-2.5 h-2.5 text-[#0b141a]" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" /></svg>
                  )}
                </div>
                <span className={isSelected ? 'font-semibold' : ''}>{opt}</span>
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}
