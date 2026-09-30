-- 206 (Pedro, 30/09/2026): A BIBLIOTECA DE LUGARES -- CONJUNTOS E AVENIDAS.
-- "Em Manaus existem conjuntos, cada conjunto é em um bairro; preciso que a Nay
--  entenda que quando algum corretor perguntar de algum conjunto ela entenda que
--  ele quer imóveis desse conjunto, que é dentro desse bairro, e ela mande imóveis
--  do bairro." E em seguida: "a biblioteca de avenidas: quando alguém pedir
--  avenida, aqui está o relacionamento dos bairros" (as duas listas dele, abaixo).
--
-- DUAS TABELAS, porque conjunto é UM bairro e avenida é VÁRIOS:
--   nai_lugar_conjunto  nome -> bairro       (Conjunto Eldorado -> Parque 10 de Novembro)
--   nai_lugar_avenida   nome -> bairros[]    (Av. Mário Ypiranga -> Adrianópolis, N. Sra. das Graças, Parque 10)
-- `expressao` é regex contra o texto sem acento, minúsculo e com pontuação
-- virando espaço ("av. mário ypiranga" -> "av mario ypiranga"). Nome que também
-- é outra coisa exige o prefixo: "Débora" é gente, "31 de março" é data,
-- "Tancredo Neves" é bairro, "Manauara" é adjetivo -- esses só valem com
-- "conjunto ..." ou "av. ...". Nome que só existe como lugar vale sozinho.
--
-- ONDE ENTRA (três camadas):
--   1. Biblioteca: nai_giria_explica ganha "LUGARES": quando ele escreve um
--      conjunto ou avenida, o contexto do modelo diz de que bairro(s) é.
--   2. Busca: nai_buscar_por_perfil procura nos bairros do lugar (e, no
--      conjunto, põe primeiro o condomínio de mesmo nome, se o catálogo tiver);
--      a lista diz "No Parque 10 de Novembro (bairro do Conjunto Eldorado)".
--      Vieiralves continua "No Vieiralves" (regra do Tel de 18/09, bairro_area).
--   3. Fila dos outros imóveis: conjunto citado conta como bairro citado
--      (nai_nome_so_do_bairro, a 147): "Eldorado" não vira o card do Eldorado Park.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS nai_lugar_conjunto (
  nome        text PRIMARY KEY,
  expressao   text NOT NULL,
  bairro      text NOT NULL,
  zona        text,
  avenidas    text,
  ativo       boolean NOT NULL DEFAULT true,
  criado_por  text,
  criado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS nai_lugar_avenida (
  nome        text PRIMARY KEY,
  expressao   text NOT NULL,
  bairros     text[] NOT NULL,
  ativo       boolean NOT NULL DEFAULT true,
  criado_por  text,
  criado_em   timestamptz NOT NULL DEFAULT now()
);

-- prefixos: P = qualquer um (conjunto/residencial/loteamento/condomínio); C = só conjunto
INSERT INTO nai_lugar_conjunto (nome, expressao, bairro, zona, avenidas, criado_por) VALUES
  ('Parque das Laranjeiras',    '\m(parque|pque|pq) (das )?laranjeiras\M',                                   'Flores',                   'centro-sul',  'Av. Professor Nilton Lins / Av. das Torres', 'Pedro 30/09'),
  ('Parque das Nações',         '\m(parque|pque|pq) (das )?nacoes\M',                                        'Flores',                   'centro-sul',  'Av. Max Teixeira / Av. Professor Nilton Lins', 'Pedro 30/09'),
  ('Conjunto Beija-Flor',       '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?beija flor\M', 'Flores',                 'centro-sul',  'Av. Max Teixeira / Av. Professor Nilton Lins', 'Pedro 30/09'),
  ('Morada do Sol',             '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?morada do sol\M', 'Aleixo',               'centro-sul',  'Av. André Araújo / Av. Via Láctea', 'Pedro 30/09'),
  ('Conjunto Petros',           '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?petros\M',    'Aleixo',                   'centro-sul',  'Av. André Araújo / Av. Cosme Ferreira', 'Pedro 30/09'),
  ('Conjunto Tiradentes',       '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) tiradentes|tiradentes residencial)\M', 'Aleixo', 'centro-sul', 'Av. André Araújo / Av. Rodrigo Otávio', 'Pedro 30/09'),
  ('Vieiralves',                '\m(vieiralves|vieira alves)\M',                                                       'Nossa Senhora das Graças', 'centro-sul',  'Av. Djalma Batista / Av. João Valério', 'Pedro 30/09'),
  ('Vila Amazonas',             '\mvila amazonas\M',                                                          'Nossa Senhora das Graças', 'centro-sul',  'Av. Mário Ypiranga / Av. Darcy Vargas', 'Pedro 30/09'),
  ('Conjunto Eldorado',         '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?eldorado\M',  'Parque 10 de Novembro',    'centro-sul',  'Av. Mário Ypiranga / Av. Perimetral', 'Pedro 30/09'),
  ('Conjunto Castelo Branco',   '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?castelo branco\M', 'Parque 10 de Novembro', 'centro-sul', 'Av. Tancredo Neves / Av. Perimetral', 'Pedro 30/09'),
  ('Conjunto Jardim Amazonas',  '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?(jardim|jd) amazonas\M', 'Parque 10 de Novembro', 'centro-sul', 'Av. Mário Ypiranga / Av. Maneca Marques', 'Pedro 30/09'),
  ('Conjunto Celetramazon',     '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?celetramazon\M', 'Adrianópolis',          'centro-sul',  'Av. Mário Ypiranga / Av. Umberto Calderaro', 'Pedro 30/09'),
  ('Conjunto Vila dos Reis',    '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?vila dos reis\M', 'Adrianópolis',         'centro-sul',  'Av. Umberto Calderaro / Av. Ephigênio Salles', 'Pedro 30/09'),
  ('Conjunto Ica Paraíba',      '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?ica paraiba\M', 'Adrianópolis',           'centro-sul',  'Av. Mário Ypiranga / Av. Álvaro Maia', 'Pedro 30/09'),
  ('Conjunto Kissia',           '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?kissia\M',    'Alvorada',                 'centro-oeste', 'Av. Jacira Reis / Av. Desembargador João Machado', 'Pedro 30/09'),
  ('Conjunto Promorar',         '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?promorar\M',  'Alvorada',                 'centro-oeste', 'Av. Alvorada / Av. Constantinopla', 'Pedro 30/09'),
  ('Conjunto Dom Pedro II',     '\m((conjunto|conj|cjto|cj) dom pedro( ii| 2)?|dom pedro ii)\M',          'Dom Pedro',                'centro-oeste', 'Av. Pedro Teixeira / Av. Dom Pedro', 'Pedro 30/09'),
  ('Conjunto Déborah',          '\m(conjunto|conj|cjto|cj|residencial) deborah?\M',                           'Dom Pedro',                'centro-oeste', 'Av. Jacira Reis / Av. Pedro Teixeira', 'Pedro 30/09'),
  ('Loteamento Alphaville',     '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?alphaville\M', 'Ponta Negra',             'oeste',       'Av. Coronel Teixeira / Av. do Turismo', 'Pedro 30/09'),
  ('Conjunto Jardim Europa',    '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?(jardim|jd) europa\M', 'Ponta Negra',     'oeste',       'Av. Coronel Teixeira / Av. do Turismo', 'Pedro 30/09'),
  ('Conjunto Campos Elíseos',   '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?campos eliseos\M', 'Planalto',            'centro-oeste', 'Av. Constantinopla / Av. Dublin', 'Pedro 30/09'),
  ('Conjunto Flamanal',         '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?flamanal\M',  'Planalto',                 'centro-oeste', 'Av. Desembargador João Machado / Av. Dublin', 'Pedro 30/09'),
  ('Parque Mosaico',            '\m(parque|pque|pq) mosaico\M',                                               'Planalto',                 'centro-oeste', 'Av. Desembargador João Machado / Av. do Futuro', 'Pedro 30/09'),
  ('Residencial Viver Melhor',  '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?viver melhor\M', 'Lago Azul',             'norte',       'Av. Torquato Tapajós / BR-174', 'Pedro 30/09'),
  ('Conjunto Manauara',         '\m(conjunto|conj|cjto|cj) manauara\M',                                       'Santa Etelvina',           'norte',       'Av. Sete de Maio / Av. Mulateiro', 'Pedro 30/09'),
  ('Conjunto Francisca Mendes', '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?francisca mendes\M', 'Cidade Nova',       'norte',       'Av. Noel Nutels / Av. Max Teixeira', 'Pedro 30/09'),
  ('Conjunto Renato Souza Pinto', '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?renato (de )?souza pinto\M', 'Cidade Nova', 'norte', 'Av. Noel Nutels / Av. Timbiras', 'Pedro 30/09'),
  ('Conjunto Canaranas',        '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?canaranas?\M', 'Cidade Nova',             'norte',       'Av. Noel Nutels / Av. Camapuã', 'Pedro 30/09'),
  ('Conjunto Campo Dourado',    '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?campo dourado\M', 'Cidade Nova',          'norte',       'Av. Noel Nutels / Av. Preciosa', 'Pedro 30/09'),
  ('Conjunto Riacho Doce',      '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?riacho doce\M', 'Cidade Nova',            'norte',       'Av. Noel Nutels / Av. Guaranás', 'Pedro 30/09'),
  ('Conjunto Galileia',         '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?galileia\M',  'Nova Cidade',              'norte',       'Av. Margarita / Av. Curaçao', 'Pedro 30/09'),
  ('Conjunto Cidadão',          '\m(conjunto|conj|cjto|cj) cidadao\M',                                        'Jorge Teixeira',           'leste',       'Av. Autaz Mirim / Av. Itaúba', 'Pedro 30/09'),
  ('Conjunto do Trabalhador',   '\m(conjunto|conj|cjto|cj) (do )?trabalhador\M',                              'São José Operário',        'leste',       'Av. Autaz Mirim / Av. Cosme Ferreira', 'Pedro 30/09'),
  ('Conjunto Mutirão',          '\m(conjunto|conj|cjto|cj) mutirao\M',                                        'Novo Aleixo',              'leste',       'Av. Autaz Mirim / Av. Nathan Xavier', 'Pedro 30/09'),
  ('Conjunto Águas Claras',     '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?aguas claras\M', 'Novo Aleixo',           'leste',       'Av. das Torres / Av. Nathan Xavier', 'Pedro 30/09'),
  ('Conjunto Japiim I e II',    '\m(conjunto|conj|cjto|cj) japiim( (i|ii|1|2)( e (ii|2))?)?\M', 'Japiim', 'sul', 'Av. Rodrigo Otávio / Av. General Rodrigo Otávio Jordão', 'Pedro 30/09'),
  ('Conjunto 31 de Março',      '\m(conjunto|conj|cjto|cj) 31 de marco\M',                                    'Japiim',                   'sul',         'Av. Rodrigo Otávio / Av. Tefé', 'Pedro 30/09')
ON CONFLICT (nome) DO UPDATE SET expressao = EXCLUDED.expressao, bairro = EXCLUDED.bairro, zona = EXCLUDED.zona,
  avenidas = EXCLUDED.avenidas;

-- (av|avenida) opcional só quando o nome não é outra coisa na cidade
INSERT INTO nai_lugar_avenida (nome, expressao, bairros, criado_por) VALUES
  ('Av. Professor Nilton Lins',  '\m((av|avenida) )?((professor|prof) )?nilton lins\M',   ARRAY['Flores'], 'Pedro 30/09'),
  ('Av. das Torres',             '\m(av|avenida) (das )?torres\M',                          ARRAY['Flores', 'Novo Aleixo'], 'Pedro 30/09'),
  ('Av. Max Teixeira',           '\m((av|avenida) )?max teixeira\M',                        ARRAY['Flores', 'Cidade Nova'], 'Pedro 30/09'),
  ('Av. André Araújo',           '\m((av|avenida) )?andre araujo\M',                        ARRAY['Aleixo'], 'Pedro 30/09'),
  ('Av. Via Láctea',             '\m((av|avenida) )?via lactea\M',                          ARRAY['Aleixo'], 'Pedro 30/09'),
  ('Av. Cosme Ferreira',         '\m((av|avenida) )?cosme ferreira\M',                      ARRAY['Aleixo', 'São José Operário'], 'Pedro 30/09'),
  ('Av. Rodrigo Otávio',         '\m((av|avenida) )?(general )?rodrigo otavio\M',           ARRAY['Aleixo', 'Japiim'], 'Pedro 30/09'),
  ('Av. Djalma Batista',         '\m((av|avenida) )?djalma batista\M',                      ARRAY['Nossa Senhora das Graças'], 'Pedro 30/09'),
  ('Av. João Valério',           '\m((av|avenida) )?joao valerio\M',                        ARRAY['Nossa Senhora das Graças'], 'Pedro 30/09'),
  ('Av. Mário Ypiranga',         '\m((av|avenida) )?mario (y|i)piranga\M',                  ARRAY['Nossa Senhora das Graças', 'Parque 10 de Novembro', 'Adrianópolis'], 'Pedro 30/09'),
  ('Av. Darcy Vargas',           '\m((av|avenida) )?darc(y|i) vargas\M',                    ARRAY['Nossa Senhora das Graças'], 'Pedro 30/09'),
  ('Av. Perimetral',             '\m(av|avenida) perimetral\M',                             ARRAY['Parque 10 de Novembro'], 'Pedro 30/09'),
  ('Av. Tancredo Neves',         '\m(av|avenida) tancredo neves\M',                         ARRAY['Parque 10 de Novembro'], 'Pedro 30/09'),
  ('Av. Maneca Marques',         '\m((av|avenida) )?maneca marques\M',                      ARRAY['Parque 10 de Novembro'], 'Pedro 30/09'),
  ('Av. Umberto Calderaro',      '\m((av|avenida) )?h?umberto calderaro\M',                 ARRAY['Adrianópolis'], 'Pedro 30/09'),
  ('Av. Ephigênio Salles',       '\m((av|avenida) )?(e|a)(ph|f)igenio sall?es\M',           ARRAY['Adrianópolis'], 'Pedro 30/09'),
  ('Av. Álvaro Maia',            '\m(av|avenida) alvaro maia\M',                            ARRAY['Adrianópolis'], 'Pedro 30/09'),
  ('Av. Jacira Reis',            '\m((av|avenida) )?jacira reis\M',                         ARRAY['Alvorada', 'Dom Pedro'], 'Pedro 30/09'),
  ('Av. Desembargador João Machado', '\m((av|avenida) )?((desembargador|des) )?joao machado\M', ARRAY['Alvorada', 'Planalto'], 'Pedro 30/09'),
  ('Av. Alvorada',               '\m(av|avenida) alvorada\M',                               ARRAY['Alvorada'], 'Pedro 30/09'),
  ('Av. Constantinopla',         '\m((av|avenida) )?constantinopla\M',                      ARRAY['Alvorada', 'Planalto'], 'Pedro 30/09'),
  ('Av. Pedro Teixeira',         '\m((av|avenida) )?pedro teixeira\M',                      ARRAY['Dom Pedro'], 'Pedro 30/09'),
  ('Av. Dom Pedro',              '\m(av|avenida) dom pedro\M',                              ARRAY['Dom Pedro'], 'Pedro 30/09'),
  ('Av. Coronel Teixeira',       '\m((av|avenida) )?(coronel|cel) teixeira\M',              ARRAY['Ponta Negra'], 'Pedro 30/09'),
  ('Av. do Turismo',             '\m(av|avenida) (do )?turismo\M',                          ARRAY['Ponta Negra'], 'Pedro 30/09'),
  ('Av. Dublin',                 '\m(av|avenida) dublin\M',                                 ARRAY['Planalto'], 'Pedro 30/09'),
  ('Av. do Futuro',              '\m(av|avenida) (do )?futuro\M',                           ARRAY['Planalto'], 'Pedro 30/09'),
  ('Av. Torquato Tapajós',       '\m((av|avenida) )?torquato( tapajos)?\M',                 ARRAY['Lago Azul'], 'Pedro 30/09'),
  ('BR-174',                     '\mbr ?174\M',                                             ARRAY['Lago Azul'], 'Pedro 30/09'),
  ('Av. Sete de Maio',           '\m(av|avenida) (sete|7) de maio\M',                       ARRAY['Santa Etelvina'], 'Pedro 30/09'),
  ('Av. Mulateiro',              '\m(av|avenida) mulateiro\M',                              ARRAY['Santa Etelvina'], 'Pedro 30/09'),
  ('Av. Noel Nutels',            '\m((av|avenida) )?noel nutels\M',                         ARRAY['Cidade Nova'], 'Pedro 30/09'),
  ('Av. Timbiras',               '\m(av|avenida) timbiras\M',                               ARRAY['Cidade Nova'], 'Pedro 30/09'),
  ('Av. Camapuã',                '\m(av|avenida) camapua\M',                                ARRAY['Cidade Nova'], 'Pedro 30/09'),
  ('Av. Preciosa',               '\m(av|avenida) preciosa\M',                               ARRAY['Cidade Nova'], 'Pedro 30/09'),
  ('Av. Guaranás',               '\m(av|avenida) guaranas\M',                               ARRAY['Cidade Nova'], 'Pedro 30/09'),
  ('Av. Margarita',              '\m(av|avenida) margarita\M',                              ARRAY['Nova Cidade'], 'Pedro 30/09'),
  ('Av. Curaçao',                '\m(av|avenida) curacao\M',                                ARRAY['Nova Cidade'], 'Pedro 30/09'),
  ('Av. Autaz Mirim',            '\m((av|avenida) )?autaz mirim\M',                         ARRAY['Jorge Teixeira', 'São José Operário', 'Novo Aleixo'], 'Pedro 30/09'),
  ('Av. Itaúba',                 '\m(av|avenida) itauba\M',                                 ARRAY['Jorge Teixeira'], 'Pedro 30/09'),
  ('Av. Nathan Xavier',          '\m((av|avenida) )?nath?an xavier\M',                      ARRAY['Novo Aleixo'], 'Pedro 30/09'),
  ('Av. Tefé',                   '\m(av|avenida) tefe\M',                                   ARRAY['Japiim'], 'Pedro 30/09')
ON CONFLICT (nome) DO UPDATE SET expressao = EXCLUDED.expressao, bairros = EXCLUDED.bairros;

-- o texto como as regras leem: sem acento, minúsculo, pontuação vira espaço
CREATE OR REPLACE FUNCTION nai_lugar_normal(p_texto text)
 RETURNS text LANGUAGE sql STABLE AS $$
  SELECT btrim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g'));
$$;

-- os conjuntos e avenidas que o texto cita
CREATE OR REPLACE FUNCTION nai_lugar_citado(p_texto text)
 RETURNS TABLE(tipo text, nome text, bairros text[], expressao text)
 LANGUAGE sql STABLE AS $$
  WITH t AS (SELECT nai_lugar_normal(p_texto) AS n)
  SELECT 'conjunto', c.nome, ARRAY[c.bairro], c.expressao FROM nai_lugar_conjunto c, t
   WHERE c.ativo AND t.n <> '' AND t.n ~ c.expressao
  UNION ALL
  SELECT 'avenida', a.nome, a.bairros, a.expressao FROM nai_lugar_avenida a, t
   WHERE a.ativo AND t.n <> '' AND t.n ~ a.expressao;
$$;

-- os bairros onde procurar (NULL quando o texto não cita conjunto nem avenida)
CREATE OR REPLACE FUNCTION nai_bairros_do_lugar(p_texto text)
 RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT array_agg(DISTINCT b ORDER BY b) FROM nai_lugar_citado(p_texto) l, unnest(l.bairros) b;
$$;

-- como a lista chama o lugar, depois de "No ...":
--   "Parque 10 de Novembro (bairro do Conjunto Eldorado)"
--   "entorno da Av. Mário Ypiranga (Adrianópolis, Nossa Senhora das Graças e Parque 10 de Novembro)"
CREATE OR REPLACE FUNCTION nai_lugar_rotulo(p_texto text)
 RETURNS text LANGUAGE sql STABLE AS $$
  WITH l AS (SELECT * FROM nai_lugar_citado(p_texto)),
  n AS (SELECT count(*) AS q FROM l)
  SELECT CASE
    WHEN n.q = 0 THEN NULL
    WHEN n.q = 1 AND (SELECT tipo FROM l) = 'conjunto' THEN
      (SELECT bairros[1] || ' (bairro ' || CASE WHEN lower(unaccent(nome)) ~ '^(vila|morada)' THEN 'da ' ELSE 'do ' END
              || nome || ')' FROM l)
    WHEN n.q = 1 THEN (SELECT 'entorno da ' || nome || ' (' || nai_lista_pt(bairros) || ')' FROM l)
    ELSE nai_lista_pt(nai_bairros_do_lugar(p_texto)) || ' (' || (SELECT nai_lista_pt(array_agg(nome ORDER BY nome)) FROM l) || ')'
  END FROM n;
$$;

-- 1. A BIBLIOTECA: o que ele escreveu + os lugares que ele citou
CREATE OR REPLACE FUNCTION public.nai_giria_explica(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    ' COMO ELE FALA: ' || string_agg('"' || g.exemplo_curto || '" = ' || g.significado, ' ' ORDER BY g.id),
    '')
    -- 206: conjuntos e avenidas (Pedro, 30/09)
    || coalesce((SELECT ' LUGARES: ' || string_agg(
         CASE WHEN l.tipo = 'conjunto'
              THEN '"' || l.nome || '" é um conjunto do bairro ' || l.bairros[1]
                   || ': quem pede imóvel lá quer imóvel desse bairro.'
              ELSE '"' || l.nome || '" passa ' || CASE WHEN cardinality(l.bairros) = 1 THEN 'pelo bairro ' ELSE 'pelos bairros ' END
                   || nai_lista_pt(l.bairros) || ': quem pede imóvel nessa avenida quer imóvel '
                   || CASE WHEN cardinality(l.bairros) = 1 THEN 'desse bairro.' ELSE 'desses bairros.' END END
         || ' Não pergunte o bairro: chame buscar_por_perfil com bairro "' || l.nome || '" (a busca já procura lá).',
         ' ' ORDER BY l.tipo, l.nome)
       FROM (SELECT * FROM nai_lugar_citado(p_texto) LIMIT 4) l), '')
    FROM (
      SELECT id, significado,
             -- a expressao inteira que ele escreveu: a regex vai entre
             -- parenteses para o grupo 1 ser o casamento todo, e nao o
             -- primeiro pedaco dela ("ta" em vez de "ta valendo").
             coalesce((regexp_match(lower(unaccent(coalesce(p_texto, ''))), '(' || expressao || ')'))[1],
                      expressao) AS exemplo_curto
        FROM nai_giria
       WHERE ativo
         AND lower(unaccent(coalesce(p_texto, ''))) ~ expressao
       LIMIT 6            -- teto: gíria e ajuda, nao um dicionario no contexto
    ) g;
$function$;

-- 2. A BUSCA
CREATE OR REPLACE FUNCTION public.nai_quantos_no_bairro(p_bairro text, p_telefone text, p_quartos integer, p_negocio text, p_tipo text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT count(*)::int FROM imoveis i
   WHERE (nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(coalesce(p_bairro, ''), true) || '%'
          -- 206: conjunto e avenida contam os bairros deles
          OR i.bairro IN (SELECT unnest(nai_bairros_do_lugar(p_bairro))))
     AND nai_oferta_serve(i, coalesce(p_telefone, ''), NULL, p_quartos, false, false, p_negocio, p_tipo);
$function$;

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_abertura     boolean;  -- 190
$a$, $b$  v_abertura     boolean;  -- 190
  v_lug_bairros  text[];   -- 206: os bairros do conjunto/avenida citado
  v_lug_rx       text;     -- 206: o nome do conjunto (condominio de mesmo nome vem primeiro)
  v_lug_rotulo   text;     -- 206: "Parque 10 de Novembro (bairro do Conjunto Eldorado)"
$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
$a$, $b$  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- 206: CONJUNTO E AVENIDA (Pedro, 30/09: "quando algum corretor perguntar de
  -- algum conjunto ... ela mande imoveis do bairro"; e a avenida, com os
  -- bairros dela). Sem bairro nenhum na chamada, vale o que ele escreveu.
  v_lug_bairros := nai_bairros_do_lugar(p_bairro);
  IF v_lug_bairros IS NULL AND nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN
    p_bairro := (SELECT string_agg(l.nome, ' e ' ORDER BY l.tipo, l.nome) FROM nai_lugar_citado(t.texto) l);
    v_lug_bairros := nai_bairros_do_lugar(p_bairro);
  END IF;
  IF v_lug_bairros IS NOT NULL THEN
    v_lug_rx := (SELECT string_agg('(' || l.expressao || ')', '|') FROM nai_lugar_citado(p_bairro) l
                  WHERE l.tipo = 'conjunto');
    v_lug_rotulo := nai_lugar_rotulo(p_bairro);
    PERFORM nai_anotar(p_turno, 7, 'lugar_vira_bairro', 'mudou',
                       left(p_bairro || ' -> ' || array_to_string(v_lug_bairros, ', '), 200));
  END IF;
$b$);

-- a lista do bairro e a lista "sem o tipo pedido": os bairros do lugar tambem
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$(v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%')$a$,
$b$(v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
            OR i.bairro = ANY (v_lug_bairros))$b$, 2);

-- o condominio com o nome do conjunto vem primeiro (Conjunto Ica Paraiba, Eldorado Park...)
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$ORDER BY 2 LIMIT 5) z;$a$,
$b$ORDER BY (v_lug_rx IS NOT NULL AND nai_lugar_normal(i.condominio_nome) ~ v_lug_rx) DESC, 2 LIMIT 5) z;$b$, 3);

