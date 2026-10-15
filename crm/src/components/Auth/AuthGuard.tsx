'use client'

/**
 * AuthGuard — substitui verificação de sessão Supabase
 * Usa useSession do NextAuth
 */
import { useEffect, useRef, useState, ReactNode } from 'react'
import { useSession } from 'next-auth/react'
import { useRouter } from 'next/navigation'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

/**
 * Segunda barreira, no cliente: o middleware já redireciona quem não tem cookie
 * de sessão, mas ele não roda em navegação client-side do Next. Sem isto, uma
 * sessão que expira com a aba aberta deixaria a pessoa numa tela que parece
 * funcionar e só devolve 401 em toda chamada.
 *
 * SÓ SAI QUANDO O SERVIDOR CONFIRMA (15/10/2026, a Rayssa: "o CRM dela está
 * saindo e ela está perdendo o histórico", com visitas batendo). O
 * SessionProvider rechecа a sessão toda vez que a aba volta ao foco -- no
 * celular, a cada ida ao WhatsApp e volta. Se essa checagem falha por um
 * instante (rede oscilando, o app saindo do segundo plano antes da internet
 * voltar), o next-auth trata a falha como "sem sessão", o status vira
 * 'unauthenticated' e esta tela mandava para o login -- fora da conversa em que
 * ela estava. A sessão (um JWT de 30 dias no cookie) continuava valendo.
 *
 * Agora 'unauthenticated' é só suspeita: pergunta ao servidor
 * (/api/auth/session) e só vai para o login se ele RESPONDER que não há
 * sessão. Falha de rede não desloga: a tela fica, com o aviso "reconectando",
 * e tenta de novo. E a volta ao login leva o endereço inteiro (com ?leadId=),
 * para cair na mesma conversa depois de entrar.
 */
type Conferencia = 'sem_sessao' | 'com_sessao' | 'sem_resposta'

async function conferirNoServidor(): Promise<Conferencia> {
  try {
    const r = await fetch('/api/auth/session', { cache: 'no-store', credentials: 'same-origin' })
    if (!r.ok) return 'sem_resposta'
    const s = await r.json().catch(() => null)
    return s && s.user ? 'com_sessao' : 'sem_sessao'
  } catch {
    return 'sem_resposta'
  }
}

export default function AuthGuard({ children }: { children: ReactNode }) {
  const { data: session, status, update } = useSession()
  const router = useRouter()
  const [reconectando, setReconectando] = useState(false)
  const ultimaSessao = useRef(session)
  if (session) ultimaSessao.current = session

  useEffect(() => {
    if (status !== 'unauthenticated') { setReconectando(false); return }
    let parar = false
    let espera: ReturnType<typeof setTimeout> | undefined
    const conferir = async (tentativa: number) => {
      const r = await conferirNoServidor()
      if (parar) return
      if (r === 'sem_sessao') {
        // confirmado pelo servidor: a sessão acabou de verdade
        const aqui = window.location.pathname + window.location.search
        router.push('/login' + (aqui && aqui !== '/' ? '?callbackUrl=' + encodeURIComponent(aqui) : ''))
        return
      }
      if (r === 'com_sessao') {
        setReconectando(false)
        void update()          // a sessão estava lá: o provider volta a ter o usuário
        return
      }
      // sem resposta (rede): fica na tela e tenta de novo, cada vez mais devagar (até 15 s)
      setReconectando(true)
      espera = setTimeout(() => conferir(tentativa + 1), Math.min(15000, 1500 * (tentativa + 1)))
    }
    void conferir(0)
    const voltouARede = () => { clearTimeout(espera); void conferir(0) }
    window.addEventListener('online', voltouARede)
    return () => { parar = true; clearTimeout(espera); window.removeEventListener('online', voltouARede) }
  }, [status, router, update])

  // primeira carga, sem nenhuma sessão vista ainda: espera
  if (status === 'loading' && !ultimaSessao.current) {
    return (
      <div className="flex items-center justify-center h-screen bg-void">
        <LoadingSpinner text="Carregando..." size="lg" />
      </div>
    )
  }

  // já tinha sessão nesta aba: a tela continua de pé enquanto confere (nada some da frente da pessoa)
  if (!session && !ultimaSessao.current) return null

  return (
    <>
      {reconectando && (
        <div role="status" className="fixed top-2 left-1/2 -translate-x-1/2 z-[100] rounded-full px-4 py-1.5 text-[13px] shadow-lg"
             style={{ background: '#B45309', color: '#fff' }}>
          Sem conexão com o servidor. Reconectando…
        </div>
      )}
      {children}
    </>
  )
}
