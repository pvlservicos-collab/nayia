-- 344 -- Colunas novas para a reforma da aba Imóveis / Condomínio (só DDL, curto; a mudança de DADO é a 345)
--
-- Pedro, 11/10/2026: o andar/unidade por tipo de imóvel; características por tipo; mobília em 4 níveis (sem nada,
-- só climatizado, com modulados e ar, mobiliado); uma OBSERVAÇÃO do imóvel que vai no card; as características do
-- condomínio NA ABA CONDOMÍNIO (lazer, segurança, comodidades, taxas por quartos, ano, construtora) e não misturadas
-- com as do imóvel; o imóvel só mostra o condomínio e tem o botão "Editar condomínio".
--
-- DDL fora de ensaio de propósito (ALTER TABLE em ensaio travou a Nay 2 min em 09/10): tudo com IF NOT EXISTS,
-- lock_timeout de 3 s, e só acrescenta coluna (NULL/DEFAULT): nada muda nos dados.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- o imóvel
ALTER TABLE imoveis
  ADD COLUMN IF NOT EXISTS observacao text,          -- "falta só TV, o dono negocia mobília"; vai no card
  ADD COLUMN IF NOT EXISTS cobertura  boolean;        -- apartamento/sala: é cobertura? (o tipo Linear/Duplex segue em extras)
COMMENT ON COLUMN imoveis.observacao IS '344: informação valiosa do imóvel (vista, negociação, o que falta); vai junto no card ao corretor.';
COMMENT ON COLUMN imoveis.cobertura IS '344: só apartamento e sala; diz se é cobertura. O tipo (Linear/Duplex/Triplex) fica em extras.tipo de cobertura.';

-- o condomínio: o que o site antigo tinha (as duas telas do Pedro) e o novo não
ALTER TABLE condominio_ficha
  ADD COLUMN IF NOT EXISTS seguranca      text[]  NOT NULL DEFAULT '{}',   -- Condomínio fechado, Guarita 24 Horas...
  ADD COLUMN IF NOT EXISTS comodidades    text[]  NOT NULL DEFAULT '{}',   -- Elevador, Lavanderia, Gerador, Gás Encanado, Água de Poço
  ADD COLUMN IF NOT EXISTS taxas          jsonb   NOT NULL DEFAULT '[]',   -- [{"quartos": 3, "condominio": 648, "iptu": 980}]
  ADD COLUMN IF NOT EXISTS ano_construcao text,                            -- "2011 e 2013" (o site antigo escreve assim)
  ADD COLUMN IF NOT EXISTS observacao     text,
  ADD COLUMN IF NOT EXISTS complemento    text,                            -- "próx. ao Condomínio Flex Parque Dez"
  ADD COLUMN IF NOT EXISTS site_antigo_id integer;                         -- /admin/condominios/<id> do imobeasy.com
COMMENT ON COLUMN condominio_ficha.taxas IS '344: taxa de condomínio por quartos (fixa para todos os imóveis daquele tamanho) e, quando fixo, o IPTU. O IPTU por casa fica no imóvel.';

-- quem lê: o site (público e admin) e o núcleo da Nay (o RAG responde pelo condomínio)
GRANT SELECT (observacao, cobertura) ON imoveis TO nay_site_leitura;
GRANT SELECT (observacao, cobertura), UPDATE (observacao, cobertura), INSERT (observacao, cobertura) ON imoveis TO nay_site_escrita;
GRANT SELECT ON condominio_ficha TO nay_core, nay_site_escrita;

-- os quatro níveis de mobília, num lugar só. `nivel` lê QUALQUER redação (as de hoje e as antigas) e devolve
-- nada | climatizado | semi | mobiliado; `rotulo` é como se escreve no cadastro.
CREATE OR REPLACE FUNCTION public.nay_mobilia_nivel(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN coalesce(btrim(p), '') = '' THEN NULL
    WHEN lower(unaccent(p)) ~ '^\s*(sem (nada|mobilia|moveis)|vazi|nenhum|nao mobiliad|desmobiliad)' THEN 'nada'
    WHEN lower(unaccent(p)) ~ '^\s*(so |somente )?(climatizad|ar.condicionado)|^\s*so ar' THEN 'climatizado'
    WHEN lower(unaccent(p)) ~ '^\s*semi|modulad' THEN 'semi'
    WHEN lower(unaccent(p)) ~ '^\s*mobiliad' THEN 'mobiliado'
    ELSE NULL END
$$;
CREATE OR REPLACE FUNCTION public.nay_mobilia_rotulo(p_nivel text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_nivel WHEN 'nada' THEN 'sem nada' WHEN 'climatizado' THEN 'só climatizado'
                      WHEN 'semi' THEN 'com modulados e ar' WHEN 'mobiliado' THEN 'mobiliado' END
$$;
GRANT EXECUTE ON FUNCTION public.nay_mobilia_nivel(text), public.nay_mobilia_rotulo(text) TO PUBLIC;

-- o que a 345 vai mudar fica guardado ANTES, para desfazer linha a linha
CREATE TABLE IF NOT EXISTS privado.imovel_antes_345 (
  codigo integer PRIMARY KEY, mobilia text, area_total numeric, caracteristicas text[], extras_condominio jsonb,
  condo_id integer, observacao text, guardado_em timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS privado.condominio_ficha_antes_345 (LIKE condominio_ficha INCLUDING ALL);

COMMIT;
