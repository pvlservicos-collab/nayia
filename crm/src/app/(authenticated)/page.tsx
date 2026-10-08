import { redirect } from 'next/navigation'

/*
 * O ENDEREÇO "/" (Pedro, 08/10/2026): "retire a aba início, deixe quando a pessoa logar já abre no whatsapp
 * parceria". A aba Início saiu do menu e quem chega aqui -- pelo login, pelo logo, por um favorito antigo --
 * vai direto para a Parceria. O painel de números que morava neste endereço continua em /inicio.
 */
export default function Raiz() {
  redirect('/chat/parceria')
}
