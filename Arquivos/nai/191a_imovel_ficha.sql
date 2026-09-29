-- 191a -- a ficha do anúncio, guardada (29/09/2026). Ver ficha_do_anuncio.py.
--
-- Tabela nova, sem trava em nada que existe. Quem escreve é só o carregador
-- (a cada 3 h); quem lê é a Nay (`nai_ficha_valor`, `nai_ficha_completa`,
-- `nai_resposta_da_base`, `nai_card_do_imovel`).

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS imovel_ficha (
  codigo                     int PRIMARY KEY,
  encontrado                 boolean NOT NULL DEFAULT true,   -- false = o site não tem mais o anúncio
  campos                     jsonb NOT NULL DEFAULT '{}',     -- rótulo normalizado -> valor, visível e comentado
  caracteristicas_imovel     text[] NOT NULL DEFAULT '{}',
  caracteristicas_condominio text[] NOT NULL DEFAULT '{}',
  descricao                  text,
  observacoes                text,
  card                       text,                            -- o card dos grupos (montar_mensagem)
  valor_venda                numeric,                         -- o que a página dizia quando o card foi montado
  valor_aluguel              numeric,
  lido_em                    timestamptz,                     -- última leitura BOA
  tentado_em                 timestamptz NOT NULL DEFAULT now(),
  erro                       text
);
COMMENT ON TABLE imovel_ficha IS
  '191: a ficha completa do anúncio (imobeasy.com/anuncios/<codigo>), lida por ficha_do_anuncio.py a cada 3 h. É a base que a Nay consulta para responder sobre o imóvel.';

COMMIT;
