-- 229 (30/09/2026): OS LUGARES LIGADOS AOS IMÓVEIS DE HOJE, E AS FICHAS COM O TEXTO EXATO.
-- Pedro: "todos os conjuntos por bairro e por zona e por avenida relacionada, preciso
-- que isso esteja tudo relacionado com nossos imóveis hoje para o banco de dados" e
-- "todos os condomínios e suas características" (a lista de 11, de novo).
--
-- Conferido antes: os 37 conjuntos já estavam com bairro, zona e as duas avenidas
-- (206), e as 42 avenidas com os bairros. O que faltava:
--   1. as 11 fichas guardavam o texto RESUMIDO ("Sim" no lugar de "Sim, possui
--      elevador", lazer encurtado): agora vai o texto da lista, palavra por palavra;
--   2. nenhum imóvel estava ligado a zona, conjunto ou avenida: nasce `imovel_lugar`,
--      uma linha por imóvel, atualizada sozinha (gatilho em `imoveis` e nas listas);
--   3. a Nay não entendia "zona leste": a zona entra em `nai_lugar_citado`.
--
-- imovel_lugar
--   zona                 pelo bairro (bairro_zona)
--   conjuntos            o conjunto no nome do condomínio, ou no endereço com o mesmo
--                        bairro ("Rua Castelo Branco" em outro bairro não é o Conjunto
--                        Castelo Branco)
--   conjuntos_do_bairro  todos os conjuntos do bairro do imóvel
--   avenidas             a avenida no endereço
--   avenidas_do_bairro   as avenidas da lista que passam no bairro
BEGIN;
SET LOCAL lock_timeout = '3s';

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

-- 1 ------------------------------------------ AS FICHAS, COM O TEXTO DA LISTA
UPDATE condominio_ficha SET ano_lancamento = 2025, construtora = $v$Riva Incorporadora (Grupo Direcional)$v$,
       revestimento = $v$Pintura texturizada padrão$v$, endereco = $v$Rua Santa Bárbara, nº 200, Bairro Flores / Parque das Laranjeiras, Manaus - AM$v$, torres = $v$7 blocos residenciais$v$,
       andares = $v$8 andares (Térreo + 7 pavimentos)$v$, aptos_por_andar = $v$8 apartamentos por andar (totalizando 448 unidades)$v$, elevador = $v$Sim, possui elevador$v$,
       unidades = NULL, lazer = ARRAY[$v$Academia climatizada$v$, $v$Churrasqueira$v$, $v$Pet place$v$, $v$Piscinas (adulto e infantil)$v$, $v$Playground$v$, $v$Quadra poliesportiva$v$, $v$Salão de festas com espaço gourmet$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Città Oasis Azzure$v$;
UPDATE condominio_ficha SET ano_lancamento = 2021, construtora = $v$Construtora Capital$v$,
       revestimento = $v$Pintura acrílica e textura$v$, endereco = $v$Av. Professor Nilton Lins, nº 1411, Bairro Flores, Manaus - AM$v$, torres = $v$1 torre única$v$,
       andares = $v$8 andares$v$, aptos_por_andar = $v$8 apartamentos por andar (totalizando 64 unidades)$v$, elevador = $v$Sim, possui elevador$v$,
       unidades = NULL, lazer = ARRAY[$v$Piscina adulto e infantil$v$, $v$Churrasqueiras$v$, $v$Salão de festas$v$, $v$Academia$v$, $v$Playground$v$, $v$Pet place$v$, $v$Quadra esportiva$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$UP Flores$v$;
UPDATE condominio_ficha SET ano_lancamento = 2020, construtora = $v$RD Engenharia$v$,
       revestimento = $v$Pintura acrílica de alta resistência$v$, endereco = $v$Travessa Carlos, nº 15, Bairro Parque 10 de Novembro, Manaus - AM$v$, torres = $v$2 torres (Torre Felicidade e Torre Sonho)$v$,
       andares = $v$8 andares (Térreo + 7 pavimentos)$v$, aptos_por_andar = $v$8 apartamentos por andar$v$, elevador = $v$Sim, possui 2 elevadores por torre$v$,
       unidades = NULL, lazer = ARRAY[$v$Deck Park$v$, $v$Brinquedoteca$v$, $v$Churrasqueiras$v$, $v$Espaço fitness$v$, $v$Piscina$v$, $v$Playground$v$, $v$Salão de festas$v$, $v$Salão de jogos$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Predilleto Residencial$v$;
UPDATE condominio_ficha SET ano_lancamento = 2019, construtora = $v$Direcional Engenharia$v$,
       revestimento = $v$Pintura texturizada$v$, endereco = $v$Av. Cosme Ferreira, nº 4731, Bairro Aleixo, Manaus - AM$v$, torres = $v$4 torres$v$,
       andares = $v$14 andares (Térreo + 13 pavimentos)$v$, aptos_por_andar = $v$8 apartamentos por andar$v$, elevador = $v$Sim, possui elevador$v$,
       unidades = NULL, lazer = ARRAY[$v$Piscinas adulto e infantil$v$, $v$Solarium$v$, $v$Quadra de esportes$v$, $v$Salão de festas$v$, $v$Espaço gourmet com churrasqueira$v$, $v$Playground$v$, $v$Fitness ao ar livre$v$, $v$Praças$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Altos do Aleixo$v$;
UPDATE condominio_ficha SET ano_lancamento = 2022, construtora = $v$Construtora Capital$v$,
       revestimento = $v$Pintura texturizada$v$, endereco = $v$Av. Thales Loureiro, s/n, Bairro Ponta Negra, Manaus - AM$v$, torres = $v$1 torre única$v$,
       andares = $v$11 andares$v$, aptos_por_andar = $v$8 apartamentos por andar$v$, elevador = $v$Sim, possui elevador inteligente$v$,
       unidades = NULL, lazer = ARRAY[$v$Piscina com deck$v$, $v$Churrasqueira$v$, $v$Salão de festas gourmet$v$, $v$Playground integrado$v$, $v$Brinquedoteca$v$, $v$Fitness equipado$v$, $v$Guarita blindada$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$UP Ponta Negra I$v$;
UPDATE condominio_ficha SET ano_lancamento = 2023, construtora = $v$MRV Engenharia$v$,
       revestimento = $v$Pintura texturizada padrão MRV$v$, endereco = $v$Av. Desembargador João Machado, s/n (Complexo Parque Mosaico), Bairro Planalto, Manaus - AM$v$, torres = $v$5 torres$v$,
       andares = $v$8 andares (Térreo + 7 pavimentos)$v$, aptos_por_andar = $v$8 apartamentos por andar$v$, elevador = $v$Sim, possui elevador em todas as torres$v$,
       unidades = NULL, lazer = ARRAY[$v$Salão de festas$v$, $v$Playground$v$, $v$Pet place$v$, $v$Salão de jogos$v$, $v$Espaço gourmet$v$, $v$Piscinas adulto e infantil$v$, $v$Pomar$v$, $v$Bicicletário com paraciclo$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Vista dos Oitis (MRV)$v$;
UPDATE condominio_ficha SET ano_lancamento = 2021, construtora = $v$Construtora Prime$v$,
       revestimento = $v$Pintura acrílica e textura$v$, endereco = $v$Av. Desembargador João Machado, nº 140, Bairro Planalto, Manaus - AM$v$, torres = $v$4 torres$v$,
       andares = $v$8 andares (Térreo + 7 pavimentos)$v$, aptos_por_andar = $v$8 apartamentos por andar$v$, elevador = $v$Sim, possui 2 elevadores por torre$v$,
       unidades = NULL, lazer = ARRAY[$v$Piscina adulto e infantil$v$, $v$Deck molhado$v$, $v$Solarium$v$, $v$Salão de festas$v$, $v$Fitness$v$, $v$Churrasqueiras$v$, $v$Playground$v$, $v$Quadra recreativa$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Prime Vivendas do Parque$v$;
UPDATE condominio_ficha SET ano_lancamento = 2020, construtora = $v$Direcional Engenharia$v$,
       revestimento = $v$Pintura texturizada$v$, endereco = $v$Av. das Torres, s/n, Bairro Lago Azul, Manaus - AM$v$, torres = $v$Organizado em blocos de apartamentos periféricos$v$,
       andares = $v$5 andares (Térreo + 4 pavimentos)$v$, aptos_por_andar = $v$8 apartamentos por andar$v$, elevador = $v$Não possui elevador$v$,
       unidades = NULL, lazer = ARRAY[$v$Quadra poliesportiva$v$, $v$Piscinas adulto e infantil$v$, $v$Playground$v$, $v$Área de churrasqueiras independentes$v$, $v$Salão de festas$v$, $v$Pista de caminhada externa$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Bosque das Torres$v$;
UPDATE condominio_ficha SET ano_lancamento = 2021, construtora = $v$Engeco Engenharia$v$,
       revestimento = $v$Pintura acrílica texturizada$v$, endereco = $v$Av. Coronel Teixeira, s/n, Bairro Ponta Negra, Manaus - AM$v$, torres = NULL,
       andares = NULL, aptos_por_andar = NULL, elevador = NULL,
       unidades = $v$53 casas duplex ao todo$v$, lazer = ARRAY[$v$Piscina privativa do condomínio$v$, $v$Área gourmet com churrasqueira$v$, $v$Playground para crianças$v$, $v$Salão de festas$v$, $v$Sistema integrado de vigilância$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Residencial Villa Marieta$v$;
UPDATE condominio_ficha SET ano_lancamento = 2022, construtora = $v$Incorporadora e Curadoria Conceito (Assinado pelo arquiteto Benedito Abbud)$v$,
       revestimento = $v$Muros ecológicos (verdes) e pavimentação das vias internas em blocos de concreto intertravado (paver)$v$, endereco = $v$Estrada de Acesso ao Cetur, nº 3020, Bairro Tarumã, Manaus - AM$v$, torres = NULL,
       andares = NULL, aptos_por_andar = NULL, elevador = NULL,
       unidades = $v$180 lotes (a partir de 1.500m²)$v$, lazer = ARRAY[$v$Complexo hípico com baias$v$, $v$Heliponto homologado$v$, $v$Marina privativa com acesso ao rio$v$, $v$Espaço exclusivo para a prática de golfe$v$, $v$Quadras de tênis e de beach tênis$v$, $v$Quadra de boliche profissional$v$, $v$Cinema privativo$v$, $v$Spa com serviço de concierge$v$, $v$Academia climatizada de última geração$v$, $v$Piscinas cinematográficas$v$, $v$Capela ecumênica$v$, $v$Restaurante de alta gastronomia$v$, $v$Ciclovias em meio a mais de 300 mil m² de mata preservada$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Quintas de São José do Rio Negro$v$;
UPDATE condominio_ficha SET ano_lancamento = 2023, construtora = $v$Amazonas Incorporadora$v$,
       revestimento = $v$Pavimentação asfáltica padrão e meio-fio$v$, endereco = $v$Av. Professor Paulo Graça, s/n, Bairro Tarumã-Açu, Manaus - AM$v$, torres = NULL,
       andares = NULL, aptos_por_andar = NULL, elevador = NULL,
       unidades = $v$247 lotes residenciais ao todo$v$, lazer = ARRAY[$v$Central de lazer com Wi-Fi livre$v$, $v$Piscina adulto e infantil com solarium$v$, $v$Salão de festas mobiliado$v$, $v$Espaço fitness/academia equipada$v$, $v$Quiosques integrados com churrasqueira$v$, $v$Trilhas exclusivas para caminhada ecológica$v$, $v$Espaço Pet dedicado$v$, $v$Redário sob árvores preservadas$v$, $v$Playground infantil$v$]::text[], fonte = 'lista do Pedro, 30/09/2026 (texto exato)', atualizado_em = now()
 WHERE nome = $v$Bellavile Residencial$v$;

DO $$
BEGIN
  IF (SELECT count(*) FROM condominio_ficha WHERE fonte = 'lista do Pedro, 30/09/2026 (texto exato)') <> 11 THEN
    RAISE EXCEPTION 'esperava 11 fichas regravadas, achei %',
      (SELECT count(*) FROM condominio_ficha WHERE fonte = 'lista do Pedro, 30/09/2026 (texto exato)');
  END IF;
END $$;

-- 2 --------------------------------------------- CADA IMÓVEL E OS SEUS LUGARES
CREATE TABLE IF NOT EXISTS imovel_lugar (
  codigo              integer PRIMARY KEY,   -- sem FK: imoveis é escrita o tempo todo pela varredura
  bairro              text,
  zona                text,
  conjuntos           text[] NOT NULL DEFAULT '{}',
  conjuntos_do_bairro text[] NOT NULL DEFAULT '{}',
  avenidas            text[] NOT NULL DEFAULT '{}',
  avenidas_do_bairro  text[] NOT NULL DEFAULT '{}',
  atualizado_em       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS imovel_lugar_zona ON imovel_lugar (zona);
CREATE INDEX IF NOT EXISTS imovel_lugar_conjuntos ON imovel_lugar USING gin (conjuntos);
CREATE INDEX IF NOT EXISTS imovel_lugar_avenidas ON imovel_lugar USING gin (avenidas);
COMMENT ON TABLE imovel_lugar IS '229 (30/09): zona, conjuntos e avenidas de cada imóvel; nai_relacionar_imovel_lugar() refaz';

CREATE OR REPLACE FUNCTION public.nai_relacionar_imovel_lugar(p_codigo integer DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
  -- 229: sem código = todos (e some quem não existe mais); com código = só ele.
  -- Cada nome é normalizado UMA vez (bz/cj/av); normalizar dentro do laço por
  -- imóvel levava 54 s para os 5.674.
  WITH bz AS MATERIALIZED (
    SELECT DISTINCT ON (nay_normalizar_lugar(z.bairro, true)) nay_normalizar_lugar(z.bairro, true) AS bn, z.zona
      FROM bairro_zona z ORDER BY nay_normalizar_lugar(z.bairro, true), z.zona
  ), cj AS MATERIALIZED (
    SELECT c.nome, c.expressao, nay_normalizar_lugar(c.bairro, true) AS bn FROM nai_lugar_conjunto c WHERE c.ativo
  ), av AS MATERIALIZED (
    SELECT a.nome, a.expressao, ARRAY(SELECT nay_normalizar_lugar(x, true) FROM unnest(a.bairros) x) AS bns
      FROM nai_lugar_avenida a WHERE a.ativo
  ), base AS MATERIALIZED (
    SELECT i.codigo, nullif(btrim(i.bairro), '') AS bairro,
           nay_normalizar_lugar(coalesce(i.bairro, ''), true) AS bn,
           nai_lugar_normal(i.logradouro) AS rua,
           nai_lugar_normal(i.condominio_nome) AS condo
      FROM imoveis i
     WHERE p_codigo IS NULL OR i.codigo = p_codigo
  )
  -- padrão por fora, imóvel por dentro: cada regex é compilada uma vez (o cache do
  -- Postgres guarda só 32, e 79 padrões alternados recompilavam a cada linha)
  , m_cj AS (
    SELECT b.codigo, array_agg(cj.nome ORDER BY cj.nome) AS nomes
      FROM cj CROSS JOIN base b
     WHERE (b.condo <> '' AND b.condo ~ cj.expressao)
        OR (b.rua <> '' AND cj.bn = b.bn AND b.rua ~ cj.expressao)
     GROUP BY b.codigo
  ), m_av AS (
    SELECT b.codigo, array_agg(av.nome ORDER BY av.nome) AS nomes
      FROM av CROSS JOIN base b
     WHERE b.rua <> '' AND b.rua ~ av.expressao
     GROUP BY b.codigo
  ), cj_b AS (
    SELECT cj.bn, array_agg(cj.nome ORDER BY cj.nome) AS nomes FROM cj GROUP BY cj.bn
  ), av_b AS (
    SELECT x.bn, array_agg(DISTINCT av.nome ORDER BY av.nome) AS nomes FROM av, unnest(av.bns) x(bn) GROUP BY x.bn
  )
  INSERT INTO imovel_lugar AS l (codigo, bairro, zona, conjuntos, conjuntos_do_bairro, avenidas, avenidas_do_bairro, atualizado_em)
  SELECT b.codigo, b.bairro, bz.zona,
         coalesce(m_cj.nomes, '{}'), coalesce(cj_b.nomes, '{}'),
         coalesce(m_av.nomes, '{}'), coalesce(av_b.nomes, '{}'),
         now()
    FROM base b
    LEFT JOIN bz   ON b.bn <> '' AND bz.bn = b.bn
    LEFT JOIN m_cj ON m_cj.codigo = b.codigo
    LEFT JOIN m_av ON m_av.codigo = b.codigo
    LEFT JOIN cj_b ON b.bn <> '' AND cj_b.bn = b.bn
    LEFT JOIN av_b ON b.bn <> '' AND av_b.bn = b.bn
  ON CONFLICT (codigo) DO UPDATE
     SET bairro = EXCLUDED.bairro, zona = EXCLUDED.zona, conjuntos = EXCLUDED.conjuntos,
         conjuntos_do_bairro = EXCLUDED.conjuntos_do_bairro, avenidas = EXCLUDED.avenidas,
         avenidas_do_bairro = EXCLUDED.avenidas_do_bairro, atualizado_em = now();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF p_codigo IS NULL THEN
    DELETE FROM imovel_lugar l WHERE NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = l.codigo);
  END IF;
  RETURN n;
END;
$function$;
REVOKE ALL ON FUNCTION nai_relacionar_imovel_lugar(integer) FROM PUBLIC;

-- o imóvel mudou de bairro, endereço ou condomínio: refaz a linha dele
CREATE OR REPLACE FUNCTION public.nai_imovel_lugar_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 229: nunca derruba a gravação do imóvel (a varredura e o cadastro escrevem aqui)
  BEGIN
    PERFORM nai_relacionar_imovel_lugar(NEW.codigo);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'imovel_lugar %: %', NEW.codigo, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

-- as listas mudaram: refaz tudo
CREATE OR REPLACE FUNCTION public.nai_imovel_lugar_tudo_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    PERFORM nai_relacionar_imovel_lugar(NULL);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'imovel_lugar (tudo): %', SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS imovel_lugar_do_imovel ON imoveis;
CREATE TRIGGER imovel_lugar_do_imovel AFTER INSERT OR UPDATE OF bairro, logradouro, condominio_nome ON imoveis
  FOR EACH ROW EXECUTE FUNCTION nai_imovel_lugar_gatilho();
DROP TRIGGER IF EXISTS imovel_lugar_conjuntos ON nai_lugar_conjunto;
CREATE TRIGGER imovel_lugar_conjuntos AFTER INSERT OR UPDATE OR DELETE ON nai_lugar_conjunto
  FOR EACH STATEMENT EXECUTE FUNCTION nai_imovel_lugar_tudo_gatilho();
DROP TRIGGER IF EXISTS imovel_lugar_avenidas ON nai_lugar_avenida;
CREATE TRIGGER imovel_lugar_avenidas AFTER INSERT OR UPDATE OR DELETE ON nai_lugar_avenida
  FOR EACH STATEMENT EXECUTE FUNCTION nai_imovel_lugar_tudo_gatilho();
DROP TRIGGER IF EXISTS imovel_lugar_zonas ON bairro_zona;
CREATE TRIGGER imovel_lugar_zonas AFTER INSERT OR UPDATE OR DELETE ON bairro_zona
  FOR EACH STATEMENT EXECUTE FUNCTION nai_imovel_lugar_tudo_gatilho();

SELECT nai_relacionar_imovel_lugar(NULL) AS imoveis_ligados;
GRANT SELECT ON imovel_lugar TO nay_site_leitura;

-- 3 ---------------------------------------------------- A NAY ENTENDE A ZONA
SELECT pg_temp.trocar('nai_lugar_citado(text)',
$a$  SELECT 'avenida', a.nome, a.bairros, a.expressao FROM nai_lugar_avenida a, t
   WHERE a.ativo AND t.n <> '' AND t.n ~ a.expressao;$a$,
$b$  SELECT 'avenida', a.nome, a.bairros, a.expressao FROM nai_lugar_avenida a, t
   WHERE a.ativo AND t.n <> '' AND t.n ~ a.expressao
  -- 229: a ZONA ("zona leste", "zona centro-sul") vira os bairros dela (bairro_zona)
  UNION ALL
  SELECT 'zona', 'Zona ' || initcap(z.zona), array_agg(z.bairro ORDER BY z.bairro),
         '\mzona ' || replace(z.zona, '-', ' ') || '\M'
    FROM bairro_zona z, t
   WHERE t.n <> '' AND t.n ~ ('\mzona ' || replace(z.zona, '-', ' ') || '\M')
   GROUP BY z.zona;$b$);

SELECT pg_temp.trocar('nai_lugar_rotulo(text)',
$a$    WHEN n.q = 1 THEN (SELECT 'entorno da ' || nome || ' (' || nai_lista_pt(bairros) || ')' FROM l)$a$,
$b$    -- 229: a zona diz os bairros dela
    WHEN n.q = 1 AND (SELECT tipo FROM l) = 'zona' THEN (SELECT nome || ' (' || nai_lista_pt(bairros) || ')' FROM l)
    WHEN n.q = 1 THEN (SELECT 'entorno da ' || nome || ' (' || nai_lista_pt(bairros) || ')' FROM l)$b$);

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('Pedro 30/09', 'tem apartamento na zona sul?', 'lugar',
   (SELECT array_agg(DISTINCT bairro ORDER BY bairro)::text FROM bairro_zona WHERE zona = 'sul'),
   'zona sul vira os bairros da zona sul'),
  ('Pedro 30/09', 'algo na zona centro-sul', 'lugar',
   (SELECT array_agg(DISTINCT bairro ORDER BY bairro)::text FROM bairro_zona WHERE zona = 'centro-sul'),
   'zona centro-sul não se confunde com zona sul');
COMMIT;
