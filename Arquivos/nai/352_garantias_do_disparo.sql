-- 352 -- As garantias do disparo aos proprietários: quem falou conosco por QUALQUER número fica fora, e corretor
--        (parceria) não entra em lista de proprietário
--
-- Pedro, 12/10/2026: "antes de disparar, garante que tire dos disparos os proprietários que falaram conosco de todos
-- os números, e tira os corretores dos proprietários, que são os que eram parceria".
--
-- "Falou conosco" = mensagem recebida em qualquer linha nossa: `mensagens` (Parceria / locação, Z-API),
-- `captacao_mensagens` (captação: Z-API e oficial), `nai_turno` (conversa com a Nay), `corretores.ultima_interacao`
-- e o CRM (todas as linhas que ele atende, inclusive o oficial com corretores; o cron nay-agentes copia do crmdb de
-- 10 em 10 min para privado.falou_conosco_crm). Tudo isso é juntado numa tabela só, privado.falou_conosco
-- (nay_falou_conosco_atualizar, pelo mesmo cron), que é o que a tela e o disparo consultam: rápido e uma regra só.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.falou_conosco_crm (telefone text NOT NULL, ultima_em timestamptz NOT NULL);
CREATE TABLE IF NOT EXISTS privado.falou_conosco_crm_tmp (telefone text NOT NULL, ultima_em timestamptz NOT NULL);
CREATE TABLE IF NOT EXISTS privado.falou_conosco (chave text PRIMARY KEY, ultima_em timestamptz NOT NULL, origens text[] NOT NULL,
                                                  atualizado_em timestamptz NOT NULL DEFAULT now());

-- o cron copia o CRM para a _tmp e troca de uma vez (nunca fica vazia no meio)
CREATE OR REPLACE FUNCTION public.nay_falou_conosco_crm_trocar() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM privado.falou_conosco_crm_tmp;
  IF n = 0 THEN RETURN 0; END IF;          -- cópia vazia = erro na leitura: mantém a de antes
  TRUNCATE privado.falou_conosco_crm;
  INSERT INTO privado.falou_conosco_crm SELECT * FROM privado.falou_conosco_crm_tmp;
  TRUNCATE privado.falou_conosco_crm_tmp;
  RETURN n;
END $$;

-- junta todas as fontes (últimos 120 dias) numa tabela por chave; quem consulta escolhe o prazo
CREATE OR REPLACE FUNCTION public.nay_falou_conosco_atualizar() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  DROP TABLE IF EXISTS _falou;   -- a função pode rodar duas vezes na mesma transação (o ensaio roda)
  CREATE TEMP TABLE _falou (chave text, ultima_em timestamptz, origem text) ON COMMIT DROP;
  INSERT INTO _falou
  SELECT nay_fone_chave(nay_fone_com_ddi(m.telefone)), max(m.criada_em), 'parceria'
    FROM mensagens m WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '120 days' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(m.telefone)), max(m.criada_em), 'captacao'
    FROM captacao_mensagens m WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '120 days' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(c.chave)), max(t.criado_em), 'nay'
    FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
   WHERE t.criado_em > now() - interval '120 days' AND c.chave !~ '@' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)), max(c.ultima_interacao), 'corretores'
    FROM corretores c WHERE c.ultima_interacao > now() - interval '120 days' AND coalesce(c.telefone, '') <> '' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(f.telefone)), max(f.ultima_em), 'crm'
    FROM privado.falou_conosco_crm f WHERE f.ultima_em > now() - interval '120 days' GROUP BY 1;
  DELETE FROM privado.falou_conosco;
  INSERT INTO privado.falou_conosco (chave, ultima_em, origens)
  SELECT chave, max(ultima_em), array_agg(DISTINCT origem ORDER BY origem) FROM _falou
   WHERE coalesce(chave, '') <> '' GROUP BY chave;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION public.nay_falou_conosco(p_chave text, p_dias integer DEFAULT 60) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT EXISTS (SELECT 1 FROM privado.falou_conosco f WHERE f.chave = p_chave AND f.ultima_em > now() - make_interval(days => p_dias))
$$;
GRANT EXECUTE ON FUNCTION public.nay_falou_conosco(text, integer) TO nay_site_escrita, nay_leitura, nay_disparo;

