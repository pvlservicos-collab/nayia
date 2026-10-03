-- 281 (03/10/2026): A LISTA POSTADA NOS GRUPOS GUARDA O ID DE CADA MENSAGEM.
--
-- Pedro, 03/10: "a nay não está lendo o card do grupo para responder ao corretor que marcou o card no pv dela".
-- O card de um imóvel postado no grupo já tinha o id guardado em `envios` (destino 'grupo') e a citação vira o
-- código por igualdade. A LISTA ("🔥 APARTAMENTOS PARA LOCAÇÃO DE 1.1k A 10k 🔥", vagas das 07:00 e 19:00 em ~18
-- grupos) saía sem registro nenhum: a Marciléia marcou a lista às 07:10 e escreveu "Esse conquista rionegro!"; a
-- Nay não tinha como saber de que mensagem ela falava.
--
-- POR QUE NÃO EM `envios`: umas 25 funções da Nay velha leem `envios` (citação, frente, ofertas, histórico do
-- CRM, métrica da agenda). `nay_imovel_da_citacao` pega UM código por id: numa lista de 15 seria um qualquer.
-- Esta tabela só é lida pela Nay nova (nay-core, `codigos_da_citacao`), que pergunta qual quando a lista tem
-- mais de um e resolve pelo nome ou pela ordem que ele escreveu.
--
-- Quem escreve: o publicador (`_disparar_lista`), depois de cada pedaço enviado, uma linha por imóvel do pedaço.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.envios_lista_grupo (
  id          bigserial PRIMARY KEY,
  message_id  text NOT NULL,
  codigo      integer NOT NULL,
  posicao     integer NOT NULL,          -- a ordem do imóvel no pedaço da lista (1, 2, 3...)
  grupo_id    text,
  grupo_nome  text,
  categoria   text,
  negocio     text,
  enviado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS envios_lista_grupo_msg ON public.envios_lista_grupo (message_id);
CREATE INDEX IF NOT EXISTS envios_lista_grupo_quando ON public.envios_lista_grupo (enviado_em);

COMMENT ON TABLE public.envios_lista_grupo IS
  'Cada imóvel de cada pedaço de lista que o publicador postou nos grupos, com o id da mensagem (281, 03/10/2026). Só a Nay nova lê: a citação de uma lista vira os códigos dela, na ordem.';

GRANT SELECT ON public.envios_lista_grupo TO nay_core, nay_leitura;

COMMIT;
