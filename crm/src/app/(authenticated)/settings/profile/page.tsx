'use client'

import { useState, useEffect, useRef } from 'react'
import { useAuth } from '@/hooks'
import { useSession } from 'next-auth/react'
import { SpinnerGap, ShieldCheck } from '@phosphor-icons/react'
import { useNotification } from '@/contexts/NotificationContext'
import { uploadClientFile } from '@/lib/blobClient'
import Image from 'next/image'

export default function UserProfileSettingsPage() {
    const { user, isMaster, roleName, profileName } = useAuth()
    const fileInputRef = useRef<HTMLInputElement>(null)
    const [isSaving, setIsSaving] = useState(false)
    const [isUploading, setIsUploading] = useState(false)
    const [avatarUrl, setAvatarUrl] = useState<string | null>(null)
    const { addNotification } = useNotification()

    // Form states
    const [name, setName] = useState('')
    const [email, setEmail] = useState('')
    const [role, setRole] = useState('')
    const [emailNotifications, setEmailNotifications] = useState(true)

    // Password states
    const [currentPassword, setCurrentPassword] = useState('')
    const [newPassword, setNewPassword] = useState('')
    const [confirmPassword, setConfirmPassword] = useState('')

    useEffect(() => {
        if (user) {
            setName(profileName || user.name || '')
            setEmail(user.email || '')
            setRole(isMaster ? 'Master' : (roleName || 'Membro'))
            if (user.image) setAvatarUrl(user.image)
        }
    }, [user, isMaster, roleName, profileName])

    const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0]
        if (!file || !user) return

        if (file.size > 2 * 1024 * 1024) {
            addNotification({
                type: 'error',
                title: 'Erro de Validação',
                message: 'A imagem deve ter no máximo 2MB.'
            })
            return
        }

        // Show local preview immediately
        const objectUrl = URL.createObjectURL(file)
        setAvatarUrl(objectUrl)
        setIsUploading(true)

        try {
            const publicUrl = await uploadClientFile(file, 'avatars', user.id)

            const updateRes = await fetch('/api/users/me', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ avatar_url: publicUrl }) })
            if (!updateRes.ok) throw new Error('Failed to update avatar')

            setAvatarUrl(publicUrl)
            addNotification({
                type: 'success',
                title: 'Foto Atualizada',
                message: 'Foto de perfil atualizada com sucesso.'
            })
        } catch (err: any) {
            console.error('Error uploading avatar:', err)
            addNotification({
                type: 'error',
                title: 'Erro no Upload',
                message: err.message || 'Erro ao enviar a foto.'
            })
            setAvatarUrl(user.image || null)
        } finally {
            setIsUploading(false)
            // Reset file input
            if (fileInputRef.current) fileInputRef.current.value = ''
        }
    }

    // Helper for initials
    const getInitials = (fullName: string) => {
        if (!fullName) return 'U'
        const parts = fullName.trim().split(' ')
        if (parts.length >= 2) {
            return `${parts[0][0]}${parts[1][0]}`.toUpperCase()
        }
        return fullName.substring(0, 2).toUpperCase()
    }

    const handleSavePersonalInfo = async () => {
        if (!user) return
        setIsSaving(true)
        try {
            const res = await fetch('/api/users/me', {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ full_name: name }),
            })
            if (!res.ok) throw new Error('Failed to update profile')
            addNotification({ type: 'success', title: 'Perfil Atualizado', message: 'Informações pessoais atualizadas com sucesso.' })
        } catch (err: any) {
            addNotification({ type: 'error', title: 'Erro na Atualização', message: err.message || 'Erro ao atualizar.' })
        } finally {
            setIsSaving(false)
        }
    }

    const handleUpdatePassword = async () => {
        if (!newPassword || newPassword !== confirmPassword) {
            addNotification({ type: 'error', title: 'Validação de Senha', message: 'A nova senha e a confirmação devem ser iguais.' })
            return
        }
        if (newPassword.length < 6) {
            addNotification({ type: 'error', title: 'Validação de Senha', message: 'A nova senha deve ter pelo menos 6 caracteres.' })
            return
        }
        setIsSaving(true)
        try {
            const res = await fetch('/api/users/me', {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ new_password: newPassword }),
            })
            if (!res.ok) throw new Error('Falha ao atualizar senha')
            addNotification({ type: 'success', title: 'Senha Atualizada', message: 'Senha atualizada com sucesso.' })
            setCurrentPassword('')
            setNewPassword('')
            setConfirmPassword('')
        } catch (err: any) {
            addNotification({ type: 'error', title: 'Falha ao Atualizar Senha', message: err.message || 'Erro ao atualizar a senha.' })
        } finally {
            setIsSaving(false)
        }
    }

    return (
        <div className="max-w-4xl pb-20">
            {/* Header */}
            <div className="mb-8">
                <h1 className="text-2xl font-bold font-display text-ink">Configurações do Perfil</h1>
                <p className="text-muted mt-1">Gerencie suas informações pessoais e preferências de conta.</p>
            </div>

            <div className="space-y-6">

                {/* Foto do Perfil Section */}
                <section className="bg-panel border border-line rounded-2xl overflow-hidden shadow-sm">
                    <div className="px-6 py-4 border-b border-line bg-void">
                        <h2 className="text-xs font-bold text-muted uppercase tracking-wider font-display">FOTO DO PERFIL</h2>
                    </div>
                    <div className="p-6 flex items-center gap-6">
                        <div className="w-24 h-24 rounded-full bg-[#E5E5CA] flex items-center justify-center border-4 border-panel shadow-md overflow-hidden shrink-0 relative">
                            {avatarUrl ? (
                                <Image
                                    src={avatarUrl}
                                    alt="Avatar"
                                    fill
                                    className="object-cover"
                                    unoptimized
                                />
                            ) : (
                                <span className="text-3xl font-bold text-[#142340]">{getInitials(name || email)}</span>
                            )}
                            {isUploading && (
                                <div className="absolute inset-0 bg-black/40 flex items-center justify-center rounded-full">
                                    <SpinnerGap size={28} className="animate-spin text-white" />
                                </div>
                            )}
                        </div>
                        <div>
                            <input
                                ref={fileInputRef}
                                type="file"
                                accept="image/jpeg,image/png,image/gif"
                                className="hidden"
                                onChange={handleAvatarUpload}
                            />
                            <button
                                onClick={() => fileInputRef.current?.click()}
                                disabled={isUploading}
                                className="px-4 py-2 border border-line hover:bg-void text-muted text-sm font-semibold rounded-lg transition-colors mb-2 disabled:opacity-50"
                            >
                                {isUploading ? 'Enviando...' : 'Alterar Foto'}
                            </button>
                            <p className="text-xs text-muted font-medium">JPG, GIF ou PNG. Tamanho máx. 2MB.</p>
                        </div>
                    </div>
                </section>

                {/* Informações Pessoais Section */}
                <section className="bg-panel border border-line rounded-2xl overflow-hidden shadow-sm">
                    <div className="px-6 py-4 border-b border-line bg-void flex justify-between items-center">
                        <h2 className="text-xs font-bold text-muted uppercase tracking-wider font-display">INFORMAÇÕES PESSOAIS</h2>
                        <button
                            onClick={handleSavePersonalInfo}
                            disabled={isSaving}
                            className="text-sm font-semibold text-accent-2 hover:text-accent-2 disabled:opacity-50"
                        >
                            {isSaving ? 'Salvando...' : 'Salvar'}
                        </button>
                    </div>
                    <div className="p-6 space-y-6">
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                            <div className="space-y-1.5">
                                <label className="text-sm font-semibold text-muted">Nome Completo</label>
                                <input
                                    type="text"
                                    value={name}
                                    onChange={(e) => setName(e.target.value)}
                                    placeholder="Seu nome"
                                    className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all font-medium text-ink"
                                />
                            </div>
                            <div className="space-y-1.5">
                                <label className="text-sm font-semibold text-muted">E-mail Pessoal</label>
                                <input
                                    type="email"
                                    value={email}
                                    disabled
                                    className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm text-muted font-medium cursor-not-allowed"
                                />
                            </div>
                        </div>

                        <div className="space-y-1.5">
                            <label className="text-sm font-semibold text-muted">Cargo</label>
                            <input
                                type="text"
                                value={role}
                                disabled
                                className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm text-muted font-medium cursor-not-allowed"
                            />
                        </div>
                    </div>
                </section>

                {/* Segurança Section */}
                <section className="bg-panel border border-line rounded-2xl overflow-hidden shadow-sm">
                    <div className="px-6 py-4 border-b border-line bg-void flex justify-between items-center">
                        <h2 className="text-xs font-bold text-muted uppercase tracking-wider font-display">SEGURANÇA</h2>
                        <div className="flex items-center gap-3">
                            <span className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-green-700 bg-green-100 px-2 py-1 rounded-md">
                                <ShieldCheck size={14} weight="fill" />
                                Protegido
                            </span>
                        </div>
                    </div>
                    <div className="p-6 space-y-6">
                        <div className="space-y-1.5">
                            <label className="text-sm font-semibold text-muted">Senha Atual</label>
                            <input
                                type="password"
                                value={currentPassword}
                                onChange={(e) => setCurrentPassword(e.target.value)}
                                placeholder="••••••••"
                                className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all text-ink"
                            />
                        </div>
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                            <div className="space-y-1.5">
                                <label className="text-sm font-semibold text-muted">Nova Senha</label>
                                <input
                                    type="password"
                                    value={newPassword}
                                    onChange={(e) => setNewPassword(e.target.value)}
                                    placeholder="Nova senha"
                                    className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all text-ink"
                                />
                            </div>
                            <div className="space-y-1.5">
                                <label className="text-sm font-semibold text-muted">Confirmar Nova Senha</label>
                                <input
                                    type="password"
                                    value={confirmPassword}
                                    onChange={(e) => setConfirmPassword(e.target.value)}
                                    placeholder="Confirme a senha"
                                    className="w-full h-11 px-4 bg-void border border-line rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all text-ink"
                                />
                            </div>
                        </div>

                        <div className="pt-2">
                            <button
                                onClick={handleUpdatePassword}
                                disabled={isSaving || !newPassword || newPassword !== confirmPassword}
                                className="px-5 py-2.5 bg-void hover:bg-black text-white text-sm font-medium rounded-xl transition-colors shadow-sm disabled:opacity-50 flex items-center gap-2"
                            >
                                {isSaving ? <SpinnerGap size={18} className="animate-spin" /> : null}
                                Atualizar Senha
                            </button>
                        </div>
                    </div>
                </section>

                {/* Preferências Section */}
                <section className="bg-panel border border-line rounded-2xl overflow-hidden shadow-sm">
                    <div className="px-6 py-4 border-b border-line bg-void">
                        <h2 className="text-xs font-bold text-muted uppercase tracking-wider font-display">PREFERÊNCIAS</h2>
                    </div>
                    <div className="p-6">
                        <div className="flex items-center justify-between">
                            <div>
                                <h3 className="text-sm font-semibold text-ink">Notificações por E-mail</h3>
                                <p className="text-sm text-muted mt-0.5">Receba resumos semanais e alertas de novos leads.</p>
                            </div>
                            <button
                                onClick={() => setEmailNotifications(!emailNotifications)}
                                className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${emailNotifications ? 'bg-accent' : 'bg-panel-2'}`}
                                role="switch"
                                aria-checked={emailNotifications}
                            >
                                <span
                                    aria-hidden="true"
                                    className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-panel shadow ring-0 transition duration-200 ease-in-out ${emailNotifications ? 'translate-x-5' : 'translate-x-0'}`}
                                ></span>
                            </button>
                        </div>
                    </div>
                </section>

            </div>
        </div>
    )
}
