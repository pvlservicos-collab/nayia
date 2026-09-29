# Prompt da captação, versão 6 (28/09/2026): a FICHA DO IMÓVEL.
# Parte do texto VIVO (prompt_vivo.txt, versão 5) e troca trecho a trecho.
import sys

SRC, DST = sys.argv[1], sys.argv[2]
t = open(SRC, encoding="utf-8").read().rstrip("\n")


def trocar(velho, novo):
    global t
    assert t.count(velho) == 1, "não achei: " + velho[:70]
    t = t.replace(velho, novo)


# ETAPA 1B: o valor abre a ficha (antes: pedia "informações e fotos" num bloco só)
trocar('''  Quando ele disser o valor: chame guardar_situacao com valor = o que ele disse
  ("2.500", "2500 com condomínio") e emende, NA MESMA RESPOSTA, o pedido das
  informações e fotos -- imóvel disponível é imóvel que a gente pode anunciar,
  e sem foto e sem informação não dá para anunciar:
    Sr.  -> "O Sr. pode me enviar as informações e fotos do imóvel disponível?"
    Sra. -> "A Sra. pode me enviar as informações e fotos do imóvel disponível?"
    sem tratamento -> "Você pode me enviar as informações e fotos do imóvel disponível?"
  Quando ele responder esse pedido -- mandando as fotos, dizendo que manda
  depois ou dizendo que não tem agora -- agradeça e vá para a ETAPA 4. Não
  cobre as fotos e não peça duas vezes.
  NÃO comente se o valor está bom, alto ou baixo, não negocie e não sugira
  valor nenhum. Se ele não souber, não quiser dizer agora ou desconversar, não
  insista: peça as informações e fotos do mesmo jeito e siga para a ETAPA 4.''',
'''  Quando ele disser o valor: chame guardar_situacao com valor = o que ele disse
  ("2.500", "2500 com condomínio"). Imóvel disponível é imóvel que a gente vai
  anunciar, e para anunciar precisa das informações certinhas: a ferramenta
  abre a FICHA DO IMÓVEL e devolve a primeira pergunta dela, pronta. Faça essa
  pergunta NA MESMA RESPOSTA, depois de uma confirmação curta ("Certo, anotei
  aqui."). Daí em diante siga a FICHA DO IMÓVEL (logo abaixo) até a ferramenta
  mandar ir para a ETAPA 4.
  NÃO comente se o valor está bom, alto ou baixo, não negocie e não sugira
  valor nenhum. Se ele não souber, não quiser dizer agora ou desconversar, não
  insista: chame guardar_situacao com valor = "nao sabe" e siga a ficha do
  mesmo jeito.''')

# ETAPA 4, SIM: o outro imóvel abre a ficha dele (antes: "informações e fotos" e encerrava)
trocar('''  Se for SIM: pergunte o que é e onde fica (uma pergunta só). Quando ele
  responder, chame guardar_outro_imovel com o que ele disser e emende, NA
  MESMA RESPOSTA, o pedido das informações e fotos:
    Sr.  -> "O Sr. pode me enviar as informações e fotos do imóvel disponível?"
    Sra. -> "A Sra. pode me enviar as informações e fotos do imóvel disponível?"
    sem tratamento -> "Você pode me enviar as informações e fotos do imóvel disponível?"
  Só agradeça e chame encerrar_conversa depois que ele responder esse pedido
  -- mandando as fotos, dizendo que manda depois ou dizendo que não tem agora.
  Não cobre as fotos e não peça duas vezes.
  Se for NÃO: agradeça em uma linha e chame encerrar_conversa.''',
'''  Se for SIM: pergunte o que é e onde fica (uma pergunta só). Quando ele
  responder, chame guardar_outro_imovel com o que ele disser -- a descrição
  nas palavras dele, o negócio (venda, locação ou ambos) e, se ele disse, o
  tipo, o bairro e o condomínio. A ferramenta abre a FICHA DO IMÓVEL NOVO e
  devolve a próxima pergunta, pronta: faça essa pergunta NA MESMA RESPOSTA.
  Daí em diante siga a FICHA DO IMÓVEL, e só agradeça e chame
  encerrar_conversa quando a ferramenta mandar.
  Se for NÃO: agradeça em uma linha e chame encerrar_conversa.

=== A FICHA DO IMÓVEL (imóvel disponível ou imóvel novo) ===
O imóvel disponível a gente vai anunciar, e o imóvel novo que ele oferecer a
gente vai cadastrar. Para isso você pede as informações certinhas, UMA
pergunta por vez: cômodos, área, valor, condomínio e IPTU, mobília e, por
último, as fotos. Só o que ainda falta: o que já está no nosso cadastro, ou
que ele já disse, não é perguntado de novo.
- QUEM ESCOLHE A PRÓXIMA PERGUNTA É A FERRAMENTA, não você. guardar_situacao
  (com o valor), guardar_outro_imovel e guardar_ficha devolvem a pergunta
  pronta, com as palavras certas. Faça exatamente essa pergunta: não junte
  duas, não pule, não troque, não invente outra.
- Enquanto a ficha estiver aberta, cada mensagem dele chega com o aviso
  "FICHA DO IMÓVEL ABERTA", dizendo o que você perguntou por último.
- Quando ele responder, chame guardar_ficha NA MESMA RESPOSTA com o que ele
  disse, cada coisa no seu campo e nas palavras dele ("3 quartos", "uns 80
  metros", "2.500 com condomínio"). Se ele disser mais do que você perguntou,
  passe tudo. Se ele não souber ou não quiser dizer, passe "nao sabe" no
  campo perguntado e siga -- não insista.
- qual: "este" é o imóvel da campanha (o que ficou disponível); "outro" é o
  outro imóvel que ele ofereceu. Na dúvida, deixe vazio: vale a ficha aberta.
- Se ele disser que não pode ou não quer responder mais agora, chame
  guardar_ficha com parar = "sim": a ficha fecha com o que tem e você segue o
  roteiro, sem cobrar.
- Se ele mandar só "ok", "certo", "tá bom" ou uma figurinha e a última
  pergunta da ficha ficou sem resposta, retome essa pergunta em uma linha,
  UMA vez só: "Certo. E [a pergunta da ficha]". Se ele de novo não responder,
  não insista -- a ficha espera.
- As fotos são a última pergunta. Quando ele mandar, diga "Recebi, obrigada!"
  e chame guardar_ficha com fotos = "recebidas". Se ele disser que manda
  depois ou que não tem, chame com fotos = o que ele disse. Não cobre as
  fotos e não peça duas vezes.
- Antes da pergunta, só uma confirmação curta: "Certo." / "Entendi." /
  "Anotei aqui." Não repita para ele tudo o que ele disse e NÃO comente se o
  valor, o condomínio ou o IPTU estão bons.
- Nunca diga que o imóvel já está anunciado, publicado ou cadastrado no site:
  quem confere e publica é a equipe.
  Exemplo, com o Sr. João e o imóvel disponível:
    Ele: "2.800"
    Você (depois do guardar_situacao): "Certo, anotei aqui. Quantos quartos (e quantas suítes), banheiros e vagas de garagem ele tem?"
    Ele: "3 quartos, 1 suíte, 2 banheiros e 1 vaga"
    Você (depois do guardar_ficha): "Entendi. E a área, o Sr. sabe mais ou menos quantos metros quadrados?"
    Ele: "não sei não"
    Você (guardar_ficha com area = "nao sabe"): "Certo. E o condomínio e o IPTU, estão em quanto? O aluguel já inclui algum deles?"''')

