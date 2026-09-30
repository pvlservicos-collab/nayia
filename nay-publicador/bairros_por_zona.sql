-- A zona de cada bairro, para ela não oferecer o outro lado da cidade.
--
-- O CASO (Waldyrene, 01/09, 22h02): a cliente dela queria o **Life Parque
-- 10**, no Parque 10 de Novembro. A Nay mandou quatro cards do
-- **Acquarelle, em Ponta Negra**. O Tel: "a ponta negra aonde fica o
-- acquarelle fica distante do parque dez... a ideia é enviar imóvel nos
-- bairros ao lado somente".
--
-- POR QUE UMA TABELA E NÃO REGRA NO PROMPT: distância entre bairros é
-- dado, não bom-senso -- o modelo não sabe a geografia de Manaus, e
-- escrever "não ofereça bairro distante" não ensina qual é distante.
-- Aqui a consulta já devolve só o que é perto.
--
-- ATENÇÃO, TEL: este agrupamento é o zoneamento administrativo de Manaus
-- e **precisa da sua conferência**. Onde eu errei, é um UPDATE, sem
-- deploy:
--   UPDATE bairro_zona SET zona = 'centro-sul' WHERE bairro = 'Aleixo';
-- E para dizer que dois bairros são vizinhos apesar de zonas diferentes:
--   INSERT INTO bairro_vizinho VALUES ('Ponta Negra','Tarumã');
--
--   docker cp bairros_por_zona.sql nay-postgres:/tmp/bz.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/bz.sql

CREATE TABLE IF NOT EXISTS bairro_zona (
  bairro text PRIMARY KEY,
  zona   text NOT NULL
);

-- Vizinhança explícita, para os pares que a zona não pega. Vale nos dois
-- sentidos -- a função cuida disso.
CREATE TABLE IF NOT EXISTS bairro_vizinho (
  bairro  text NOT NULL,
  vizinho text NOT NULL,
  PRIMARY KEY (bairro, vizinho)
);

INSERT INTO bairro_zona (bairro, zona) VALUES
  ('Ponta Negra','oeste'), ('Tarumã','oeste'), ('Tarumã-Açu','oeste'),
  ('Lírio do Vale','oeste'), ('Compensa','oeste'), ('Santo Antônio','oeste'),
  ('São Jorge','oeste'), ('São Geraldo','oeste'), ('Nova Esperança','oeste'),
  ('Vila da Prata','oeste'), ('São Raimundo','oeste'), ('Glória','oeste'),

  ('Parque 10 de Novembro','centro-sul'), ('Aleixo','centro-sul'),
  ('Adrianópolis','centro-sul'), ('Chapada','centro-sul'),
  ('Nossa Senhora das Graças','centro-sul'), ('Flores','centro-sul'),
  ('São Francisco','centro-sul'), ('Petrópolis','centro-sul'),
  ('Parque das Laranjeiras','centro-sul'),

  ('Centro','sul'), ('Praça 14 de Janeiro','sul'), ('Educandos','sul'),
  ('Japiim','sul'), ('Distrito Industrial I','sul'), ('Santa Luzia','sul'),
  ('Cachoeirinha','sul'), ('Presidente Vargas','sul'),
  ('Raiz','sul'), ('Crespo','sul'), ('Colônia Santo Antônio','norte'),

  ('Alvorada','centro-oeste'), ('Dom Pedro','centro-oeste'),
  ('Planalto','centro-oeste'), ('Da Paz','centro-oeste'),
  ('Redenção','centro-oeste'), ('Santo Agostinho','centro-oeste'),

  ('Cidade Nova','norte'), ('Cidade de Deus','norte'),
  ('Colônia Terra Nova','norte'), ('Nova Cidade','norte'),
  ('Santa Etelvina','norte'), ('Lago Azul','norte'), ('Novo Israel','norte'),
  ('Monte das Oliveiras','norte'), ('Novo Aleixo','norte'),

  ('Coroado','leste'), ('Zumbi dos Palmares','leste'),
  ('São José Operário','leste'), ('Jorge Teixeira','leste'),
  ('Tancredo Neves','leste'), ('Armando Mendes','leste'),
  ('Mauazinho','leste'), ('Puraquequara','leste'),
  ('Distrito Industrial II','leste')