-- os vizinhos do conjunto sao os do bairro dele
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$                ELSE nay_bairros_proximos(btrim(coalesce(p_bairro, ''))) END;$a$,
$b$                WHEN cardinality(v_lug_bairros) = 1 THEN nay_bairros_proximos(v_lug_bairros[1])
                WHEN v_lug_bairros IS NOT NULL THEN '{}'::text[]
                ELSE nay_bairros_proximos(btrim(coalesce(p_bairro, ''))) END;$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
$a$, $b$         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND i.bairro <> ALL (coalesce(v_lug_bairros, '{}'::text[]))
$b$);

-- conjunto/avenida nao e "bairro que nao existe"
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$    IF NOT v_livre AND NOT EXISTS ($a$,
$b$    IF NOT v_livre AND v_lug_bairros IS NULL AND NOT EXISTS ($b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$            ELSE 'No ' || initcap(btrim(coalesce(p_bairro, ''))) || ' não tenho ' || v_nada$a$,
$b$            ELSE 'No ' || coalesce(v_lug_rotulo, initcap(btrim(coalesce(p_bairro, '')))) || ' não tenho ' || v_nada$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  SELECT coalesce((SELECT a.area FROM nai_area_citada(p_bairro) a LIMIT 1), v_nome_b)
    INTO v_nome_b;
$a$, $b$  SELECT coalesce((SELECT a.area FROM nai_area_citada(p_bairro) a LIMIT 1), v_nome_b)
    INTO v_nome_b;
  -- 206: conjunto e avenida dizem de que bairro e a lista (o Vieiralves segue a regra de cima)
  IF v_lug_rotulo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nai_area_citada(p_bairro)) THEN
    v_nome_b := v_lug_rotulo;
  END IF;
$b$);

-- 3. A FILA DOS OUTROS IMOVEIS: conjunto citado conta como bairro citado (147)
SELECT pg_temp.trocar('nai_nome_so_do_bairro(text,integer)',
$a$     WHERE length(b.nb) >= 4 AND t.n LIKE '% ' || b.nb || ' %'),$a$,
$b$     WHERE length(b.nb) >= 4 AND t.n LIKE '% ' || b.nb || ' %'
    -- 206: o conjunto que ele citou ("eldorado" nao e o Eldorado Park)
    UNION
    SELECT btrim((regexp_match(t.n, '(' || c.expressao || ')'))[1])
      FROM nai_lugar_conjunto c, t
     WHERE c.ativo AND t.n ~ c.expressao),$b$);

GRANT SELECT ON nai_lugar_conjunto, nai_lugar_avenida TO nay_core;
COMMIT;
