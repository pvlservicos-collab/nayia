-- 258 (01/10/2026): ESSE ANÚNCIO JÁ É NOSSO? -- a consulta do grokbot do Pedro.
-- "preciso de um webhook para o grokbot de consulta ao nosso banco de dados de
-- imóveis... o webhook deve dizer se esse imóvel faz ou não parte do nosso banco
-- de dados para ele tomar uma ação" e, depois: "eu quero meu grokbot perguntando
-- sobre um imóvel que ele achou para nosso sistema e o sistema responde apenas".
--
-- O CONTRATO É O QUE O BOT PEDIU (colado pelo Pedro em 01/10): entra o anúncio
-- em campos (link, portal, id_anuncio, titulo, tipo, finalidade, preco, bairro,
-- condominio_nome, area_m2, quartos..., telefone -- tudo opcional menos o link)
-- e saem os CANDIDATOS parecidos, cada um com nota de 0 a 100, o que bateu e o
-- que diverge. Quem decide se é o mesmo imóvel é outro agente; aqui só se mede.
--
-- A NOTA (soma, com teto em 100):
--   mesmo link ou mesmo id do portal ........ 100  (confiança alta)
--   mesmo telefone do proprietário ..........  45  (confiança alta)
--   condomínio igual ........................  35  (parecido: 20)
--   área em até 3% ..........................  20  (até 10%: 12)
--   preço em até 2% .........................  20  (até 15%: 15)
--   bairro ou CEP ...........................  10
--   rua .....................................  10
--   tipo ....................................   5
--   quartos 5, vagas 2, suítes 2, banheiros 1
--   condomínio igual + área em até 3% também é confiança alta (regra 2 do bot).
--   Entra na lista quem tem 30 ou mais; "média" a partir de 45.
--
-- CAMPO NULO NÃO DESCLASSIFICA, só não pontua (regra 4) -- dos dois lados: o
-- anúncio sem área e o imóvel nosso sem área dão zero ponto e zero divergência.
--
-- O CONDOMÍNIO SE COMPARA PELO NOME ESCRITO (`condominio_nome`), não pelo
-- `condo_id`: só 1.136 dos 5.676 imóveis têm o id, e 5.674 têm o nome. E pelo
-- NÚCLEO do nome (sem "Residencial", "Edifício"...), tirando o lixo de cadastro:
-- "Não identificado" está em 669 imóveis e "Casa" em 58 -- sem o filtro, todo
-- anúncio de casa "batia condomínio" com eles (foi o que o primeiro ensaio
-- mostrou).
--
-- OS LINKS: o que a Captação OLX já importou guarda `extras.olx_id` e
-- `extras.olx_url`; o que o bot confirmar daqui para a frente vai para a tabela
-- nova `imovel_anuncio` (crm_imovel_vincular_anuncio), e a próxima consulta do
-- mesmo anúncio bate por link.
--
-- A TABELA NÃO TEM FOREIGN KEY PARA `imoveis` de propósito: criar a FK pede
-- trava na tabela dos imóveis, que a Nay lê o tempo todo (em 28/09 um ALTER
-- TABLE de ensaio travou a Nay 2 min). Quem confere que o código existe é a
-- função que grava.
--
-- DO PROPRIETÁRIO SAI SÓ O FINAL DO TELEFONE ("**18"), que é o que o bot pediu
-- para conferir. Nome e número inteiro não saem daqui.
--
-- RESPONDE SOBRE O CATÁLOGO INTEIRO (vendido, alugado, removido, parceiro): se
-- já foi nosso, o bot tem de saber -- o status vai junto para ele decidir.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.imovel_anuncio (
  id            bigserial PRIMARY KEY,
  codigo        integer NOT NULL,
  portal        text NOT NULL DEFAULT 'olx',
  id_anuncio    text,
  link          text NOT NULL,
  link_normal   text NOT NULL,
  registrado_por text,
  registrado_em timestamptz NOT NULL DEFAULT now(),
  UNIQUE (codigo, link_normal)
);
CREATE INDEX IF NOT EXISTS imovel_anuncio_link ON public.imovel_anuncio (link_normal);
CREATE INDEX IF NOT EXISTS imovel_anuncio_id ON public.imovel_anuncio (id_anuncio) WHERE id_anuncio IS NOT NULL;
COMMENT ON TABLE public.imovel_anuncio IS
  '258: o anúncio de portal (OLX...) que alguém confirmou ser de um imóvel nosso. Sem FK de propósito (ver a migração).';

