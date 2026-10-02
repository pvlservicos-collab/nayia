-- 271 (02/10/2026): A PÁGINA PÚBLICA DO IMÓVEL E O "ME ENVIA".
--
-- Pedro, 02/10: "criei uma nova tela de ver imóvel (...) quando abro o site sem
-- logar ele deve abrir essa tela"; "ela usa a tecnologia de se enviar imóvel: o
-- corretor vai digitar o WhatsApp lá e nosso sistema vai saber os corretores que
-- mais se enviam imóveis".
--
-- DUAS FUNÇÕES, as duas chamadas pela API do site (imobeasy.online/imovel/...):
--
-- 1. site_imovel_publico(codigo): o que a página mostra, num JSON só. É ABERTA,
--    sem senha, então só leva o que pode aparecer para qualquer pessoa: NÃO sai
--    rua, número, complemento, CEP, andar, torre nem apartamento, e a posição no
--    mapa vai arredondada (~110 m). Só imóvel publicado, disponível e não bloqueado.
--
-- 2. site_me_envia(telefone, codigos, ip): o corretor digita o WhatsApp dele e
--    recebe o card e as fotos. Sai pela MESMA caixa do "Enviar imóvel" do painel
--    (nai_disparo_enfileirar, 145), então valem as paredes de sempre: imóvel de
--    parceiro não sai, indisponível não sai, o mesmo imóvel só 1 vez a cada 24 h
--    por pessoa, e a cadência das fotos.
--
--    A rota é aberta e qualquer um pode digitar qualquer número: por isso os
--    TETOS (por número, por IP e no total do dia). Sem eles, a página viraria um
--    jeito de fazer o nosso número mandar mensagem para desconhecidos.
--
-- Cada pedido fica em privado.me_envia (telefone é dado pessoal: schema privado,
-- fora do /api/tabelas). site_me_envia_ranking() responde "quem mais se envia".
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.me_envia (
  id        bigserial PRIMARY KEY,
  criado_em timestamptz NOT NULL DEFAULT now(),
  chave     text NOT NULL,          -- a mesma de nai_contato.chave
  telefone  text NOT NULL,
  codigos   integer[] NOT NULL,     -- o que ele pediu
  enviados  integer NOT NULL DEFAULT 0,
  ip        text,
  resultado text                    -- o que a caixa respondeu, ou o teto que barrou
);
CREATE INDEX IF NOT EXISTS me_envia_chave ON privado.me_envia (chave, criado_em);
CREATE INDEX IF NOT EXISTS me_envia_ip ON privado.me_envia (ip, criado_em);
CREATE INDEX IF NOT EXISTS me_envia_quando ON privado.me_envia (criado_em);