ON CONFLICT (bairro) DO NOTHING;

-- Vizinhanças que cruzam zona. Estas são as que interessam ao catálogo:
-- Ponta Negra e Tarumã são zona oeste e ficam coladas; o Parque 10 faz
-- divisa com o Aleixo e com a Chapada, que já são da mesma zona.
INSERT INTO bairro_vizinho (bairro, vizinho) VALUES
  ('Ponta Negra','Tarumã'), ('Ponta Negra','Tarumã-Açu'),
  ('Tarumã','Tarumã-Açu'),
  ('Parque 10 de Novembro','Aleixo'), ('Parque 10 de Novembro','Chapada'),
  ('Parque 10 de Novembro','Adrianópolis'), ('Parque 10 de Novembro','Flores'),
  ('Parque 10 de Novembro','Parque das Laranjeiras'),
  ('Flores','Cidade Nova'), ('Flores','Da Paz'), ('Flores','Dom Pedro'),
  ('Aleixo','Coroado'), ('Aleixo','Parque das Laranjeiras'),
  ('Adrianópolis','Nossa Senhora das Graças'),
  ('Adrianópolis','Chapada'), ('Chapada','São Geraldo'),
  ('Dom Pedro','Alvorada'), ('Alvorada','Planalto'),
  ('Cidade Nova','Colônia Terra Nova'), ('Cidade Nova','Novo Aleixo'),
  ('Cidade Nova','Lago Azul'), ('Colônia Terra Nova','Lago Azul'),
  ('Nova Cidade','Cidade Nova'), ('Santa Etelvina','Cidade Nova')
ON CONFLICT DO NOTHING;

-- --------------------------------------------------------------------
-- Os bairros que valem como alternativa ao que ele pediu: o próprio, os
-- vizinhos declarados (nos dois sentidos) e o resto da mesma zona.
--
-- A zona entra como rede de segurança: bairro sem vizinho declarado
-- ainda oferece alguma coisa perto, em vez de nada. Bairro que não está
-- em `bairro_zona` devolve só ele mesmo -- e não ter dado é motivo para
-- NÃO oferecer nada de longe, nunca para chutar.
CREATE OR REPLACE FUNCTION nay_bairros_proximos(p_bairro text)
RETURNS text[] LANGUAGE sql STABLE AS $fn$
  WITH alvo AS (
    SELECT z.bairro, z.zona
      FROM bairro_zona z
     WHERE nay_normalizar_lugar(z.bairro, true)
         = nay_normalizar_lugar(coalesce(p_bairro,''), true)
     LIMIT 1
  )
  SELECT array_agg(DISTINCT b ORDER BY b) FROM (
    SELECT bairro AS b FROM alvo
    UNION SELECT v.vizinho FROM bairro_vizinho v JOIN alvo a ON v.bairro = a.bairro
    UNION SELECT v.bairro  FROM bairro_vizinho v JOIN alvo a ON v.vizinho = a.bairro
    UNION SELECT z.bairro  FROM bairro_zona z JOIN alvo a ON z.zona = a.zona
  ) s;
$fn$;

-- Só para o texto: "Ponta Negra fica longe do Parque 10 de Novembro".
CREATE OR REPLACE FUNCTION nay_bairro_e_perto(p_a text, p_b text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
  SELECT coalesce(
    EXISTS (
      SELECT 1 FROM unnest(coalesce(nay_bairros_proximos(p_a), ARRAY[]::text[])) x
       WHERE nay_normalizar_lugar(x, true) = nay_normalizar_lugar(coalesce(p_b,''), true)
    ), false);
$fn$;