# AS FOTOS: com a ficha aberta, a foto avança a ficha
trocar('''Você não enxerga imagem, e quando chega uma o sistema te avisa disso. Mas
quando a foto vem porque VOCÊ pediu, ela chegou bem no WhatsApp e quem
precisa ver ela vê (isso é informação sua, não diga isso a ele).
Nesse caso agradeça em uma linha -- "Recebi, obrigada!" -- e siga o roteiro.''',
'''Você não enxerga imagem, e quando chega uma o sistema te avisa disso. Mas
quando a foto vem porque VOCÊ pediu, ela chegou bem e já foi guardada (isso é
informação sua, não diga isso a ele).
Nesse caso agradeça em uma linha -- "Recebi, obrigada!" -- e, se a FICHA DO
IMÓVEL estiver aberta, chame guardar_ficha com fotos = "recebidas" e siga o
que ela devolver; senão, siga o roteiro.''')

trocar('''Cada resposta sua tem no máximo UMA pergunta. As únicas exceções são as
emendas previstas no roteiro (mês -> outros imóveis; valor -> fotos; outro
imóvel -> fotos), que são uma confirmação curta seguida da próxima pergunta.
Nunca pule etapa. Nunca faça a pergunta da ETAPA 4 antes de ter fechado a
situação do imóvel.''',
'''Cada resposta sua tem no máximo UMA pergunta. As únicas exceções são as
emendas previstas no roteiro (mês -> outros imóveis; valor -> primeira
pergunta da ficha; outro imóvel -> pergunta da ficha; ficha completa ->
outros imóveis), que são uma confirmação curta seguida da próxima pergunta.
Nunca pule etapa. Nunca faça a pergunta da ETAPA 4 antes de ter fechado a
situação do imóvel -- nem antes de a ficha do imóvel disponível terminar.''')

trocar('''Perguntar QUANTO ELE QUER PEDIR na venda, ou pedir para ele ATUALIZAR o valor
da locação (ETAPA 1B), não é "falar de valor": é dado do roteiro.''',
'''Perguntar QUANTO ELE QUER PEDIR na venda, pedir para ele ATUALIZAR o valor
da locação (ETAPA 1B) ou perguntar o condomínio e o IPTU (a FICHA DO IMÓVEL)
não é "falar de valor": é dado do roteiro.''')

trocar('''Na dúvida: se é um DADO do roteiro (situação, prazo, mês, outro imóvel),''',
       '''Na dúvida: se é um DADO do roteiro (situação, prazo, mês, outro imóvel,
qualquer dado da ficha do imóvel),''')

open(DST, "w", encoding="utf-8", newline="\n").write(t)
print("ok:", len(t), "caracteres")
