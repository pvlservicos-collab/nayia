-- 286 (03/10/2026): NA AGENDA DOS GRUPOS, A LISTA DE IMÓVEIS E AS MÉTRICAS (a coluna `vagas.texto_fixo` é da 285).
--
-- Pedro, 03/10: "quero também lá na página de agenda que crie, no criar mensagem, lista de imóveis, e editar essa
-- mensagem fisicamente: hoje tu só edita horários" (com a foto da lista do Tel: "🔥 APARTAMENTOS PARA LOCAÇÃO DE
-- 1.1k A 10k 🔥" e uma linha ✅ por imóvel) e "quero também um painel de métricas lá na agenda, uma outra aba ao
-- lado de Grupos, que mostra quantas vezes saiu cada mensagem, e uma estimativa de pessoas que chegaram marcando
-- ela ou perguntando de imóveis dela".
--
-- 1. A LISTA pelo site. A vaga de lista (categoria + negócio + destino) só nascia pelo comando do Tel no WhatsApp
--    e o site só mudava o horário. Agora `site_grade_salvar` cria e edita a lista, e `site_grade_lista_previa`
--    devolve o texto como sai hoje (o mesmo `nay_lista_de_imoveis` do publicador).
-- 2. O TEXTO EDITADO À MÃO: `vagas.texto_fixo`. Vazio = a lista é montada na hora do envio, como sempre. Preenchido
--    = sai o que foi escrito; o publicador só tira, na hora, a linha de imóvel que saiu do mercado e, em grupo com
--    regra (piso do Alto Padrão, só comercial), a linha que o grupo não aceita. Os valores NÃO se atualizam sozinhos.
-- 3. A AGENDA media a lista errado: lista não grava em `envios`, e a função dava a ela os posts de OUTROS imóveis
--    que saíam até 90 min depois. A lista agora é medida por `lista_disparada` (grupos que receberam) e, desde a
--    281, por `envios_lista_grupo` (ids e códigos, para saber quem marcou a lista).
-- 4. AS MÉTRICAS: `site_grade_metricas(de, ate)`. Por mensagem (vaga) e por imóvel: quantas vezes saiu, em quantos
--    posts, quem MARCOU o post no privado (citou a mensagem do grupo) e quem ESCREVEU O CÓDIGO de um imóvel dela
--    nas 6 h seguintes sem marcar. É estimativa: quem chegou perguntando sem código e sem marcar não é contado.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ------------------------------------------------------------------ as opções da tela
CREATE OR REPLACE FUNCTION public.site_grade_opcoes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'grupos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', g.id_grupo, 'nome', g.nome, 'apelido', g.apelido,
                                  'ativo', g.ativo, 'venda', g.aceita_venda, 'locacao', g.aceita_locacao,
                                  'so_condominio', g.so_condominio, 'so_comercial', g.so_comercial,
                                  -- 280: o que a tela precisa para mostrar o post como ele chega neste grupo
                                  'todas_fotos', g.todas_fotos, 'venda_minima', g.venda_minima,
                                  'aluguel_minimo', g.aluguel_minimo, 'lotado', coalesce(g.apelido = 'lotado', false))
                                ORDER BY g.nome) FROM grupos g), '[]'::jsonb),
    'destinos', coalesce((SELECT jsonb_agg(jsonb_build_object('apelido', d.apelido, 'grupos', d.nomes) ORDER BY d.apelido)
                            FROM (SELECT g.apelido, array_agg(g.nome ORDER BY g.nome) AS nomes FROM grupos g
                                   WHERE g.ativo AND coalesce(g.apelido, '') NOT IN ('', 'lotado') GROUP BY g.apelido) d), '[]'::jsonb),
    -- 285: a lista de imóveis (as categorias e os destinos do publicador: interpretar_comando.py e _disparar_lista)
    'categorias', jsonb_build_array(
      jsonb_build_object('chave', 'apartamento', 'nome', 'Apartamento'),
      jsonb_build_object('chave', 'apartamento_via_publica', 'nome', 'Apartamento em via pública'),
      jsonb_build_object('chave', 'casa_condominio', 'nome', 'Casa em condomínio'),
      jsonb_build_object('chave', 'casa_via_publica', 'nome', 'Casa em via pública'),
      jsonb_build_object('chave', 'sala', 'nome', 'Sala comercial'),
      jsonb_build_object('chave', 'lote', 'nome', 'Lote')),
    'destinos_lista', jsonb_build_array(
      jsonb_build_object('chave', 'parceiros', 'nome', 'Grupos de parceiros'),
      jsonb_build_object('chave', 'easy', 'nome', 'Imóveis para anunciar Easy'),
      jsonb_build_object('chave', 'comercial', 'nome', 'Comercial')));
