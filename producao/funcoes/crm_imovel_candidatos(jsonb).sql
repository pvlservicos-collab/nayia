CREATE OR REPLACE FUNCTION public.crm_imovel_candidatos(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
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
              -- 262: rua e número separados (o bot grava em campos separados)
              'endereco', nullif(btrim(regexp_replace(regexp_replace(coalesce(t.logradouro, ''),
                            ',\s*(n[º°o.]?\s*)?[0-9].*$', ''), '\s*,\s*(-|,|$).*$', ''), ' ,-'), ''),
              'numero', coalesce(nullif(btrim(t.numero), ''),
                                 (regexp_match(coalesce(t.logradouro, ''), ',\s*(?:n[º°o.]?\s*)?([0-9]+[A-Za-z]?)'))[1]),
              'complemento', nullif(btrim(t.complemento), ''),
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
