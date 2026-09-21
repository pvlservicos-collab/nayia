'use client'

import { useState, useEffect } from 'react'
import { UsersThree, Kanban, GearSix, SpinnerGap } from '@phosphor-icons/react'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

interface RolePermissionsPanelProps {
  organizationId: string
  selectedRoleId: string | null
}

interface PermissionsSchema {
  leads: { view_own_only: boolean; create_edit: boolean; export: boolean }
  pipeline: { manage_deals: boolean; configure_funnels: boolean }
  settings: {
    manage_members: boolean
    view_dashboard: boolean
    view_pipeline: boolean
    view_chat: boolean
    view_leads: boolean
    view_settings: boolean
    view_funnels: boolean
    view_logs: boolean
    view_metrics: boolean
    manage_quick_replies: boolean
  }
}

const defaultPermissions: PermissionsSchema = {
  leads: { view_own_only: true, create_edit: false, export: false },
  pipeline: { manage_deals: false, configure_funnels: false },
  settings: {
    manage_members: false,
    view_dashboard: true,
    view_pipeline: true,
    view_chat: true,
    view_leads: true,
    view_settings: false,
    view_funnels: true,
    view_logs: true,
    view_metrics: true,
    manage_quick_replies: false,
  },
}

const CustomSwitch = ({ checked, onChange, disabled }: { checked: boolean; onChange: () => void; disabled: boolean }) => (
  <button type="button" onClick={onChange} disabled={disabled}
    className={`relative inline-flex h-6 w-12 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-all duration-300 focus:outline-none focus:ring-2 focus:ring-blue-600 focus:ring-offset-2 ${checked ? 'bg-blue-600' : 'bg-gray-200'} ${disabled ? 'opacity-50 cursor-not-allowed' : 'hover:scale-105 active:scale-95'}`}
    role="switch" aria-checked={checked}>
    <span aria-hidden="true" className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-md ring-0 transition-transform duration-300 ${checked ? 'translate-x-6' : 'translate-x-0'}`} style={{ transitionTimingFunction: 'cubic-bezier(0.34, 1.56, 0.64, 1)' }} />
  </button>
)

const PermissionRow = ({ title, description, module, action, permissions, isAdmin, handleToggle, forceDisabled = false, forceChecked }: any) => {
  let isChecked = isAdmin ? true : permissions[module][action]
  let isDisabled = isAdmin
  if (forceChecked !== undefined) isChecked = forceChecked
  if (forceDisabled) isDisabled = true
  return (
    <div className="flex items-center justify-between py-4 border-b border-gray-100 last:border-0">
      <div className="pr-4">
        <p className={`text-sm font-semibold ${isDisabled ? 'text-gray-500' : 'text-gray-900'}`}>{title}</p>
        <p className="text-sm text-gray-500">{description}</p>
      </div>
      <CustomSwitch checked={isChecked} onChange={() => { if (!isDisabled) handleToggle(module, action) }} disabled={isDisabled} />
    </div>
  )
}

export default function RolePermissionsPanel({ organizationId, selectedRoleId }: RolePermissionsPanelProps) {
  const [roleName, setRoleName] = useState('')
  const [permissions, setPermissions] = useState<PermissionsSchema>(defaultPermissions)
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [hasChanges, setHasChanges] = useState(false)
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  useEffect(() => {
    if (!selectedRoleId) return
    fetchRolePermissions()
  }, [selectedRoleId])

  async function fetchRolePermissions() {
    setIsLoading(true)
    setHasChanges(false)
    setMessage(null)
    try {
      const res = await fetch(`/api/roles/${selectedRoleId}`)
      if (!res.ok) throw new Error('Failed to fetch role')
      const { data } = await res.json()
      setRoleName(data.name)
      const mergedPermissions = {
        leads: { ...defaultPermissions.leads, ...(data.permissions?.leads || {}) },
        pipeline: { ...defaultPermissions.pipeline, ...(data.permissions?.pipeline || {}) },
        settings: { ...defaultPermissions.settings, ...(data.permissions?.settings || {}) },
      }
      setPermissions(mergedPermissions as PermissionsSchema)
    } catch (err) {
      console.error('Error fetching permissions:', err)
    } finally {
      setIsLoading(false)
    }
  }

  const isAdmin = roleName.toLowerCase() === 'administrador' || roleName.toLowerCase() === 'owner' || roleName.toLowerCase() === 'master'

  if (roleName.toLowerCase() === 'master') {
    return (
      <div className="h-64 flex flex-col pt-8 items-center justify-center text-gray-500 bg-gray-50/50 rounded-xl border border-dashed border-gray-200">
        <SpinnerGap className="w-8 h-8 mb-3 text-muted" />
        <p className="text-sm font-medium text-gray-900">Cargo do Sistema Restrito</p>
        <p className="text-xs mt-1 text-gray-500">O cargo Master possui acesso global e não pode ser configurado por organização.</p>
      </div>
    )
  }

  const handleToggle = (module: keyof PermissionsSchema, action: string) => {
    if (isAdmin) return
    setPermissions(prev => {
      const next = { ...prev }
      // @ts-ignore
      next[module] = { ...prev[module], [action]: !prev[module][action] }
      return next
    })
    setHasChanges(true)
  }

  const handleSave = async () => {
    if (!selectedRoleId || isAdmin) return
    setIsSaving(true)
    setMessage(null)
    try {
      const res = await fetch(`/api/roles/${selectedRoleId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ permissions }),
      })
      if (!res.ok) throw new Error('Failed to save')
      setHasChanges(false)
      setMessage({ type: 'success', text: 'Permissões atualizadas com sucesso!' })
      setTimeout(() => setMessage(null), 3000)
    } catch (err) {
      setMessage({ type: 'error', text: 'Erro ao salvar as permissões.' })
    } finally {
      setIsSaving(false)
    }
  }

  if (!selectedRoleId) {
    return (
      <div className="h-64 flex flex-col pt-8 items-center text-gray-500 bg-gray-50/50 rounded-xl border border-dashed border-gray-200">
        <SpinnerGap className="w-8 h-8 mb-3 text-muted" />
        <p className="text-sm font-medium text-gray-900">Nenhum cargo selecionado</p>
        <p className="text-xs mt-1 text-gray-500">Selecione um cargo na lista ao lado ou crie um novo.</p>
      </div>
    )
  }

  if (isLoading) return <div className="h-64 flex items-center justify-center bg-gray-50/50 rounded-xl border border-dashed border-gray-200"><LoadingSpinner text="Carregando permissões..." /></div>

  return (
    <div className="space-y-6 animate-in fade-in duration-300">
      <div className="flex justify-between items-start">
        <div>
          <h2 className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-2">CONFIGURAÇÕES &gt; CARGOS</h2>
          <h3 className="text-2xl font-bold text-gray-900 mb-1">Permissões: <span className="text-blue-600">{roleName}</span></h3>
          <p className="text-sm text-gray-500">Defina o que os usuários com este cargo podem ver e fazer no CRM.</p>
        </div>
        {message && <div className={`px-4 py-2 rounded-lg text-sm font-medium ${message.type === 'success' ? 'bg-green-50 text-green-700 border border-green-200' : 'bg-red-50 text-red-700 border border-red-200'}`}>{message.text}</div>}
      </div>

      <div className="space-y-6">
        <div className="bg-white border border-gray-200 rounded-xl shadow-sm overflow-hidden">
          <div className="bg-gray-50 px-6 py-4 flex items-center gap-2 border-b border-gray-200">
            <UsersThree weight="bold" className="text-gray-400 w-5 h-5" />
            <h4 className="text-xs font-bold text-gray-700 uppercase tracking-wider">Módulo de Leads</h4>
          </div>
          <div className="px-6">
            <PermissionRow title="Ver apenas seus próprios leads" description="Limita a visão do CRM apenas aos cards atribuídos a este usuário." module="leads" action="view_own_only" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Criar e editar leads" description="Permite adicionar novos contatos ou modificar existentes." module="leads" action="create_edit" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Exportar dados" description="Habilita o download de planilhas CSV/XLSX." module="leads" action="export" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
          </div>
        </div>

        <div className="bg-white border border-gray-200 rounded-xl shadow-sm overflow-hidden">
          <div className="bg-gray-50 px-6 py-4 flex items-center gap-2 border-b border-gray-200">
            <Kanban weight="bold" className="text-gray-400 w-5 h-5" />
            <h4 className="text-xs font-bold text-gray-700 uppercase tracking-wider">Módulo de Pipeline</h4>
          </div>
          <div className="px-6">
            <PermissionRow title="Gerenciar Negócios" description="Mover cards no Kanban, ganhar ou perder negociações." module="pipeline" action="manage_deals" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Configurar Funis" description="Adicionar, editar ou remover etapas do processo comercial." module="pipeline" action="configure_funnels" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
          </div>
        </div>

        <div className="bg-white border border-gray-200 rounded-xl shadow-sm overflow-hidden">
          <div className="bg-gray-50 px-6 py-4 flex items-center gap-2 border-b border-gray-200">
            <GearSix weight="bold" className="text-gray-400 w-5 h-5" />
            <h4 className="text-xs font-bold text-gray-700 uppercase tracking-wider">Configurações Gerais</h4>
          </div>
          <div className="px-6">
            <PermissionRow title="Gerenciar Membros" description="Convidar novos usuários e alterar permissões da organização." module="settings" action="manage_members" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Dashboard" description="Permite o acesso à tela inicial de métricas." module="settings" action="view_dashboard" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Pipeline" description="Permite o acesso ao módulo de Negócios e Pipeline." module="settings" action="view_pipeline" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Chat" description="Permite o acesso ao módulo de Chat / WhatsApp." module="settings" action="view_chat" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Leads" description="Permite o acesso ao módulo central de Leads." module="settings" action="view_leads" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Funil de Mensagens" description="Permite o acesso às automações de mensagens." module="settings" action="view_funnels" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Logs" description="Permite o acesso ao histórico de eventos do sistema." module="settings" action="view_logs" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Métricas" description="Permite o acesso aos relatórios e métricas." module="settings" action="view_metrics" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Visualizar Configurações" description="Permite o acesso à esta tela de Configurações." module="settings" action="view_settings" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
            <PermissionRow title="Gerenciar Respostas Rápidas" description="Criar, editar e excluir a biblioteca de respostas rápidas compartilhada da equipe." module="settings" action="manage_quick_replies" permissions={permissions} isAdmin={isAdmin} handleToggle={handleToggle} />
          </div>
        </div>

        {!isAdmin && (
          <div className="border border-red-200 border-dashed bg-red-50/50 rounded-xl p-6 flex items-center justify-between">
            <div>
              <h4 className="text-sm font-bold text-red-900">Remover Cargo</h4>
              <p className="text-sm text-red-700 mt-1">Este cargo não poderá ser excluído se houver membros vinculados a ele.</p>
            </div>
            <button className="px-4 py-2 bg-white border border-red-200 text-red-600 font-semibold text-sm rounded-lg hover:bg-red-50 transition-colors shadow-sm">Remover Cargo</button>
          </div>
        )}

        <div className="pt-4 flex justify-end">
          {!isAdmin ? (
            <button onClick={handleSave} disabled={!hasChanges || isSaving} className={`px-5 py-2.5 bg-blue-600 text-white font-semibold text-sm rounded-lg shadow-sm transition-colors flex items-center gap-2 ${!hasChanges || isSaving ? 'opacity-50 cursor-not-allowed' : 'hover:bg-blue-700'}`}>
              {isSaving && <SpinnerGap className="w-4 h-4 animate-spin" weight="bold" />} Salvar Alterações
            </button>
          ) : (
            <div className="px-4 py-2 bg-gray-100 rounded-lg text-sm text-gray-500 font-medium">Cargo administrador fixo. Permissões não podem ser removidas.</div>
          )}
        </div>
      </div>
    </div>
  )
}
