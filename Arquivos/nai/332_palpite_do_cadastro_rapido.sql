-- 332 -- Cadastro rápido: "O que a IA supõe que é" (o palpite de cada item da fila)
--
-- Pedro, 09/10/2026: "quero que você prejulgue em categorias analisando, e crie uma categoria com cores lá, 'O que a IA
-- supõe que é', e separe os julgamentos em ordem por categorias, selecionáveis no meio das setas lá em cima por uma
-- lista suspensa".
--
-- O serviço nay-captacao (captacao/palpite.py, junto com o preparar, de 5 em 5 minutos) manda cada item de
-- nai_cadastro_pendente() ao modelo -- a ficha, a conversa, os outros imóveis do dono, os parecidos da fila -- e guarda
-- aqui UMA categoria e o porquê:
--   novo          imóvel novo para anunciar
--   atualizacao   atualização de imóvel que já temos
--   completar     cadastro nosso para completar (foto, bairro, área, valor)
--   indisponivel  alugado, vendido, em obra: não é para anunciar agora
--   repetido      o mesmo imóvel de outro item da fila
--   nao_e         não há imóvel para cadastrar
-- `base` é o resumo (md5) do que foi lido: mudou a ficha, a situação ou as fotos, o palpite é refeito.
-- A tela (site e CRM) só lê. Nada no cadastro muda por causa do palpite: é triagem.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.cadastro_rapido_palpite (
  fonte         text NOT NULL CHECK (fonte IN ('ficha', 'imovel')),
  item          bigint NOT NULL,                 -- o id da ficha (captacao_cadastro) ou o código do imóvel
  categoria     text NOT NULL CHECK (categoria IN ('novo', 'atualizacao', 'completar', 'indisponivel', 'repetido', 'nao_e')),
  porque        text,
  base          text NOT NULL,
  analisado_em  timestamptz NOT NULL DEFAULT now(),
  modelo        text,
  PRIMARY KEY (fonte, item)
);
COMMENT ON TABLE public.cadastro_rapido_palpite IS
  '332: o palpite da IA para cada item da fila do Cadastro rápido (nay-captacao/captacao/palpite.py). Só triagem: a tela ordena e filtra por ele.';
GRANT SELECT ON public.cadastro_rapido_palpite TO nay_leitura, nay_site_leitura, nay_site_escrita;

COMMIT;