$function$;

-- ------------------------------------------------------------------ a lista como sai hoje
CREATE OR REPLACE FUNCTION public.site_grade_lista_previa(p_categoria text, p_negocio text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
  IF coalesce(p_categoria, '') NOT IN ('apartamento', 'apartamento_via_publica', 'casa_condominio', 'casa_via_publica', 'sala', 'lote')
     OR coalesce(p_negocio, '') NOT IN ('locacao', 'venda') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Escolha o tipo de imóvel e se é locação ou venda.');
  END IF;
  SELECT texto_pronto, quantos INTO r FROM nay_lista_de_imoveis(p_categoria, p_negocio);
  RETURN jsonb_build_object('ok', true, 'quantos', coalesce(r.quantos, 0),
                            'texto', CASE WHEN coalesce(r.quantos, 0) > 0 THEN r.texto_pronto END);
END;
$function$;

-- ------------------------------------------------------------------ criar e editar
CREATE OR REPLACE FUNCTION public.site_grade_salvar(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id      int := nullif(p->>'id', '')::int;
  v_atual   vagas%ROWTYPE;
  v_hora    time;
  v_rec     text := coalesce(p->>'recorrencia', 'diaria');
  v_dias    int[];
  v_data    date;
  v_cods    text[];
  v_dest    text := nullif(btrim(coalesce(p->>'destino', '')), '');
  v_ruins   text[];
  v_cat     text := nullif(btrim(coalesce(p->>'categoria', '')), '');
  v_neg     text := nullif(btrim(coalesce(p->>'negocio', '')), '');
  v_texto   text;
BEGIN
  IF v_id IS NOT NULL THEN
    SELECT * INTO v_atual FROM vagas WHERE id = v_id;
    IF v_atual.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Essa mensagem não existe mais.'); END IF;
  END IF;
  BEGIN
    v_hora := (p->>'horario')::time;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Horário inválido (use 07:30).');
  END;
  IF v_hora IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Diga o horário.'); END IF;
  IF v_rec NOT IN ('diaria', 'semanal', 'unica') THEN RETURN jsonb_build_object('ok', false, 'erro', 'Repetição inválida.'); END IF;
  IF v_rec = 'semanal' THEN
    SELECT array_agg(DISTINCT d ORDER BY d) INTO v_dias
      FROM jsonb_array_elements_text(coalesce(p->'dias', '[]'::jsonb)) x(t), LATERAL (SELECT x.t::int AS d) y
     WHERE y.d BETWEEN 0 AND 6;
    IF coalesce(cardinality(v_dias), 0) = 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'Escolha os dias da semana.'); END IF;
  ELSIF v_rec = 'unica' THEN
    BEGIN v_data := (p->>'data')::date; EXCEPTION WHEN OTHERS THEN v_data := NULL; END;
    IF v_data IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Escolha o dia.'); END IF;
    IF (v_data + v_hora) AT TIME ZONE 'America/Manaus' < now() THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Esse dia e horário já passaram.');
    END IF;
  END IF;

  -- A LISTA DE IMÓVEIS (285): nova (veio a categoria) ou a edição de uma vaga que já é de lista. O tipo da
  -- mensagem não muda na edição: lista continua lista, imóvel continua imóvel.
  IF (v_id IS NULL AND v_cat IS NOT NULL) OR v_atual.categoria IS NOT NULL THEN
    v_cat  := coalesce(v_cat, v_atual.categoria);
    v_neg  := coalesce(v_neg, v_atual.negocio);
    v_dest := coalesce(v_dest, v_atual.destino, 'parceiros');
    IF v_cat NOT IN ('apartamento', 'apartamento_via_publica', 'casa_condominio', 'casa_via_publica', 'sala', 'lote') THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Escolha o tipo de imóvel da lista.');
    END IF;
    IF coalesce(v_neg, '') NOT IN ('locacao', 'venda') THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Diga se a lista é de locação ou de venda.');
    END IF;
    IF v_dest NOT IN ('parceiros', 'easy', 'comercial') THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Destino da lista inválido.');
    END IF;
    -- o texto: a chave ausente não mexe no que está gravado (a tela antiga só mudava o horário)
    v_texto := CASE WHEN p ? 'texto_fixo' THEN nullif(btrim(coalesce(p->>'texto_fixo', '')), '') ELSE v_atual.texto_fixo END;
    IF v_texto IS NOT NULL THEN
      IF length(v_texto) > 20000 THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'O texto ficou grande demais (o limite é de 20 mil letras).');
      END IF;
      -- a parede do publicador na hora do envio é pela linha "cod 1234": sem nenhum imóvel no ar, não há lista
      IF NOT EXISTS (SELECT 1 FROM regexp_matches(v_texto, '\mcod\.?\s*(\d{3,5})\M', 'gi') m
                       JOIN imoveis i ON i.codigo = m[1]::int
                      WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                        AND NOT coalesce(i.e_parceiro, false)) THEN
        RETURN jsonb_build_object('ok', false, 'erro',
          'O texto precisa ter pelo menos um imóvel que está no ar, escrito como na lista: "cod 1234".');
      END IF;
    ELSIF (SELECT quantos FROM nay_lista_de_imoveis(v_cat, v_neg)) = 0 AND v_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Hoje não há nenhum imóvel nessa lista: nada sairia.');
    END IF;
    BEGIN
      IF v_id IS NULL THEN
        INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, data_unica, categoria, negocio, destino, texto_fixo)
        VALUES (v_hora, v_rec, CASE WHEN v_rec = 'semanal' THEN v_dias END, CASE WHEN v_rec = 'unica' THEN v_data END,
                v_cat, v_neg, v_dest, v_texto)
        RETURNING id INTO v_id;
      ELSE
        UPDATE vagas SET horario = v_hora, tipo_recorrencia = v_rec,
                         dias_semana = CASE WHEN v_rec = 'semanal' THEN v_dias END,
                         data_unica = CASE WHEN v_rec = 'unica' THEN v_data END,
                         categoria = v_cat, negocio = v_neg, destino = v_dest, texto_fixo = v_texto
         WHERE id = v_id;
      END IF;
    EXCEPTION WHEN unique_violation THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Já existe essa lista, nesse horário e para esse destino.');
    END;
    RETURN jsonb_build_object('ok', true, 'id', v_id);
  END IF;

  -- o destino: um apelido de grupo que existe (vazio = cada imóvel vai aos grupos que aceitam o tipo e o valor dele)
  IF v_dest IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM grupos g WHERE g.ativo AND g.apelido = v_dest AND v_dest <> 'lotado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Esse grupo de destino não existe.');
  END IF;

  -- os imóveis: na ordem escritos, sem repetir, até 10
  SELECT array_agg(c ORDER BY n) INTO v_cods FROM (
    SELECT DISTINCT ON (c) c, n FROM (
      SELECT regexp_replace(x.t, '\D', '', 'g') AS c, x.n
        FROM jsonb_array_elements_text(coalesce(p->'codigos', '[]'::jsonb)) WITH ORDINALITY x(t, n)) y
     WHERE c <> '' ORDER BY c, n) z;
  IF coalesce(cardinality(v_cods), 0) = 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'Escolha pelo menos um imóvel.'); END IF;
  IF cardinality(v_cods) > 10 THEN RETURN jsonb_build_object('ok', false, 'erro', 'No máximo 10 imóveis por mensagem.'); END IF;
  -- as paredes do publicador: imóvel que existe, no ar, e nunca de parceiro (parceria não sai nos grupos)
  SELECT array_agg(c.cod || CASE WHEN i.codigo IS NULL THEN ' (não existe)'
                                 WHEN coalesce(i.e_parceiro, false) THEN ' (é de parceiro)'
                                 ELSE ' (não está no ar)' END)
    INTO v_ruins
    FROM unnest(v_cods) c(cod) LEFT JOIN imoveis i ON i.codigo::text = c.cod
   WHERE i.codigo IS NULL OR coalesce(i.e_parceiro, false)
      OR NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site);
  IF v_ruins IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Não dá para agendar: ' || array_to_string(v_ruins, ', ') || '.');
  END IF;

  BEGIN
    IF v_id IS NULL THEN
      INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, data_unica, codigos, destino)
      VALUES (v_hora, v_rec, CASE WHEN v_rec = 'semanal' THEN v_dias END, CASE WHEN v_rec = 'unica' THEN v_data END, v_cods, v_dest)
      RETURNING id INTO v_id;
    ELSE
      UPDATE vagas SET horario = v_hora, tipo_recorrencia = v_rec,
                       dias_semana = CASE WHEN v_rec = 'semanal' THEN v_dias END,
                       data_unica = CASE WHEN v_rec = 'unica' THEN v_data END,
                       codigos = v_cods, destino = v_dest
       WHERE id = v_id;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Já existe uma mensagem com esses imóveis, nesse horário e para esse destino.');
  END;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$function$;