CREATE OR REPLACE FUNCTION public.site_imovel_publico(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
  WITH i AS (
    SELECT im.*, coalesce(im.extras, '{}'::jsonb) AS x,
           initcap(split_part(coalesce(im.tipo, 'Imóvel'), ' ', 1)) AS tipo_curto
      FROM imoveis im
     WHERE im.codigo = p_codigo AND im.publicado_no_site AND im.disponivel AND NOT coalesce(im.bloqueado, false)
  ), t AS (
    SELECT i.*, coalesce(nullif(btrim(i.tipo), ''), 'Imóvel')
           || CASE WHEN coalesce(i.quartos, 0) > 0 THEN ' ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
           || CASE WHEN nullif(btrim(i.condominio_nome), '') IS NOT NULL THEN ' no ' || btrim(i.condominio_nome)
                   WHEN nullif(btrim(i.bairro), '') IS NOT NULL THEN ' em ' || btrim(i.bairro) ELSE '' END AS titulo
      FROM i
  ), condo AS (
    -- quais características são do CONDOMÍNIO: a lista do cadastro; na falta dela, a da ficha do anúncio
    SELECT coalesce(
             (SELECT array_agg(v) FROM t, jsonb_array_elements_text(
                 CASE WHEN jsonb_typeof(t.x -> 'caracteristicas do condominio') = 'array'
                      THEN t.x -> 'caracteristicas do condominio' ELSE '[]'::jsonb END) v),
             (SELECT f.caracteristicas_condominio FROM imovel_ficha f WHERE f.codigo = p_codigo),
             '{}'::text[]) AS tags
  )
  SELECT jsonb_build_object(
    'codigo', t.codigo,
    'titulo', t.titulo,
    'slug', btrim(regexp_replace(lower(nay_sem_acento(t.titulo)), '[^a-z0-9]+', '-', 'g'), '-'),
    'parceiro', coalesce(t.e_parceiro, false),
    -- imóvel de parceiro não sai pela caixa (parceria nunca sai): a página nem oferece o envio
    'pode_enviar', NOT coalesce(t.e_parceiro, false),
    'local', jsonb_build_object('condominio', nullif(btrim(t.condominio_nome), ''), 'bairro', t.bairro,
                                'cidade', coalesce(t.cidade, 'Manaus'), 'estado', coalesce(t.estado, 'AM')),
    'carac', jsonb_build_object(
      'tipo', t.tipo, 'quartos', t.quartos, 'suites', t.suites, 'banheiros', t.banheiros,
      'salas', t.x ->> 'salas', 'vagas', t.vagas, 'vagascob', t.vagas_cobertas,
      'mobilia', t.mobilia, 'face', t.sol,
      'areautil', t.area_util, 'areatotal', t.area_total, 'areacons', t.x ->> 'area construida',
      'terreno', t.x ->> 'tamanho do terreno', 'frente', t.x ->> 'frente', 'fundo', t.x ->> 'fundo',
      'pedireito', t.x ->> 'pe direito', 'andares', t.x ->> 'andares', 'elevadores', t.x ->> 'elevadores',
      'escadas', t.x ->> 'lances de escada', 'cobertura', t.x ->> 'tipo de cobertura'),
    'tagscondo', to_jsonb((SELECT tags FROM condo)),
    'tagsimovel', to_jsonb(coalesce(
        (SELECT array_agg(c) FROM unnest(coalesce(nullif(t.caracteristicas, '{}'),
                 (SELECT f.caracteristicas_imovel FROM imovel_ficha f WHERE f.codigo = p_codigo), '{}'::text[])) c
          WHERE NOT EXISTS (SELECT 1 FROM condo, unnest(condo.tags) ct WHERE ct = c)), '{}'::text[])),
    'valores', jsonb_build_object('aluguel', t.valor_aluguel, 'venda', t.valor_venda, 'condo', t.taxa_condominio,
                                  'iptu', t.iptu, 'fin', t.x ->> 'aceita financiamento', 'permuta', t.x ->> 'permuta'),
    'incluso', t.x ->> 'incluso no aluguel',
    'garantia', t.x ->> 'garantia de aluguel',
    'desc', t.descricao,
    'fotos', coalesce((SELECT jsonb_agg(f.url ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id)
                         FROM imovel_fotos f
                        WHERE f.codigo = p_codigo AND coalesce(f.url, '') <> '' AND NOT coalesce(f.e_mosaico, false)), '[]'::jsonb),
    -- a posição vai ARREDONDADA (3 casas, ~110 m): a página mostra a região, não a porta
    'geo', (SELECT jsonb_build_object('lat', round(g.lat::numeric, 3), 'lon', round(g.lon::numeric, 3), 'precisao', g.precisao)
              FROM imovel_geo g WHERE g.codigo = p_codigo)
  ) FROM t;
$function$;

CREATE OR REPLACE FUNCTION public.site_me_envia(p_telefone text, p_codigos integer[], p_ip text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
  -- OS TETOS (em imóveis pedidos). Mudar aqui muda para todo mundo.
  TETO_POR_PEDIDO   CONSTANT int := 10;    -- o mesmo do "Enviar imóvel" do painel
  TETO_NUMERO_HORA  CONSTANT int := 20;
  TETO_NUMERO_DIA   CONSTANT int := 60;
  TETO_IP_HORA      CONSTANT int := 40;
  TETO_GERAL_DIA    CONSTANT int := 400;
  v_dig     text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_chave   text;
  v_cod     integer[];
  v_res     text;
  v_teto    text;
  v_enviados int := 0;
  v_msg     text;
BEGIN
  IF length(v_dig) IN (10, 11) THEN v_dig := '55' || v_dig; END IF;
  IF v_dig !~ '^55[1-9][0-9][0-9]{8,9}$' THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Digite seu WhatsApp com DDD.');
  END IF;
  v_chave := nai_chave(v_dig);
  v_cod := ARRAY(SELECT c FROM (SELECT DISTINCT ON (c) c, n FROM unnest(p_codigos) WITH ORDINALITY u(c, n)
                                 WHERE c IS NOT NULL ORDER BY c, n) x ORDER BY n LIMIT TETO_POR_PEDIDO);
  IF v_chave IS NULL OR coalesce(array_length(v_cod, 1), 0) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Escolha pelo menos um imóvel.');
  END IF;

  SELECT CASE
    WHEN (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE chave = v_chave AND criado_em > now() - interval '1 hour') + cardinality(v_cod) > TETO_NUMERO_HORA THEN 'numero_hora'
    WHEN (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE chave = v_chave AND criado_em > now() - interval '24 hours') + cardinality(v_cod) > TETO_NUMERO_DIA THEN 'numero_dia'
    WHEN nullif(p_ip, '') IS NOT NULL AND
         (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE ip = p_ip AND criado_em > now() - interval '1 hour') + cardinality(v_cod) > TETO_IP_HORA THEN 'ip_hora'
    WHEN (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE criado_em > now() - interval '24 hours') + cardinality(v_cod) > TETO_GERAL_DIA THEN 'geral_dia'
  END INTO v_teto;
  IF v_teto IS NOT NULL THEN
    INSERT INTO privado.me_envia (chave, telefone, codigos, enviados, ip, resultado)
    VALUES (v_chave, v_dig, '{}', 0, left(p_ip, 64), 'barrado pelo teto: ' || v_teto || ' (pediu ' || array_to_string(v_cod, ',') || ')');
    RETURN jsonb_build_object('ok', false, 'teto', v_teto,
      'mensagem', 'Você já pediu muitos imóveis agora há pouco. Tente de novo mais tarde.');
  END IF;

  v_res := nai_disparo_enfileirar(v_dig, v_cod, 'site: me envia');
  IF v_res LIKE 'Mandei para%' THEN
    v_enviados := (SELECT count(*) FROM regexp_matches(split_part(v_res, E'\n', 1), '\(card e', 'g'));
  END IF;
  INSERT INTO privado.me_envia (chave, telefone, codigos, enviados, ip, resultado)
  VALUES (v_chave, v_dig, v_cod, v_enviados, left(p_ip, 64), left(v_res, 1000));

  v_msg := CASE
    WHEN v_enviados > 0 AND v_enviados = cardinality(v_cod) THEN 'Pronto! Em instantes chega no seu WhatsApp.'
    WHEN v_enviados > 0 THEN 'Pronto! ' || v_enviados || ' de ' || cardinality(v_cod)
         || ' estão a caminho do seu WhatsApp. Os outros já foram enviados hoje ou não estão mais disponíveis.'
    WHEN v_res ~ 'já foi para esse número' THEN 'Você já recebeu esse imóvel nas últimas 24 horas. Ele está na sua conversa com a gente.'
    WHEN v_res ~ 'indisponível' THEN 'Esse imóvel não está mais disponível.'
    ELSE 'Não foi possível enviar agora. Tente de novo em alguns minutos.' END;
  RETURN jsonb_build_object('ok', v_enviados > 0, 'enviados', v_enviados, 'pedidos', cardinality(v_cod), 'mensagem', v_msg);
END;
$function$;

-- quem mais se envia imóveis (para o painel; telefone é dado pessoal: só com a senha do /admin)
CREATE OR REPLACE FUNCTION public.site_me_envia_ranking(p_dias integer DEFAULT 30)
 RETURNS TABLE(telefone text, nome text, e_corretor boolean, pedidos bigint, imoveis_enviados bigint,
               imoveis_distintos bigint, primeiro timestamptz, ultimo timestamptz)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
  SELECT max(m.telefone),
         coalesce((SELECT c.nome FROM corretores c WHERE nai_chave(c.telefone) = m.chave LIMIT 1),
                  (SELECT coalesce(k.nome_completo, k.nome_whatsapp) FROM nai_contato k WHERE k.chave = m.chave)) AS nome,
         EXISTS (SELECT 1 FROM corretores c WHERE nai_chave(c.telefone) = m.chave) AS e_corretor,
         count(*) AS pedidos, sum(m.enviados)::bigint AS imoveis_enviados,
         (SELECT count(DISTINCT c) FROM privado.me_envia m2, unnest(m2.codigos) c
           WHERE m2.chave = m.chave AND m2.enviados > 0 AND m2.criado_em > now() - make_interval(days => p_dias)) AS imoveis_distintos,
         min(m.criado_em), max(m.criado_em)
    FROM privado.me_envia m
   WHERE m.criado_em > now() - make_interval(days => p_dias)
   GROUP BY m.chave
   ORDER BY sum(m.enviados) DESC, count(*) DESC;
$function$;

REVOKE ALL ON FUNCTION public.site_imovel_publico(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_me_envia(text, integer[], text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_me_envia_ranking(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_imovel_publico(integer) TO nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_me_envia(text, integer[], text) TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_me_envia_ranking(integer) TO nay_site_escrita;

COMMIT;
