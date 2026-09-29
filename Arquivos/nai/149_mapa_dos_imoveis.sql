-- =====================================================================
-- 149 — O MAPA DOS IMÓVEIS E OS BAIRROS AO REDOR (28/09/2026)
--
-- Tel: "lá nos imóveis quero adicionar o mapa agora... um mapa focado na
-- cidade de Manaus, e implemente lá a localização próxima de todos os nossos
-- imóveis, todos divididinhos por bairro... para termos a relação de bairros
-- ao redor do imóvel pronta e precisa para usarmos depois, cada imóvel vai
-- ser um card point no mapa clicável".
--
-- Só tabelas NOVAS -- nada que a Nay usa hoje muda. Quem preenche é
-- /root/nay-publicador/geocodificar_imoveis.py:
--   geo_bairro              os bairros oficiais de Manaus (contorno do
--                           OpenStreetMap) e os que só existem como lugar
--   geo_bairro_nome         como o nosso cadastro escreve -> o bairro oficial
--   geo_bairro_vizinho      quem faz divisa com quem (e a distância dos centros)
--   imovel_geo              o ponto de cada imóvel nosso, com a PRECISÃO dele:
--                           'condominio' (o condomínio está no mapa), 'rua' (a
--                           rua, dentro do bairro certo) ou 'bairro' (o centro
--                           do bairro, quando nem a rua foi achada)
--   imovel_bairro_ao_redor  os bairros a até 2 km do ponto do imóvel -- medido
--                           até a BORDA do bairro, não até o centro
--   geo_consulta            o que já foi perguntado ao geocodificador (a regra
--                           do serviço gratuito é guardar e não perguntar de novo)
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS geo_bairro (
  bairro        text PRIMARY KEY,           -- o nome oficial (como está no OpenStreetMap)
  osm_id        bigint,
  lat           double precision NOT NULL,  -- um ponto DENTRO do bairro (o rótulo no mapa)
  lon           double precision NOT NULL,
  poligono      jsonb,                      -- GeoJSON simplificado; NULL = só temos o lugar
  area_km2      numeric(8, 2),
  fonte         text NOT NULL CHECK (fonte IN ('osm_limite', 'osm_lugar')),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS geo_bairro_nome (
  nome_cadastro text PRIMARY KEY,            -- "Dom Pedro", "Parque 10 de Novembro"...
  bairro        text NOT NULL REFERENCES geo_bairro (bairro) ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS geo_bairro_vizinho (
  bairro   text NOT NULL REFERENCES geo_bairro (bairro) ON UPDATE CASCADE ON DELETE CASCADE,
  vizinho  text NOT NULL REFERENCES geo_bairro (bairro) ON UPDATE CASCADE ON DELETE CASCADE,
  divisa   boolean NOT NULL,                 -- os contornos se encostam
  km       numeric(6, 2) NOT NULL,           -- entre os centros
  PRIMARY KEY (bairro, vizinho)
);

CREATE TABLE IF NOT EXISTS imovel_geo (
  codigo           integer PRIMARY KEY,
  lat              double precision NOT NULL,
  lon              double precision NOT NULL,
  precisao         text NOT NULL CHECK (precisao IN ('condominio', 'rua', 'bairro')),
  bairro           text,                     -- o bairro oficial onde o ponto cai
  consulta         text,                     -- o que foi perguntado (ou 'centro do bairro X')
  fonte            text NOT NULL,            -- 'nominatim' | 'centro_do_bairro'
  geocodificado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS imovel_geo_bairro ON imovel_geo (bairro);

CREATE TABLE IF NOT EXISTS imovel_bairro_ao_redor (
  codigo  integer NOT NULL,
  bairro  text NOT NULL,
  km      numeric(6, 2) NOT NULL,            -- 0 = o imóvel está dentro dele
  dentro  boolean NOT NULL,
  PRIMARY KEY (codigo, bairro)
);
CREATE INDEX IF NOT EXISTS imovel_bairro_ao_redor_bairro ON imovel_bairro_ao_redor (bairro, km);

CREATE TABLE IF NOT EXISTS geo_consulta (
  consulta  text PRIMARY KEY,
  resposta  jsonb,
  em        timestamptz NOT NULL DEFAULT now()
);

-- A API do site lê o mapa pelo usuário de leitura; o resto não.
GRANT SELECT ON geo_bairro, geo_bairro_nome, geo_bairro_vizinho, imovel_geo, imovel_bairro_ao_redor TO nay_site_leitura;

COMMIT;
