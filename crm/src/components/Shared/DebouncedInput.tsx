'use client'

import React, { useState, useEffect, useRef } from 'react'

interface DebouncedInputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'onChange'> {
    value: string | number
    onChange: (value: string | number) => void
    debounceTime?: number
}

export default function DebouncedInput({
    value: initialValue,
    onChange,
    debounceTime = 500,
    ...props
}: DebouncedInputProps) {
    const [value, setValue] = useState(initialValue)
    const isInternalChange = useRef(false)

    useEffect(() => {
        if (!isInternalChange.current) {
            setValue(initialValue)
        }
        isInternalChange.current = false
    }, [initialValue])

    useEffect(() => {
        // Only debounce if the internal value doesn't match the initial (prop) value
        if (value !== initialValue) {
            const timeout = setTimeout(() => {
                onChange(value)
            }, debounceTime)

            return () => clearTimeout(timeout)
        }
    }, [value, onChange, debounceTime, initialValue])

    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        isInternalChange.current = true
        const val = props.type === 'number' && e.target.value ? Number(e.target.value) : e.target.value
        setValue(val)
    }

    return (
        <input
            {...props}
            value={value === null || value === undefined ? '' : value}
            onChange={handleChange}
        />
    )
}