-- ------------------------------------------------------------------ a agenda (a lista medida pelo que ela grava)
CREATE OR REPLACE FUNCTION public.site_grade_agenda(p_de date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_de  date := greatest(coalesce(p_de, current_date), current_date - 180);
  v_ate date := least(coalesce(p_ate, coalesce(p_de, current_date) + 6), greatest(coalesce(p_de, current_date), current_date - 180) + 62);
  v_ini timestamptz;
  v_fim timestamptz;
  v_teste text[] := nai_chaves_teste();
  v jsonb;
BEGIN
  v_ini := v_de::timestamp AT TIME ZONE 'America/Manaus';
  v_fim := (v_ate + 1)::timestamp AT TIME ZONE 'America/Manaus';
  WITH gerais AS (   -- sem destino: os grupos ativos que recebem post de imóvel (todas_fotos é outro caminho)
    SELECT array_agg(id_grupo) AS ids FROM grupos WHERE ativo AND NOT coalesce(todas_fotos, false)
  ), vg AS (
    SELECT v.*,
           CASE WHEN v.categoria IS NOT NULL THEN   -- a LISTA: os destinos do `_disparar_lista` do publicador
                  (SELECT array_agg(g.id_grupo) FROM grupos g
                    WHERE g.ativo
                      AND CASE v.destino WHEN 'easy' THEN g.apelido = 'easy'
                                         WHEN 'comercial' THEN g.apelido = 'comercial'
                                         ELSE NOT coalesce(g.todas_fotos, false)
                                              AND (CASE WHEN v.negocio = 'venda' THEN g.aceita_venda ELSE g.aceita_locacao END)
                                              AND NOT (coalesce(g.so_comercial, false) AND v.categoria <> 'sala') END)
                WHEN EXISTS (SELECT 1 FROM grupos g WHERE g.ativo AND g.apelido = v.destino)
                THEN (SELECT array_agg(g.id_grupo) FROM grupos g WHERE g.ativo AND g.apelido = v.destino)
                ELSE (SELECT ids FROM gerais) END AS previstos
      FROM vagas v
  ), oc AS (
    SELECT vg.id AS vaga_id, ((d::date + vg.horario) AT TIME ZONE 'America/Manaus') AS quando
      FROM vg, generate_series(v_de::timestamp, v_ate::timestamp, interval '1 day') d
     WHERE (vg.tipo_recorrencia = 'diaria'
            OR (vg.tipo_recorrencia = 'semanal' AND extract(dow FROM d)::int = ANY (vg.dias_semana))
            OR (vg.tipo_recorrencia = 'unica' AND d::date = vg.data_unica))
       AND ((d::date + vg.horario) AT TIME ZONE 'America/Manaus') >= date_trunc('minute', vg.criado_em) - interval '1 minute'
  ), env AS (
    -- o post de IMÓVEL: o que o publicador gravou em `envios` na janela do horário
    SELECT oc.vaga_id, oc.quando,
           array_agg(DISTINCT e.grupo_nome) FILTER (WHERE e.grupo_nome IS NOT NULL) AS grupos,
           array_agg(DISTINCT e.message_id) FILTER (WHERE e.message_id IS NOT NULL) AS ids,
           array_agg(DISTINCT e.codigo) AS codigos,
           count(*) AS posts
      FROM oc JOIN vagas v ON v.id = oc.vaga_id AND v.categoria IS NULL AND cardinality(v.codigos) > 0
      JOIN envios e ON e.destino = 'grupo'
                   AND e.enviado_em >= oc.quando - interval '1 minute' AND e.enviado_em < oc.quando + interval '90 minutes'
                   AND e.codigo = ANY (v.codigos)
     WHERE oc.quando <= now()
     GROUP BY oc.vaga_id, oc.quando
    UNION ALL
    -- a LISTA (285): não grava em `envios`. Os grupos vêm de `lista_disparada`; os ids e os códigos, de
    -- `envios_lista_grupo` (desde a 281). Antes, a lista tomava os posts dos imóveis que saíam depois dela.
    SELECT oc.vaga_id, oc.quando, ld.grupos,
           (SELECT array_agg(DISTINCT x.message_id) FROM envios_lista_grupo x
             WHERE x.categoria = v.categoria AND x.negocio = v.negocio
               AND x.enviado_em >= ld.enviado_em - interval '1 minute' AND x.enviado_em < ld.enviado_em + interval '60 minutes'),
           (SELECT array_agg(DISTINCT x.codigo::text) FROM envios_lista_grupo x
             WHERE x.categoria = v.categoria AND x.negocio = v.negocio
               AND x.enviado_em >= ld.enviado_em - interval '1 minute' AND x.enviado_em < ld.enviado_em + interval '60 minutes'),
           cardinality(ld.grupos)::bigint
      FROM oc JOIN vagas v ON v.id = oc.vaga_id AND v.categoria IS NOT NULL
      JOIN LATERAL (SELECT l.grupos, l.enviado_em FROM lista_disparada l
                     WHERE l.categoria = v.categoria AND l.negocio = v.negocio AND l.destino = v.destino
                       AND l.enviado_em >= oc.quando - interval '1 minute' AND l.enviado_em < oc.quando + interval '30 minutes'
                       AND coalesce(cardinality(l.grupos), 0) > 0
                     ORDER BY l.enviado_em LIMIT 1) ld ON true
     WHERE oc.quando <= now()
  ), msgs0 AS MATERIALIZED (   -- o que chegou ao número da Parceria no período (+6 h)
    SELECT nai_chave(m.telefone) AS chave, m.criada_em, m.citado_id, m.texto
      FROM mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em >= v_ini AND m.criada_em < v_fim + interval '6 hours'
  ), quem AS MATERIALIZED (    -- equipe e teste saem: uma conta por PESSOA, não por mensagem
    SELECT d.chave, k.criado_em AS desde,
           (d.chave = ANY (v_teste)) OR (k.id IS NOT NULL AND nai_e_da_equipe_contato(k.id)) AS fora
      FROM (SELECT DISTINCT chave FROM msgs0 WHERE chave IS NOT NULL) d
      LEFT JOIN nai_contato k ON k.chave = d.chave
  ), msgs AS MATERIALIZED (
    SELECT m.chave, m.criada_em, m.citado_id, m.texto, q.desde
      FROM msgs0 m JOIN quem q ON q.chave = m.chave
     WHERE NOT q.fora
  ), met AS (
    SELECT env.vaga_id, env.quando,
           count(DISTINCT s.chave) AS pessoas,
           count(DISTINCT s.chave) FILTER (WHERE s.desde >= env.quando) AS novos,
           count(DISTINCT s.chave) FILTER (WHERE s.citado_id = ANY (coalesce(env.ids, '{}'::text[]))
                                              OR (cardinality(coalesce(env.codigos, '{}'::text[])) > 0
                                                  AND s.texto ~ ('\m(' || array_to_string(env.codigos, '|') || ')\M'))) AS pelo_imovel
      FROM env
      LEFT JOIN msgs s ON s.criada_em >= env.quando AND s.criada_em < env.quando + interval '6 hours'
     GROUP BY env.vaga_id, env.quando
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate, 'agora', now(),
    'vagas', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id', vg.id, 'horario', to_char(vg.horario, 'HH24:MI'), 'recorrencia', vg.tipo_recorrencia,
        'dias', to_jsonb(vg.dias_semana), 'data', vg.data_unica, 'destino', vg.destino,
        'categoria', vg.categoria, 'negocio', vg.negocio, 'texto_fixo', vg.texto_fixo, 'criada_em', vg.criado_em,
        'previstos', to_jsonb(vg.previstos),
        'imoveis', (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                        'codigo', c.cod, 'existe', i.codigo IS NOT NULL,
                        'titulo', coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo), 'bairro', i.bairro,
                        'venda', nullif(i.valor_venda, 0), 'aluguel', nullif(i.valor_aluguel, 0),
                        'no_ar', CASE WHEN i.codigo IS NULL THEN NULL
                                      ELSE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) END,
                        'parceiro', coalesce(i.e_parceiro, false),
                        'foto', (SELECT f.url FROM imovel_fotos f WHERE f.codigo = i.codigo AND coalesce(f.url, '') <> ''
                                    AND NOT coalesce(f.e_mosaico, false)
                                  ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1)))
                        ORDER BY c.n)
                      FROM unnest(vg.codigos) WITH ORDINALITY c(cod, n)
                      LEFT JOIN imoveis i ON i.codigo::text = c.cod)))
        ORDER BY vg.horario, vg.id) FROM vg), '[]'::jsonb),
    'ocorrencias', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'vaga', oc.vaga_id, 'quando', oc.quando, 'passou', oc.quando <= now(),
        'janela_completa', oc.quando + interval '6 hours' <= now(),
        'posts', env.posts, 'grupos', to_jsonb(env.grupos),
        'pessoas', met.pessoas, 'novos', met.novos, 'pelo_imovel', met.pelo_imovel))
        ORDER BY oc.quando, oc.vaga_id)
      FROM oc
      LEFT JOIN env ON env.vaga_id = oc.vaga_id AND env.quando = oc.quando
      LEFT JOIN met ON met.vaga_id = oc.vaga_id AND met.quando = oc.quando), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$function$;

