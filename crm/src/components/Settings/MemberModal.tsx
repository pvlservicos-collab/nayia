'use client'

import { useState, useEffect } from 'react'
import { createPortal } from 'react-dom'
import { X, SpinnerGap, Trash } from '@phosphor-icons/react'

interface MemberModalProps {
  organizationId: string
  member: any | null
  onClose: (refresh?: boolean) => void
}

export default function MemberModal({ organizationId, member, onClose }: MemberModalProps) {
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [roleId, setRoleId] = useState('')
  const [roles, setRoles] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [mounted, setMounted] = useState(false)

  const isEditing = !!member

  useEffect(() => {
    setMounted(true)
    async function fetchRoles() {
      const res = await fetch('/api/roles')
      if (res.ok) {
        const { data } = await res.json()
        const validRoles = (data || []).filter((r: any) => r.name.toLowerCase() !== 'master')
        setRoles(validRoles)
        if (!isEditing && validRoles.length > 0) setRoleId(validRoles[0].id)
      }
    }
    fetchRoles()
    if (isEditing) {
      setName(member.profiles?.full_name || '')
      setEmail(member.profiles?.email || '')
      setRoleId(member.role_id)
    }
  }, [organizationId, isEditing, member])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      const endpoint = isEditing ? `/api/users/${member.id}` : '/api/users'
      const method = isEditing ? 'PUT' : 'POST'
      const res = await fetch(endpoint, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, password, role_id: roleId }),
      })
      const result = await res.json()
      if (!res.ok) throw new Error(result.error || result.detail || 'Erro ao salvar membro')
      onClose(true)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleDelete = async () => {
    if (!confirm('Tem certeza que deseja remover este membro da organização?')) return
    setDeleting(true)
    setError(null)
    try {
      const res = await fetch(`/api/users/${member.id}`, { method: 'DELETE', headers: { 'Content-Type': 'application/json' } })
      const result = await res.json()
      if (!res.ok) throw new Error(result.error || 'Erro ao remover membro')
      onClose(true)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setDeleting(false)
    }
  }

  if (!mounted) return null

  return createPortal(
    <div className="fixed inset-0 z-[100]">
      <div className="absolute inset-0 bg-black/50 modal-overlay-enter" onClick={() => onClose()} />
      <div className="flex items-center justify-center min-h-screen p-4 pointer-events-none">
        <div className="bg-white rounded-xl shadow-xl w-full max-w-md overflow-hidden modal-content-enter pointer-events-auto relative z-10">
          <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100">
            <h2 className="text-lg font-bold text-gray-900">{isEditing ? 'Editar Membro' : 'Novo Membro'}</h2>
            <button onClick={() => onClose()} className="text-gray-400 hover:text-gray-600 transition-colors p-1"><X className="w-5 h-5" /></button>
          </div>
          <form onSubmit={handleSubmit} className="p-6 space-y-4">
            {error && <div className="p-3 bg-red-50 text-red-700 text-sm rounded-lg border border-red-200">{error}</div>}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Nome Completo</label>
              <input type="text" required value={name} onChange={(e) => setName(e.target.value)} className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-blue-600 focus:bg-white transition-all" placeholder="Ex: João Silva" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">E-mail</label>
              <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-blue-600 focus:bg-white transition-all" placeholder="joao@empresa.com" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Cargo</label>
              <select required value={roleId} onChange={(e) => setRoleId(e.target.value)} className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm text-gray-900 focus:ring-2 focus:ring-blue-600 focus:bg-white transition-all">
                <option value="" disabled>Selecione um Cargo</option>
                {roles.map(role => <option key={role.id} value={role.id}>{role.name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">{isEditing ? 'Nova Senha (Opcional)' : 'Senha de Acesso'}</label>
              <input type="password" required={!isEditing} value={password} onChange={(e) => setPassword(e.target.value)} className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-blue-600 focus:bg-white transition-all" placeholder={isEditing ? 'Deixe em branco para manter' : 'Mínimo 6 caracteres'} />
            </div>
            <div className={`pt-4 flex ${isEditing ? 'justify-between' : 'justify-end'} gap-3`}>
              {isEditing && (
                <button type="button" onClick={handleDelete} disabled={deleting || loading} className="px-4 py-2 text-sm font-medium text-red-600 bg-white border border-red-200 rounded-lg hover:bg-red-50 disabled:opacity-50 transition-colors shadow-sm flex items-center gap-1.5">
                  {deleting ? <SpinnerGap className="w-4 h-4 animate-spin" weight="bold" /> : <Trash className="w-4 h-4" weight="bold" />} Remover
                </button>
              )}
              <div className="flex gap-3">
                <button type="button" onClick={() => onClose()} className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors shadow-sm">Cancelar</button>
                <button type="submit" disabled={loading || deleting} className="px-6 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors shadow-sm flex items-center justify-center min-w-[120px]">
                  {loading ? <SpinnerGap className="w-5 h-5 animate-spin" weight="bold" /> : 'Salvar'}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </div>,
    document.body
  )
}