-- corretor (grupos ou parceria do site antigo) nunca é "proprietário" numa lista
CREATE OR REPLACE FUNCTION public.nay_e_corretor_chave(p_chave text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT coalesce(p_chave, '') <> '' AND (
       EXISTS (SELECT 1 FROM corretores c WHERE nay_fone_chave(nay_fone_com_ddi(c.telefone)) = p_chave)
    OR EXISTS (SELECT 1 FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
                 AND nay_fone_chave(nay_fone_com_ddi(p.telefone)) = p_chave))
$$;
GRANT EXECUTE ON FUNCTION public.nay_e_corretor_chave(text) TO nay_site_escrita, nay_leitura, nay_disparo;

-- a tela: a regra única (privado.falou_conosco) e corretor fora das listas de donos
CREATE FUNCTION pg_temp.remendar(p_fn regprocedure, p_de text, p_para text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_get_functiondef(p_fn); n int;
BEGIN
  n := (length(v) - length(replace(v, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION 'remendo em %: o trecho aparece % vez(es), esperava 1: %', p_fn, n, left(p_de, 60); END IF;
  EXECUTE replace(v, p_de, p_para);
END $$;
SELECT pg_temp.remendar('site_publicos_disparo()',
$de$  ), falou AS (                          -- quem escreveu para a gente nos últimos 60 dias (qualquer número)
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(m.telefone)) AS chave FROM mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '60 days'
    UNION
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(m.telefone)) FROM captacao_mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '60 days'
    UNION
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(c.chave)) FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
     WHERE t.criado_em > now() - interval '60 days' AND c.chave !~ '@'
    UNION
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(c.telefone)) FROM corretores c
     WHERE c.ultima_interacao > now() - interval '60 days' AND coalesce(c.telefone, '') <> ''
  ), corr AS ($de$,
$para$  ), falou AS (                          -- 352: quem escreveu para a gente nos últimos 60 dias, por QUALQUER número
    SELECT f.chave FROM privado.falou_conosco f WHERE f.ultima_em > now() - interval '60 days'
  ), corretor AS (                        -- 352: corretor (grupos ou parceria) não é dono
    SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(c.telefone, '') <> ''
    UNION
    SELECT nay_fone_chave(nay_fone_com_ddi(p.telefone)) FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
  ), corr AS ($para$);
SELECT pg_temp.remendar('site_publicos_disparo()',
$de$     WHERE length(regexp_replace(coalesce(ps.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13 AND NOT site_nao_e_dono(ps.nome)
     GROUP BY 1$de$,
$para$     WHERE length(regexp_replace(coalesce(ps.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13 AND NOT site_nao_e_dono(ps.nome)
       AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = nay_fone_chave(nay_fone_com_ddi(ps.telefone)))
     GROUP BY 1$para$);
SELECT pg_temp.remendar('site_publicos_disparo()',
$de$    UNION ALL SELECT 9, l.telefone_chave FROM captacao_leads l WHERE coalesce(l.telefone_chave, '') <> ''
    UNION ALL SELECT 10, l.telefone_chave FROM captacao_leads l JOIN captacao_retomada_oficial r ON r.lead_id = l.id$de$,
$para$    UNION ALL SELECT 9, l.telefone_chave FROM captacao_leads l WHERE coalesce(l.telefone_chave, '') <> ''
                AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = l.telefone_chave)
    UNION ALL SELECT 10, l.telefone_chave FROM captacao_leads l JOIN captacao_retomada_oficial r ON r.lead_id = l.id
                WHERE NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = l.telefone_chave)$para$);

-- o disparo da captação (o único automático que existe) respeita as duas garantias
SELECT pg_temp.remendar('captacao_py_fila_do_disparo()',
$de$     AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)$de$,
$para$     AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
     -- 352: quem falou conosco por qualquer número nos últimos 60 dias não recebe disparo; corretor não é proprietário
     AND NOT nay_falou_conosco(l.telefone_chave, 60)
     AND NOT nay_e_corretor_chave(l.telefone_chave)$para$);

SELECT nay_falou_conosco_atualizar() AS falaram_120_dias;
COMMIT;