-- ------------------------------------------------------------------ as métricas
CREATE OR REPLACE FUNCTION public.site_grade_metricas(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_ate date := least(coalesce(p_ate, current_date), current_date);
  v_de  date := greatest(coalesce(p_de, v_ate - 29), v_ate - 92);
  v_ini timestamptz;
  v_fim timestamptz;
  v_teste text[] := nai_chaves_teste();
  v jsonb;
BEGIN
  v_ini := v_de::timestamp AT TIME ZONE 'America/Manaus';
  v_fim := least((v_ate + 1)::timestamp AT TIME ZONE 'America/Manaus', now());
  WITH posts AS MATERIALIZED (   -- cada post de IMÓVEL num grupo, com o DISPARO a que pertence (posts do mesmo
                                 -- código a menos de 45 min um do outro são a mesma saída, grupo por grupo)
    SELECT x.*, sum(x.novo) OVER (PARTITION BY x.codigo ORDER BY x.enviado_em, x.id) AS ilha
      FROM (SELECT e.id, e.codigo, e.message_id, e.grupo_nome, e.enviado_em,
                   CASE WHEN e.enviado_em - lag(e.enviado_em) OVER (PARTITION BY e.codigo ORDER BY e.enviado_em, e.id)
                             <= interval '45 minutes' THEN 0 ELSE 1 END AS novo
              FROM envios e
             WHERE e.destino = 'grupo' AND e.enviado_em >= v_ini AND e.enviado_em < v_fim AND e.codigo ~ '^\d{2,6}$') x
  ), disp AS MATERIALIZED (      -- um disparo de imóvel: quando começou, quando acabou, em quantos grupos
    SELECT codigo, ilha, min(enviado_em) AS quando, max(enviado_em) AS ate, count(*) AS posts,
           array_agg(DISTINCT grupo_nome) FILTER (WHERE grupo_nome IS NOT NULL) AS grupos
      FROM posts GROUP BY codigo, ilha
  ), listas AS MATERIALIZED (    -- cada lista que saiu, com os ids e os códigos dela (existem desde a 281)
    SELECT l.id, l.categoria, l.negocio, l.destino, l.enviado_em AS quando, l.grupos, l.quantos,
           (SELECT array_agg(DISTINCT x.message_id) FROM envios_lista_grupo x
             WHERE x.categoria = l.categoria AND x.negocio = l.negocio
               AND x.enviado_em >= l.enviado_em - interval '1 minute' AND x.enviado_em < l.enviado_em + interval '60 minutes') AS ids,
           (SELECT array_agg(DISTINCT x.codigo::text) FROM envios_lista_grupo x
             WHERE x.categoria = l.categoria AND x.negocio = l.negocio
               AND x.enviado_em >= l.enviado_em - interval '1 minute' AND x.enviado_em < l.enviado_em + interval '60 minutes') AS codigos
      FROM lista_disparada l
     WHERE l.enviado_em >= v_ini AND l.enviado_em < v_fim AND coalesce(cardinality(l.grupos), 0) > 0
  ), msgs0 AS MATERIALIZED (     -- o que chegou ao número da Parceria (a marcação vale até 7 dias depois do post)
    SELECT nai_chave(m.telefone) AS chave, m.criada_em, m.citado_id, m.texto
      FROM mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em >= v_ini AND m.criada_em < v_fim + interval '7 days'
  ), quem AS MATERIALIZED (      -- equipe e teste saem
    SELECT d.chave, (d.chave = ANY (v_teste)) OR (k.id IS NOT NULL AND nai_e_da_equipe_contato(k.id)) AS fora
      FROM (SELECT DISTINCT chave FROM msgs0 WHERE chave IS NOT NULL) d
      LEFT JOIN nai_contato k ON k.chave = d.chave
  ), msgs AS MATERIALIZED (
    SELECT m.chave, m.criada_em, m.citado_id, m.texto
      FROM msgs0 m JOIN quem q ON q.chave = m.chave WHERE NOT q.fora
  ), marc AS MATERIALIZED (      -- quem MARCOU o post do grupo no privado
    SELECT DISTINCT p.codigo, p.ilha, s.chave
      FROM posts p JOIN msgs s ON s.citado_id = p.message_id
     WHERE p.message_id IS NOT NULL
  ), msgs_cod AS MATERIALIZED (  -- só as mensagens que trazem um número com cara de código (a maioria não traz)
    SELECT chave, criada_em, texto FROM msgs WHERE texto ~ '\d{3,5}'
  ), perg AS MATERIALIZED (      -- quem ESCREVEU O CÓDIGO até 6 h depois do disparo. O CASE garante a ordem: o
                                 -- horário é conferido antes do texto (sem ele, 30 dias levavam 9 s)
    SELECT DISTINCT d.codigo, d.ilha, s.chave
      FROM disp d CROSS JOIN msgs_cod s
     WHERE CASE WHEN s.criada_em >= d.quando AND s.criada_em < d.ate + interval '6 hours'
                THEN s.texto ~ ('\m' || d.codigo || '\M') ELSE false END
  ), gente AS MATERIALIZED (     -- por disparo de imóvel: a pessoa e como chegou (marcar vence escrever)
    SELECT codigo, ilha, chave, bool_or(marcou) AS marcou
      FROM (SELECT codigo, ilha, chave, true AS marcou FROM marc
            UNION ALL SELECT codigo, ilha, chave, false FROM perg) u
     GROUP BY codigo, ilha, chave
  ), lgente AS MATERIALIZED (    -- o mesmo para as listas
    SELECT l.id, s.chave, bool_or(s.citado_id = ANY (coalesce(l.ids, '{}'::text[]))) AS marcou
      FROM listas l JOIN msgs s
        ON s.citado_id = ANY (coalesce(l.ids, '{}'::text[]))
        OR (cardinality(coalesce(l.codigos, '{}'::text[])) > 0
            AND s.criada_em >= l.quando AND s.criada_em < l.quando + interval '6 hours'
            AND s.texto ~ ('\m(' || array_to_string(l.codigos, '|') || ')\M'))
     GROUP BY l.id, s.chave
  ), vd AS MATERIALIZED (        -- o disparo de imóvel é de qual mensagem da grade? (código, horário e dia batem)
    SELECT v.id AS vaga_id, d.codigo, d.ilha, d.quando, d.posts, d.grupos
      FROM vagas v JOIN disp d ON d.codigo = ANY (v.codigos)
     WHERE v.categoria IS NULL
       AND d.quando >= date_trunc('minute', v.criado_em) - interval '1 minute'
       AND (d.quando AT TIME ZONE 'America/Manaus')::time >= v.horario - interval '1 minute'
       AND (d.quando AT TIME ZONE 'America/Manaus')::time <  v.horario + interval '90 minutes'
       AND (v.tipo_recorrencia = 'diaria'
            OR (v.tipo_recorrencia = 'semanal' AND extract(dow FROM d.quando AT TIME ZONE 'America/Manaus')::int = ANY (v.dias_semana))
            OR (v.tipo_recorrencia = 'unica' AND (d.quando AT TIME ZONE 'America/Manaus')::date = v.data_unica))
  ), vl AS MATERIALIZED (        -- a lista disparada é de qual mensagem da grade?
    SELECT v.id AS vaga_id, l.id AS lista_id, l.quando, l.grupos
      FROM vagas v JOIN listas l ON l.categoria = v.categoria AND l.negocio = v.negocio AND l.destino = v.destino
     WHERE v.categoria IS NOT NULL
       AND (l.quando AT TIME ZONE 'America/Manaus')::time >= v.horario - interval '1 minute'
       AND (l.quando AT TIME ZONE 'America/Manaus')::time <  v.horario + interval '30 minutes'
  ), por_vaga AS (
    SELECT v.id, v.horario, v.tipo_recorrencia, v.dias_semana, v.data_unica, v.destino, v.categoria, v.negocio, v.codigos,
           (v.texto_fixo IS NOT NULL) AS texto_fixo,
           -- as vezes: cada dia+horário em que saiu (a vaga de vários imóveis conta uma vez por horário)
           CASE WHEN v.categoria IS NULL
                THEN (SELECT count(DISTINCT (vd.quando AT TIME ZONE 'America/Manaus')::date) FROM vd WHERE vd.vaga_id = v.id)
                ELSE (SELECT count(*) FROM vl WHERE vl.vaga_id = v.id) END AS vezes,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT coalesce(sum(vd.posts), 0) FROM vd WHERE vd.vaga_id = v.id)
                ELSE (SELECT coalesce(sum(cardinality(vl.grupos)), 0) FROM vl WHERE vl.vaga_id = v.id) END AS posts,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT max(vd.quando) FROM vd WHERE vd.vaga_id = v.id)
                ELSE (SELECT max(vl.quando) FROM vl WHERE vl.vaga_id = v.id) END AS ultima,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT count(DISTINCT g.chave) FILTER (WHERE g.marcou) FROM vd JOIN gente g ON g.codigo = vd.codigo AND g.ilha = vd.ilha WHERE vd.vaga_id = v.id)
                ELSE (SELECT count(DISTINCT g.chave) FILTER (WHERE g.marcou) FROM vl JOIN lgente g ON g.id = vl.lista_id WHERE vl.vaga_id = v.id) END AS marcaram,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT count(DISTINCT g.chave) FROM vd JOIN gente g ON g.codigo = vd.codigo AND g.ilha = vd.ilha WHERE vd.vaga_id = v.id)
                ELSE (SELECT count(DISTINCT g.chave) FROM vl JOIN lgente g ON g.id = vl.lista_id WHERE vl.vaga_id = v.id) END AS pessoas
      FROM vagas v
  ), por_imovel AS (
    SELECT d.codigo, count(*) AS vezes, sum(d.posts) AS posts, max(d.quando) AS ultima,
           (SELECT count(DISTINCT g.chave) FILTER (WHERE g.marcou) FROM gente g WHERE g.codigo = d.codigo) AS marcaram,
           (SELECT count(DISTINCT g.chave) FROM gente g WHERE g.codigo = d.codigo) AS pessoas
      FROM disp d GROUP BY d.codigo
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate,
    'total', jsonb_build_object(
      'disparos', (SELECT count(*) FROM disp) + (SELECT count(*) FROM listas),
      'posts', (SELECT coalesce(sum(posts), 0) FROM disp) + (SELECT coalesce(sum(cardinality(grupos)), 0) FROM listas),
      'marcaram', (SELECT count(DISTINCT chave) FROM (SELECT chave FROM gente WHERE marcou UNION SELECT chave FROM lgente WHERE marcou) u),
      'pessoas', (SELECT count(DISTINCT chave) FROM (SELECT chave FROM gente UNION SELECT chave FROM lgente) u)),
    'mensagens', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'vaga', pv.id, 'horario', to_char(pv.horario, 'HH24:MI'), 'recorrencia', pv.tipo_recorrencia,
        'dias', to_jsonb(pv.dias_semana), 'data', pv.data_unica, 'destino', pv.destino,
        'categoria', pv.categoria, 'negocio', pv.negocio, 'texto_fixo', pv.texto_fixo,
        'imoveis', (SELECT jsonb_agg(jsonb_build_object('codigo', c.cod,
                                     'titulo', coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo)) ORDER BY c.n)
                      FROM unnest(pv.codigos) WITH ORDINALITY c(cod, n) LEFT JOIN imoveis i ON i.codigo::text = c.cod),
        'vezes', pv.vezes, 'posts', pv.posts, 'ultima', pv.ultima,
        'marcaram', pv.marcaram, 'perguntaram', pv.pessoas - pv.marcaram, 'pessoas', pv.pessoas))
        ORDER BY pv.pessoas DESC, pv.vezes DESC, pv.horario, pv.id) FROM por_vaga pv), '[]'::jsonb),
    'imoveis', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'codigo', pi.codigo, 'titulo', coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo), 'bairro', i.bairro,
        'vezes', pi.vezes, 'posts', pi.posts, 'ultima', pi.ultima,
        'marcaram', pi.marcaram, 'perguntaram', pi.pessoas - pi.marcaram, 'pessoas', pi.pessoas)
        ORDER BY pi.pessoas DESC, pi.vezes DESC, pi.codigo)
      FROM por_imovel pi LEFT JOIN imoveis i ON i.codigo::text = pi.codigo), '[]'::jsonb),
    'listas_com_id_desde', (SELECT min(enviado_em) FROM envios_lista_grupo)
  ) INTO v;
  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.site_grade_lista_previa(text, text), public.site_grade_metricas(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_grade_opcoes() TO nay_site_escrita, nay_site_leitura;
GRANT EXECUTE ON FUNCTION public.site_grade_agenda(date, date) TO nay_site_escrita, nay_site_leitura;
GRANT EXECUTE ON FUNCTION public.site_grade_lista_previa(text, text) TO nay_site_escrita, nay_site_leitura;
GRANT EXECUTE ON FUNCTION public.site_grade_metricas(date, date) TO nay_site_escrita, nay_site_leitura;
GRANT EXECUTE ON FUNCTION public.site_grade_salvar(jsonb) TO nay_site_escrita;

COMMIT;
