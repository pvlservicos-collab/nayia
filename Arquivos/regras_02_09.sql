-- As regras que saíram das duas conversas de 01/09 à noite (Waldyrene e
-- Alice). Cada uma tem um caso real atrás, e a maioria já tem PAREDE
-- correspondente -- a regra aqui é o texto que o modelo lê, a parede é o
-- que acontece quando ele erra mesmo assim.
--
--   docker cp regras_02_09.sql nay-postgres:/tmp/r.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/r.sql
--   .venv/bin/python sincronizar_regras.py --escrever   # e importar o fluxo

INSERT INTO regras (texto, contexto, ativa) VALUES

-- Waldyrene, 22h02: a cliente queria o Life Parque 10 (Parque 10 de
-- Novembro) e recebeu quatro cards do Acquarelle (Ponta Negra). Parede:
-- `nay_bairros_proximos`, dentro do `buscar_por_perfil`.
('Imóvel de outro bairro só entra na conversa se for VIZINHO do que o cliente '
 || 'pediu, e você diz o bairro de cada um. Nunca ofereça imóvel de outra região '
 || 'da cidade: quem procura no Parque 10 não quer Ponta Negra. Se você não sabe '
 || 'se é perto, não ofereça.',
 'bairro', true),

-- O que fazer quando não tem: qualificar, em vez de empurrar qualquer coisa.
('Quando não temos nada no perfil pedido, faça as três perguntas na mesma '
 || 'mensagem: até que valor o cliente vai, quantos quartos precisa e quais '
 || 'bairros aceita. Só depois disso escale ao Tel como demanda não atendida. '
 || 'Não fique repetindo que não tem, e não ofereça o que estiver à mão.',
 'bairro', true),

-- Waldyrene, 22h02: "os dois acquareles locacao é o de 02 e 03 quartos" +
-- "me evia os de venda tambem" -> mandou só os de venda.
('Se o corretor pediu duas coisas no mesmo turno, responda as DUAS antes de '
 || 'encerrar. Venda e locação juntos: chame a ferramenta uma vez para cada e '
 || 'mande os dois. Se de um deles não houver nada, diga isso com todas as '
 || 'letras -- calar sobre um faz ele achar que você esqueceu.',
 'atendimento', true),

-- Alice, 22h00: "Cliente gostaria de agendar uma visita" + "Está
-- disponível?" -> ela pediu o código, mandou o card, e não falou da visita.
('Pedido de visita se responde falando da visita. Mandar o card do imóvel não '
 || 'responde "posso agendar?". Use avaliar_visita, diga se pode, o que ele '
 || 'precisa fazer e o que você precisa saber -- e nunca encerre o turno sem '
 || 'ter falado disso.',
 'visita', true),

-- Waldyrene, 22h01: "o life pq 10 da loc ainda ta disponiveis" -- ela
-- respondeu sem ter olhado. Parede: `disponibilidade_no_condominio`.
('Antes de dizer se um imóvel ou condomínio está disponível, consulte. Nunca '
 || 'responda disponibilidade de memória nem pelo que foi dito antes na conversa: '
 || 'o que vale é o que a ferramenta devolveu agora.',
 'disponibilidade', true)

ON CONFLICT DO NOTHING;
