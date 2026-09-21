'use client'

import { useState, useEffect } from 'react'
import { Plus, MagnifyingGlass, ShieldStar } from '@phosphor-icons/react'
import MemberModal from './MemberModal'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

interface MembersPanelProps {
  organizationId: string
}

export interface MemberData {
  id: string
  user_id: string
  role_id: string
  status: string
  created_at: string
  profiles: { full_name: string; avatar_url: string; email: string }
  organization_roles: { name: string }
}

export default function MembersPanel({ organizationId }: MembersPanelProps) {
  const [members, setMembers] = useState<MemberData[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [selectedMember, setSelectedMember] = useState<MemberData | null>(null)

  const fetchMembers = async () => {
    setLoading(true)
    try {
      const res = await fetch('/api/users')
      if (!res.ok) throw new Error('Failed to load members')
      const data = await res.json()
      setMembers(Array.isArray(data) ? data : (data.data || []))
    } catch (error) {
      console.error('Failed to load members:', error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (organizationId) fetchMembers()
  }, [organizationId])

  const filteredMembers = members.filter(m =>
    m.profiles?.full_name?.toLowerCase().includes(search.toLowerCase()) ||
    m.profiles?.email?.toLowerCase().includes(search.toLowerCase()) ||
    m.organization_roles?.name?.toLowerCase().includes(search.toLowerCase())
  )

  const handleEdit = (member: MemberData) => { setSelectedMember(member); setIsModalOpen(true) }
  const handleAddNew = () => { setSelectedMember(null); setIsModalOpen(true) }
  const handleCloseModal = (refresh: boolean = false) => { setIsModalOpen(false); if (refresh) fetchMembers() }

  if (loading) return <div className="flex justify-center py-20"><LoadingSpinner text="Carregando membros..." size="lg" /></div>

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div className="relative w-full sm:w-72">
          <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input
            type="text"
            placeholder="Buscar membro..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-white border border-gray-200 rounded-lg text-sm text-gray-900 focus:ring-2 focus:ring-blue-600 focus:border-blue-600 transition-colors"
          />
        </div>
        <button onClick={handleAddNew} className="w-full sm:w-auto px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg flex items-center justify-center gap-2 text-sm font-semibold transition-colors shadow-sm">
          <Plus weight="bold" /> Novo Membro
        </button>
      </div>

      <div className="bg-white border border-gray-200 rounded-xl overflow-hidden shadow-sm">
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="bg-gray-50 text-gray-500 font-semibold border-b border-gray-200">
              <tr>
                <th className="px-6 py-4">Usuário</th>
                <th className="px-6 py-4">Cargo</th>
                <th className="px-6 py-4">Status</th>
                <th className="px-6 py-4 text-right">Ações</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filteredMembers.length > 0 ? filteredMembers.map((member) => (
                <tr key={member.id} className="hover:bg-gray-50/50 transition-colors group">
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-full bg-panel-2 flex items-center justify-center flex-shrink-0 text-accent-2 font-bold uppercase overflow-hidden">
                        {member.profiles?.avatar_url ? (
                          <img src={member.profiles.avatar_url} alt="" className="w-full h-full object-cover" />
                        ) : (member.profiles?.full_name?.substring(0, 2) || 'US')}
                      </div>
                      <div>
                        <p className="font-semibold text-gray-900">{member.profiles?.full_name || 'Desconhecido'}</p>
                        <p className="text-gray-500 text-xs mt-0.5">{member.profiles?.email || 'Sem email'}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-gray-100 border border-gray-200 text-gray-700 font-medium">
                      {member.organization_roles?.name === 'Administrador' ? <ShieldStar weight="fill" className="text-amber-500" /> : null}
                      {member.organization_roles?.name || '---'}
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-green-100 text-green-700">
                      <span className="w-1.5 h-1.5 rounded-full bg-green-500" /> Ativo
                    </span>
                  </td>
                  <td className="px-6 py-4 text-right">
                    <button onClick={() => handleEdit(member)} className="px-3 py-1.5 text-sm font-medium text-blue-600 hover:bg-blue-50 rounded-lg transition-colors">
                      Editar
                    </button>
                  </td>
                </tr>
              )) : (
                <tr><td colSpan={4} className="px-6 py-12 text-center text-gray-500">Nenhum membro encontrado.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {isModalOpen && <MemberModal organizationId={organizationId} member={selectedMember} onClose={handleCloseModal} />}
    </div>
  )
}