-- o link sem protocolo, sem www, sem ?parametros e sem barra no fim
CREATE OR REPLACE FUNCTION public.crm_anuncio_link_normal(p text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT nullif(regexp_replace(regexp_replace(regexp_replace(
           lower(btrim(coalesce(p, ''))), '^https?://(www\.)?', ''), '[?#].*$', ''), '/+$', ''), '');
$function$;

-- o id numérico do portal: o último número comprido do link (OLX: ...-1540696600)
CREATE OR REPLACE FUNCTION public.crm_anuncio_id_do_link(p text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT (regexp_match(crm_anuncio_link_normal(p), '([0-9]{6,})[^0-9]*$'))[1];
$function$;

-- número que pode vir como número (990000) ou como texto ("R$ 990.000,00")
CREATE OR REPLACE FUNCTION public.crm_anuncio_numero(v jsonb)
 RETURNS numeric LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE jsonb_typeof(v)
    WHEN 'number' THEN (v #>> '{}')::numeric
    WHEN 'string' THEN CASE
      WHEN (v #>> '{}') ~ '^\s*[0-9]+(\.[0-9]{1,2})?\s*$' THEN btrim(v #>> '{}')::numeric
      WHEN regexp_replace(v #>> '{}', '[^0-9.,]', '', 'g') ~ '^([0-9]{1,3}(\.[0-9]{3})+|[0-9]+)(,[0-9]{1,2})?$'
        THEN replace(replace(regexp_replace(v #>> '{}', '[^0-9.,]', '', 'g'), '.', ''), ',', '.')::numeric
      END
    END;
$function$;

-- a família do tipo: o anúncio diz "apartamento", o cadastro diz "Apartamento em
-- Via Pública", "Flat", "Cobertura"
CREATE OR REPLACE FUNCTION public.crm_anuncio_familia(p text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE
    WHEN t = '' THEN NULL
    WHEN t ~ 'lote|terreno|chacara|sitio|fazenda' THEN 'terreno'
    WHEN t ~ 'apart|apto|flat|cobertura|kitnet|kitinete|studio|loft|duplex' THEN 'apartamento'
    WHEN t ~ 'casa|sobrado' THEN 'casa'
    WHEN t ~ 'sala|loja|ponto|galpao|deposito|predio|comercial|andar' THEN 'comercial'
    END
  FROM (SELECT nay_sem_acento(lower(coalesce(p, ''))) AS t) x;
$function$;

-- as palavras do nome em ordem alfabética: "Smart Residence Downtown" (o anúncio)
-- e "Smart Downtown Residence" (o nosso cadastro) são o MESMO condomínio. Foi o
-- primeiro exemplo que o bot mandou, e sem isto ele saía só como "parecido".
CREATE OR REPLACE FUNCTION public.crm_anuncio_palavras(p text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT string_agg(w, ' ' ORDER BY w)
    FROM (SELECT DISTINCT w FROM regexp_split_to_table(coalesce(p, ''), '[^a-z0-9]+') w WHERE w <> '') x;
$function$;

CREATE OR REPLACE FUNCTION public.crm_imovel_candidatos(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
 -- JIT desligado, como em crm_parceria_marcas: `nai_chave` tem COST 500 e o
 -- Postgres resolvia compilar a consulta -- 0,5 a 1,5 s de compilação para 20 ms
 -- de trabalho (medido no ensaio).
 SET jit TO 'off'
AS $function$
DECLARE
  LIXO CONSTANT text[] := ARRAY['nao identificado', 'casa', 'predio', 'livre', 'apartamento', 'terreno',
                                'sala', 'loja', 'galpao', 'kitnet', 'sobrado', 'lote', ''];
  v_link    text := crm_anuncio_link_normal(p ->> 'link');
  v_id      text;
  v_fam     text := crm_anuncio_familia(coalesce(p ->> 'tipo', p ->> 'titulo'));
  v_fin     text;
  v_preco   numeric := crm_anuncio_numero(p -> 'preco');
  v_area    numeric := crm_anuncio_numero(p -> 'area_m2');
  v_quartos numeric := crm_anuncio_numero(p -> 'quartos');
  v_suites  numeric := crm_anuncio_numero(p -> 'suites');
  v_banh    numeric := crm_anuncio_numero(p -> 'banheiros');
  v_vagas   numeric := crm_anuncio_numero(p -> 'vagas');
  v_taxa    numeric := crm_anuncio_numero(p -> 'valor_condominio');
  v_cidade  text := nullif(nay_sem_acento(lower(btrim(coalesce(p ->> 'cidade', '')))), '');
  v_cep     text := nullif(regexp_replace(coalesce(p ->> 'cep', ''), '\D', '', 'g'), '');
  v_bairro  text;      -- o bairro do anúncio, com o nome que o CATÁLOGO usa
  v_condo   text := nay_sem_acento(lower(nai_condominio_nucleo(coalesce(p ->> 'condominio_nome', ''))));
  v_rua     text;
  v_fone    text := nai_chave(p ->> 'telefone');
  v_donos   int[] := '{}';
  v_do_link int[] := '{}';
  v_tit     text := ' ' || nay_sem_acento(lower(coalesce(p ->> 'titulo', ''))) || ' ';
  v_lista   jsonb;
BEGIN
  IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RETURN jsonb_build_object('consulta_ok', false, 'erro', 'mande um objeto JSON com os campos do anúncio');
  END IF;

  v_id := coalesce(nullif(regexp_replace(coalesce(p ->> 'id_anuncio', ''), '\D', '', 'g'), ''),
                   crm_anuncio_id_do_link(p ->> 'link'));
  v_fin := CASE WHEN nay_sem_acento(lower(coalesce(p ->> 'finalidade', ''))) ~ 'alug|loca' THEN 'aluguel'
                WHEN nay_sem_acento(lower(coalesce(p ->> 'finalidade', ''))) ~ 'vend|compra' THEN 'venda'
                WHEN v_tit ~ '\m(aluga|alugo|aluguel|locacao)' AND v_tit !~ '\m(venda|vendo|vende)' THEN 'aluguel'
                WHEN v_tit ~ '\m(venda|vendo|vende)' AND v_tit !~ '\m(aluga|alugo|aluguel|locacao)' THEN 'venda' END;
  IF v_condo = ANY (LIXO) OR length(v_condo) < 3 THEN v_condo := NULL; END IF;

  -- o bairro do anúncio no nome do catálogo (igual; senão, o mais parecido)
  IF coalesce(btrim(p ->> 'bairro'), '') <> '' THEN
    SELECT b.bairro INTO v_bairro FROM bairro_normal b
     WHERE b.normal = nay_normalizar_lugar(p ->> 'bairro', true) LIMIT 1;
    IF v_bairro IS NULL THEN
      SELECT b.bairro INTO v_bairro FROM bairro_normal b
       WHERE similarity(b.normal, nay_normalizar_lugar(p ->> 'bairro', true)) >= 0.6
       ORDER BY similarity(b.normal, nay_normalizar_lugar(p ->> 'bairro', true)) DESC LIMIT 1;
    END IF;
  END IF;

  -- a rua: sem "rua/av./travessa" na frente e sem o número; 6 letras ou mais
  v_rua := nullif(btrim(regexp_replace(regexp_replace(nay_sem_acento(lower(coalesce(p ->> 'endereco', ''))),
             '^\s*(rua|r\.?|avenida|av\.?|travessa|tv\.?|estrada|rodovia|alameda|al\.?)\s+', ''),
             '[,0-9-].*$', '')), '');
  IF length(coalesce(v_rua, '')) < 6 THEN v_rua := NULL; END IF;

  -- sem o nome do condomínio no campo, ele costuma estar no TÍTULO ("Venda
  -- apartamento SMART RESIDENCE DOWNTOWN"): procuro um nome do catálogo ali
  IF v_condo IS NULL AND btrim(v_tit) <> '' THEN
    WITH cand AS MATERIALIZED (
      SELECT x.nome FROM (
        SELECT nay_sem_acento(lower(nai_condominio_nucleo(d.nome))) AS nome
          FROM (SELECT DISTINCT i.condominio_nome AS nome FROM imoveis i
                 WHERE coalesce(btrim(i.condominio_nome), '') <> '') d) x
       WHERE length(x.nome) >= 5 AND strpos(v_tit, x.nome) > 0
    )
    SELECT c.nome INTO v_condo FROM cand c
     WHERE NOT (c.nome = ANY (LIXO))
       AND NOT EXISTS (SELECT 1 FROM bairro_normal b WHERE b.normal = c.nome)
       AND NOT EXISTS (SELECT 1 FROM nai_lugar_avenida a WHERE nay_sem_acento(lower(a.nome)) LIKE '%' || c.nome || '%')
       AND v_tit ~ ('(^|[^a-z0-9])' || regexp_replace(c.nome, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '([^a-z0-9]|$)')
     ORDER BY length(c.nome) DESC LIMIT 1;
  END IF;

  IF v_link IS NULL AND v_id IS NULL AND v_fone IS NULL AND v_condo IS NULL AND v_bairro IS NULL
     AND v_cep IS NULL AND v_rua IS NULL AND v_preco IS NULL AND v_area IS NULL THEN
    RETURN jsonb_build_object('consulta_ok', false,
      'erro', 'não veio nada que dê para comparar: mande pelo menos o link, ou condomínio, bairro, preço ou área');
  END IF;

  -- quem já está ligado a este anúncio (pelo link ou pelo id do portal)
  IF v_link IS NOT NULL OR v_id IS NOT NULL THEN
    SELECT coalesce(array_agg(DISTINCT c), '{}') INTO v_do_link FROM (
      SELECT a.codigo AS c FROM imovel_anuncio a
       WHERE a.link_normal = v_link OR (v_id IS NOT NULL AND a.id_anuncio = v_id)
      UNION
      SELECT i.codigo FROM imoveis i
       WHERE (v_id IS NOT NULL AND i.extras ->> 'olx_id' = v_id)
          OR (v_link IS NOT NULL AND i.extras ? 'olx_url' AND crm_anuncio_link_normal(i.extras ->> 'olx_url') = v_link)
    ) z;
  END IF;

  -- os proprietários que têm este telefone
  IF v_fone IS NOT NULL THEN
    SELECT coalesce(array_agg(pr.id), '{}') INTO v_donos
      FROM proprietarios pr
     WHERE coalesce(pr.telefone, '') <> '' AND nai_chave(pr.telefone) = v_fone;
  END IF;

  WITH nomes AS MATERIALIZED (
    SELECT d.nome, nay_sem_acento(lower(nai_condominio_nucleo(d.nome))) AS nucleo,
           crm_anuncio_palavras(nay_sem_acento(lower(nai_condominio_nucleo(d.nome)))) AS palavras
      FROM (SELECT DISTINCT i.condominio_nome AS nome FROM imoveis i) d
  ),
  base AS (
    SELECT i.*, n.nucleo, n.palavras,
           coalesce(i.proprietario_id, ip.proprietario_id) AS dono,
           coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) AS area,
           crm_anuncio_familia(i.tipo) AS familia,
           -- o preço do banco que se compara: o da finalidade; sem finalidade, o mais perto
           CASE WHEN v_fin = 'aluguel' THEN nullif(i.valor_aluguel, 0)
                WHEN v_fin = 'venda'   THEN nullif(i.valor_venda, 0)
                WHEN v_preco IS NULL   THEN coalesce(nullif(i.valor_venda, 0), nullif(i.valor_aluguel, 0))
                WHEN nullif(i.valor_venda, 0) IS NULL THEN nullif(i.valor_aluguel, 0)
                WHEN nullif(i.valor_aluguel, 0) IS NULL THEN i.valor_venda
                WHEN abs(i.valor_venda - v_preco) <= abs(i.valor_aluguel - v_preco) THEN i.valor_venda
                ELSE i.valor_aluguel END AS preco
      FROM imoveis i
      LEFT JOIN nomes n ON n.nome IS NOT DISTINCT FROM i.condominio_nome
      LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
  ),
  pontos AS (
    SELECT b.*,
           (b.codigo = ANY (v_do_link)) AS m_link,
           (b.dono = ANY (v_donos)) AS m_fone,
           CASE WHEN v_condo IS NULL OR b.nucleo IS NULL OR b.nucleo = ANY (LIXO) THEN 0
                WHEN b.nucleo = v_condo OR b.palavras = crm_anuncio_palavras(v_condo) THEN 2
                WHEN length(b.nucleo) >= 5 AND length(v_condo) >= 5
                     AND (b.nucleo LIKE '%' || v_condo || '%' OR v_condo LIKE '%' || b.nucleo || '%') THEN 1
                WHEN similarity(b.nucleo, v_condo) >= 0.5 THEN 1
                ELSE 0 END AS m_condo,
           CASE WHEN v_area IS NULL OR b.area IS NULL THEN 0
                WHEN abs(b.area - v_area) <= v_area * 0.03 THEN 2
                WHEN abs(b.area - v_area) <= v_area * 0.10 THEN 1 ELSE 0 END AS m_area,
           CASE WHEN v_preco IS NULL OR b.preco IS NULL THEN 0
                WHEN abs(b.preco - v_preco) <= v_preco * 0.02 THEN 2
                WHEN abs(b.preco - v_preco) <= v_preco * 0.15 THEN 1 ELSE 0 END AS m_preco,
           (v_bairro IS NOT NULL AND b.bairro = v_bairro) AS m_bairro,
           (v_cep IS NOT NULL AND length(v_cep) = 8 AND regexp_replace(coalesce(b.cep, ''), '\D', '', 'g') = v_cep) AS m_cep,
           (v_rua IS NOT NULL AND nay_sem_acento(lower(coalesce(b.logradouro, ''))) LIKE '%' || v_rua || '%') AS m_rua,
           (v_fam IS NOT NULL AND b.familia = v_fam) AS m_tipo,
           (v_quartos IS NOT NULL AND b.quartos = v_quartos) AS m_quartos,
           (v_vagas   IS NOT NULL AND b.vagas = v_vagas) AS m_vagas,
           (v_suites  IS NOT NULL AND b.suites = v_suites) AS m_suites,
           (v_banh    IS NOT NULL AND b.banheiros = v_banh) AS m_banh
      FROM base b
  ),
  nota AS (
    SELECT t.*,
           least(100,
             CASE WHEN t.m_link THEN 100 ELSE 0 END
           + CASE WHEN t.m_fone THEN 45 ELSE 0 END
           + CASE t.m_condo WHEN 2 THEN 35 WHEN 1 THEN 20 ELSE 0 END
           + CASE t.m_area  WHEN 2 THEN 20 WHEN 1 THEN 12 ELSE 0 END
           + CASE t.m_preco WHEN 2 THEN 20 WHEN 1 THEN 15 ELSE 0 END
           + CASE WHEN t.m_bairro OR t.m_cep THEN 10 ELSE 0 END
           + CASE WHEN t.m_rua THEN 10 ELSE 0 END
           + CASE WHEN t.m_tipo THEN 5 ELSE 0 END
           + CASE WHEN t.m_quartos THEN 5 ELSE 0 END
           + CASE WHEN t.m_vagas THEN 2 ELSE 0 END
           + CASE WHEN t.m_suites THEN 2 ELSE 0 END
           + CASE WHEN t.m_banh THEN 1 ELSE 0 END) AS score
      FROM pontos t
  ),
  top AS (
    -- outra cidade não é candidato, a não ser pelo link ou pelo telefone
    SELECT n.* FROM nota n
     WHERE n.m_link OR n.m_fone
        OR (n.score >= 30
            AND (v_cidade IS NULL OR coalesce(btrim(n.cidade), '') = ''
                 OR nay_sem_acento(lower(btrim(n.cidade))) = v_cidade))
     ORDER BY n.score DESC, abs(n.preco - v_preco) NULLS LAST, n.codigo
     LIMIT 10
  )
  SELECT jsonb_agg(jsonb_build_object(
           'id_imovel', t.codigo::text,
           'score', t.score,
           'confianca', CASE WHEN t.m_link OR t.m_fone OR (t.m_condo = 2 AND t.m_area = 2) THEN 'alta'
                             WHEN t.score >= 45 THEN 'media' ELSE 'baixa' END,
           'campos_que_bateram', to_jsonb(array_remove(ARRAY[
              CASE WHEN t.m_link THEN 'link' END,
              CASE WHEN t.m_fone THEN 'telefone' END,
              CASE WHEN t.m_condo > 0 THEN 'condominio_nome' END,
              CASE WHEN t.m_area > 0 THEN 'area_m2' END,
              CASE WHEN t.m_preco > 0 THEN 'preco' END,
              CASE WHEN t.m_bairro THEN 'bairro' END,
              CASE WHEN t.m_cep THEN 'cep' END,
              CASE WHEN t.m_rua THEN 'endereco' END,
              CASE WHEN t.m_tipo THEN 'tipo' END,
              CASE WHEN t.m_quartos THEN 'quartos' END,
              CASE WHEN t.m_vagas THEN 'vagas' END,
              CASE WHEN t.m_suites THEN 'suites' END,
              CASE WHEN t.m_banh THEN 'banheiros' END], NULL)),
           -- diverge quem tem valor DOS DOIS LADOS e não bateu. Campo vazio de um
           -- lado não é divergência (regra 4).
           'campos_divergentes', coalesce((
              SELECT jsonb_agg(jsonb_build_object('campo', d.campo, 'banco', d.banco, 'anuncio', d.anuncio))
                FROM (VALUES
                  ('preco', to_jsonb(t.preco), to_jsonb(v_preco), v_preco IS NOT NULL AND t.preco IS NOT NULL AND t.m_preco = 0),
                  ('finalidade', to_jsonb(array_to_string(array_remove(ARRAY[
                       CASE WHEN coalesce(t.valor_venda, 0) > 0 THEN 'venda' END,
                       CASE WHEN coalesce(t.valor_aluguel, 0) > 0 THEN 'aluguel' END], NULL), '+')), to_jsonb(v_fin),
                     v_fin IS NOT NULL AND (coalesce(t.valor_venda, 0) > 0 OR coalesce(t.valor_aluguel, 0) > 0)
                     AND NOT ((v_fin = 'venda' AND coalesce(t.valor_venda, 0) > 0)
                           OR (v_fin = 'aluguel' AND coalesce(t.valor_aluguel, 0) > 0))),
                  ('area_m2', to_jsonb(t.area), to_jsonb(v_area), v_area IS NOT NULL AND t.area IS NOT NULL AND t.m_area = 0),
                  ('condominio_nome', to_jsonb(t.condominio_nome), to_jsonb(p ->> 'condominio_nome'),
                     v_condo IS NOT NULL AND t.nucleo IS NOT NULL AND NOT (t.nucleo = ANY (LIXO)) AND t.m_condo = 0),
                  ('bairro', to_jsonb(t.bairro), to_jsonb(p ->> 'bairro'),
                     v_bairro IS NOT NULL AND coalesce(t.bairro, '') <> '' AND NOT t.m_bairro),
                  ('tipo', to_jsonb(t.tipo), to_jsonb(p ->> 'tipo'),
                     v_fam IS NOT NULL AND t.familia IS NOT NULL AND NOT t.m_tipo),
                  ('quartos', to_jsonb(t.quartos), to_jsonb(v_quartos), v_quartos IS NOT NULL AND t.quartos IS NOT NULL AND NOT t.m_quartos),
                  ('suites', to_jsonb(t.suites), to_jsonb(v_suites), v_suites IS NOT NULL AND t.suites IS NOT NULL AND NOT t.m_suites),
                  ('banheiros', to_jsonb(t.banheiros), to_jsonb(v_banh), v_banh IS NOT NULL AND t.banheiros IS NOT NULL AND NOT t.m_banh),
                  ('vagas', to_jsonb(t.vagas), to_jsonb(v_vagas), v_vagas IS NOT NULL AND t.vagas IS NOT NULL AND NOT t.m_vagas),
                  ('valor_condominio', to_jsonb(t.taxa_condominio), to_jsonb(v_taxa),
                     v_taxa IS NOT NULL AND coalesce(t.taxa_condominio, 0) > 0 AND abs(t.taxa_condominio - v_taxa) > v_taxa * 0.10)
                ) AS d(campo, banco, anuncio, diverge)
               WHERE d.diverge), '[]'::jsonb),
           'dados', jsonb_build_object(
              'titulo', coalesce(nullif(t.extras ->> 'olx_titulo', ''),
                          concat_ws(' - ', nullif(concat_ws(' ', t.tipo,
                            CASE WHEN NOT (coalesce(t.nucleo, '') = ANY (LIXO)) THEN t.condominio_nome END), ''), t.bairro)),
              'tipo', t.tipo,
              'preco', t.preco,
              'preco_venda', nullif(t.valor_venda, 0),
              'preco_aluguel', nullif(t.valor_aluguel, 0),
              'bairro', t.bairro, 'cidade', t.cidade,
              'endereco', nullif(concat_ws(', ', nullif(btrim(t.logradouro), ''), nullif(btrim(t.numero), '')), ''),
              'cep', t.cep,
              'condominio_nome', CASE WHEN NOT (coalesce(t.nucleo, '') = ANY (LIXO)) THEN t.condominio_nome END,
              'area_m2', t.area, 'quartos', t.quartos, 'suites', t.suites,
              'banheiros', t.banheiros, 'vagas', t.vagas,
              'valor_condominio', nullif(t.taxa_condominio, 0),
              'links_portais', coalesce((
                 SELECT jsonb_agg(DISTINCT l.link) FROM (
                   SELECT a.link FROM imovel_anuncio a WHERE a.codigo = t.codigo
                   UNION SELECT t.extras ->> 'olx_url' WHERE coalesce(t.extras ->> 'olx_url', '') <> '') l), '[]'::jsonb),
              'proprietario_telefone_final', (
                 SELECT '**' || right(regexp_replace(pr.telefone, '\D', '', 'g'), 2)
                   FROM proprietarios pr
                  WHERE pr.id = t.dono AND length(regexp_replace(coalesce(pr.telefone, ''), '\D', '', 'g')) >= 8),
              'status', t.status,
              'no_mercado', nay_esta_no_mercado(t.disponivel, t.bloqueado, t.publicado_no_site),
              'publicado_no_site', coalesce(t.publicado_no_site, false),
              'de_parceiro', coalesce(t.e_parceiro, false),
              'atualizado_em', to_char(coalesce(t.sincronizado_em, t.criado_em), 'YYYY-MM-DD'))
         ) ORDER BY t.score DESC, abs(t.preco - v_preco) NULLS LAST, t.codigo)
    INTO v_lista
    FROM top t;

  v_lista := coalesce(v_lista, '[]'::jsonb);
  RETURN jsonb_build_object(
    'consulta_ok', true,
    'total_candidatos', jsonb_array_length(v_lista),
    'melhor_score', coalesce((v_lista -> 0 ->> 'score')::int, 0),
    -- o que eu entendi do anúncio: se a busca não achou, dá para ver por quê
    'entendido', jsonb_strip_nulls(jsonb_build_object(
       'link', v_link, 'id_anuncio', v_id, 'finalidade', v_fin, 'tipo', v_fam, 'preco', v_preco,
       'bairro', v_bairro, 'cep', v_cep, 'condominio', v_condo, 'rua', v_rua, 'area_m2', v_area,
       'quartos', v_quartos,
       'telefone_conhecido', CASE WHEN v_fone IS NOT NULL THEN coalesce(array_length(v_donos, 1), 0) > 0 END)),
    'candidatos', v_lista);
EXCEPTION WHEN others THEN
  -- nunca resposta vazia: o bot leria como "não é nosso"
  RETURN jsonb_build_object('consulta_ok', false, 'erro', 'falha na busca: ' || SQLERRM);
END
$function$;
COMMENT ON FUNCTION crm_imovel_candidatos(jsonb) IS
  '258: o grokbot manda o anúncio em campos e recebe os imóveis parecidos do catálogo, com nota, o que bateu e o que diverge';

-- O BOT CONFIRMOU QUE É O MESMO IMÓVEL: guarda o link, e a próxima consulta
-- desse anúncio bate em 100.
CREATE OR REPLACE FUNCTION public.crm_imovel_vincular_anuncio(p_codigo integer, p_link text, p_portal text DEFAULT NULL, p_id_anuncio text DEFAULT NULL, p_quem text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_normal text := crm_anuncio_link_normal(p_link);
  v_id     text := coalesce(nullif(regexp_replace(coalesce(p_id_anuncio, ''), '\D', '', 'g'), ''), crm_anuncio_id_do_link(p_link));
  v_portal text := lower(coalesce(nullif(btrim(p_portal), ''),
                     CASE WHEN crm_anuncio_link_normal(p_link) LIKE '%olx.com.br%' THEN 'olx' ELSE 'outro' END));
  v_outro  int;
  v_novo   bigint;
BEGIN
  IF p_codigo IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'não existe imóvel com o id ' || coalesce(p_codigo::text, '(vazio)'));
  END IF;
  IF v_normal IS NULL OR v_normal !~ '^[a-z0-9.-]+\.[a-z]{2,}/' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'o link não parece um endereço de anúncio');
  END IF;
  -- o mesmo anúncio em DOIS imóveis é erro de quem confirmou: não gravo, aviso
  SELECT a.codigo INTO v_outro FROM imovel_anuncio a
   WHERE a.codigo <> p_codigo AND (a.link_normal = v_normal OR (v_id IS NOT NULL AND a.id_anuncio = v_id AND a.portal = v_portal))
   LIMIT 1;
  IF v_outro IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'id_imovel_atual', v_outro::text,
      'erro', 'este anúncio já está registrado no imóvel ' || v_outro || '; não registrei em outro');
  END IF;
  INSERT INTO imovel_anuncio (codigo, portal, id_anuncio, link, link_normal, registrado_por)
  VALUES (p_codigo, left(v_portal, 30), v_id, left(btrim(p_link), 600), v_normal, left(coalesce(nullif(btrim(p_quem), ''), 'grokbot'), 60))
  ON CONFLICT (codigo, link_normal) DO NOTHING
  RETURNING id INTO v_novo;
  RETURN jsonb_build_object('ok', true, 'id_imovel', p_codigo::text, 'link', v_normal, 'id_anuncio', v_id,
    'ja_estava', v_novo IS NULL,
    'mensagem', CASE WHEN v_novo IS NULL THEN 'esse link já estava registrado nesse imóvel'
                     ELSE 'link registrado: a próxima consulta desse anúncio bate por link' END);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('ok', false, 'erro', 'falha ao registrar: ' || SQLERRM);
END
$function$;
COMMENT ON FUNCTION crm_imovel_vincular_anuncio(integer, text, text, text, text) IS
  '258: registra o link de um anúncio num imóvel nosso, depois de confirmado que é o mesmo';

REVOKE ALL ON FUNCTION crm_imovel_candidatos(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_imovel_candidatos(jsonb) TO nay_disparo;
REVOKE ALL ON FUNCTION crm_imovel_vincular_anuncio(integer, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_imovel_vincular_anuncio(integer, text, text, text, text) TO nay_disparo;
COMMIT;
