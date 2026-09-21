'use client'

import { useState, useRef, useEffect } from 'react'

interface CustomFieldSelectProps {
  options: string[]
  value: string
  onChange: (val: string) => void
  placeholder?: string
}

export default function CustomFieldSelect({ options, value, onChange, placeholder = 'Selecione...' }: CustomFieldSelectProps) {
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

  return (
    <div className="relative w-full" ref={containerRef}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between text-[13px] font-medium border-b border-[var(--chat-border)] pb-1 focus:outline-none focus:border-[var(--chat-accent)] bg-transparent text-left cursor-pointer transition-colors hover:border-[var(--chat-accent)]"
      >
        <span className={value ? 'text-[var(--chat-text-secondary)]' : 'text-[var(--chat-text-tertiary)]'}>{value || placeholder}</span>
        <svg className={`w-3.5 h-3.5 text-[var(--chat-text-muted)] transition-transform duration-200 ${isOpen ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" /></svg>
      </button>

      {isOpen && (
        <div className="glass-raised absolute z-50 w-full mt-1.5 rounded-xl py-1 max-h-48 overflow-y-auto animate-in fade-in slide-in-from-top-1">
          <button
            type="button"
            className={`w-full text-left px-3 py-2 text-[13px] hover:bg-[var(--chat-bg-hover)] flex items-center transition-colors ${!value ? 'bg-[var(--chat-bg-hover)] text-[var(--chat-accent)] font-semibold' : 'text-[var(--chat-text-tertiary)]'}`}
            onClick={() => {
              onChange('')
              setIsOpen(false)
            }}
          >
            {placeholder}
          </button>

          {options.map((opt) => (
            <button
              key={opt}
              type="button"
              className={`w-full text-left px-3 py-2 text-[13px] hover:bg-[var(--chat-bg-hover)] flex items-center transition-colors ${value === opt ? 'bg-[var(--chat-bg-hover)] text-[var(--chat-accent)] font-semibold' : 'text-[var(--chat-text-secondary)]'}`}
              onClick={() => {
                onChange(opt)
                setIsOpen(false)
              }}
            >
              {opt}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
