'use client'

/**
 * Chama `acao` de tempos em tempos — o "tempo real" do CRM enquanto não há um.
 *
 * O CRM foi feito em cima do Pusher, mas o app do Pusher configurado não existe
 * mais (a API responde 404) e a Vercel de produção nem tinha as chaves. Resultado:
 * nenhum evento chegava — a lista de conversas não se reordenava, mensagem nova
 * não aparecia sem recarregar, e os sons de lead novo nunca tocaram. Buscar de
 * novo a cada poucos segundos é o que funciona hoje, sem serviço externo nenhum.
 *
 * Com a aba escondida o intervalo PARA (ninguém está vendo a lista), e ao voltar
 * pra aba ele roda na hora — quem volta pro CRM vê o estado atual, não o de dois
 * minutos atrás. `mesmoEscondido` desliga essa pausa pra quem precisa avisar
 * justamente quando ninguém está olhando (os sons).
 */
import { useEffect, useRef } from 'react'

export function useAtualizacaoPeriodica(
  acao: () => void,
  intervaloMs: number,
  opcoes: { ativo?: boolean; mesmoEscondido?: boolean } = {}
) {
  const { ativo = true, mesmoEscondido = false } = opcoes
  const acaoRef = useRef(acao)
  acaoRef.current = acao

  useEffect(() => {
    if (!ativo || typeof window === 'undefined') return

    let timer: ReturnType<typeof setInterval> | null = null
    const visivel = () => mesmoEscondido || document.visibilityState === 'visible'

    const ligar = () => {
      if (timer || !visivel()) return
      timer = setInterval(() => acaoRef.current(), intervaloMs)
    }
    const desligar = () => {
      if (timer) clearInterval(timer)
      timer = null
    }

    const aoMudarVisibilidade = () => {
      if (visivel()) {
        acaoRef.current() // voltou pra aba: atualiza já, sem esperar o próximo ciclo
        ligar()
      } else {
        desligar()
      }
    }

    ligar()
    document.addEventListener('visibilitychange', aoMudarVisibilidade)
    window.addEventListener('focus', aoMudarVisibilidade)
    return () => {
      desligar()
      document.removeEventListener('visibilitychange', aoMudarVisibilidade)
      window.removeEventListener('focus', aoMudarVisibilidade)
    }
  }, [ativo, intervaloMs, mesmoEscondido])
}
