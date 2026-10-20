-- 427 (Pedro, 20/10/2026)
--  1. BUSCAR IMÓVEL OLX igual ao filtro da OLX ("a busca precisa ser mais detalhada, de preferência igual ao filtro da
--     OLX"): a ordem aberta pelo CRM guarda o bloco "olx" do formulário; o nay-olx (busca_olx.parametros_da_olx) põe
--     cada filtro no endereço da OLX com os nomes e códigos da própria OLX.
--  2. VISITANTES ("uma aba lá no CRM VISITANTES: todos os clientes e corretores que já visitaram com a gente, por dia,
--     mês, trimestre e total"): crm_visitantes(de, ate) = as visitas que aconteceram (encerrada/realizada da Parceria e
--     as do cliente da OLX que já passaram), com o corretor e o cliente. A tela agrupa por pessoa e por período.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.crm_olx_busca_parceiro_abrir(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE
  v_tel   text := regexp_replace(coalesce(p->>'telefone', ''), '\D', '', 'g');
  v_nome  text := nullif(btrim(p->>'nome'), '');
  v_lead  bigint;
  v_f     jsonb;
  v_id    bigint;
  v_ab    record;
  v_bai   jsonb;
BEGIN
  IF length(v_tel) IN (12, 13) AND left(v_tel, 2) = '55' THEN v_tel := substr(v_tel, 3); END IF;
  IF length(v_tel) NOT IN (10, 11) THEN
    RETURN jsonb_build_object('erro', 'Telefone do cliente inválido: use DDD + número.');
  END IF;
  IF coalesce(p->>'finalidade', '') NOT IN ('locacao', 'venda') THEN
    RETURN jsonb_build_object('erro', 'Diga se é locação ou venda.');
  END IF;
  IF nullif(p->>'teto', '') IS NULL OR (p->>'teto')::numeric <= 0 THEN
    RETURN jsonb_build_object('erro', 'Diga o valor máximo.');
  END IF;
  SELECT coalesce(jsonb_agg(btrim(b)) FILTER (WHERE btrim(b) <> ''), '[]') INTO v_bai
    FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'bairros') = 'array' THEN p->'bairros' ELSE '[]' END) b;
  IF v_bai = '[]'::jsonb AND coalesce((p->>'qualquer_bairro')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('erro', 'Diga pelo menos um bairro (ou marque qualquer bairro).');
  END IF;
  v_f := jsonb_strip_nulls(jsonb_build_object(
    'finalidade', p->>'finalidade', 'tipo', nullif(btrim(p->>'tipo'), ''), 'teto', (p->>'teto')::numeric,
    'bairros', v_bai, 'qualquer_bairro', CASE WHEN (p->>'qualquer_bairro')::boolean THEN true END,
    'quartos', nullif(p->>'quartos', '')::int, 'aceita_menos_quartos', CASE WHEN (p->>'aceita_menos_quartos')::boolean THEN true END,
    'mobilia', nullif(btrim(p->>'mobilia'), ''), 'aceita_escada', CASE WHEN (p->>'precisa_elevador')::boolean THEN false END,
    'financiamento', nullif(btrim(p->>'financiamento'), ''), 'aceita_parceiro', 'true',
    '_aberta_por', coalesce(nullif(btrim(p_quem), ''), 'CRM'), '_observacao', nullif(btrim(p->>'observacao'), ''),
    -- 427: o filtro igual ao da OLX (tipos, subtipos, faixas, quartos/banheiros/vagas, detalhes, anunciante, ordem)
    'olx', CASE WHEN jsonb_typeof(p->'olx') = 'object' THEN jsonb_strip_nulls(p->'olx') END));

  SELECT id INTO v_lead FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_tel, 8) ORDER BY id DESC LIMIT 1;
  IF v_lead IS NULL THEN
    INSERT INTO privado.olx_lead_whatsapp (telefone, nome, origem, etapa, etapa_em, filtros)
    VALUES (v_tel, v_nome, 'manual', 'feito_busca', now(), v_f - '_aberta_por' - '_observacao')
    RETURNING id INTO v_lead;
  ELSIF v_nome IS NOT NULL THEN
    UPDATE privado.olx_lead_whatsapp SET nome = v_nome, atualizado_em = now() WHERE id = v_lead AND nullif(btrim(nome), '') IS NULL;
  END IF;

  SELECT id, estado INTO v_ab FROM privado.olx_busca_parceiro
   WHERE lead = v_lead AND estado IN ('pendente', 'buscando', 'sem_navegador', 'perguntado', 'aguardando_cadastro') LIMIT 1;
  IF v_ab.id IS NOT NULL THEN
    RETURN jsonb_build_object('erro', 'Esse cliente já tem uma busca aberta (nº ' || v_ab.id || ', ' || v_ab.estado || ').', 'id', v_ab.id);
  END IF;
  INSERT INTO privado.olx_busca_parceiro (lead, filtros, teste) VALUES (v_lead, v_f, false) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'lead', v_lead);
END
$function$;

CREATE OR REPLACE FUNCTION public.crm_visitantes(p_de date DEFAULT NULL, p_ate date DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' SET jit TO 'off' AS $f$
  WITH corr AS MATERIALIZED (SELECT nai_chave(cr.telefone) AS chave, cr.nome, cr.telefone FROM corretores cr),
  v AS (
    SELECT 'parceria'::text AS origem, v.id, v.quando, v.codigo, nai_ref_imovel(v.codigo) AS imovel, v.estado, v.resultado,
           coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(co.nome), ''), nullif(btrim(c.nome_whatsapp), ''), c.telefone) AS corretor,
           coalesce(nullif(regexp_replace(coalesce(co.telefone, c.telefone, ''), '\D', '', 'g'), ''), c.telefone) AS corretor_telefone,
           nullif(btrim(v.visitante_nome), '') AS cliente, NULL::text AS cliente_telefone
      FROM nai_visita v
      LEFT JOIN nai_contato c ON c.id = v.corretor_id
      LEFT JOIN LATERAL (SELECT cr.nome, cr.telefone FROM corr cr WHERE cr.chave = c.chave LIMIT 1) co ON true
     WHERE v.estado IN ('encerrada', 'realizada') AND v.excluida_em IS NULL AND v.quando IS NOT NULL
    UNION ALL
    SELECT 'olx', o.id, o.quando, o.codigo, nai_ref_imovel(o.codigo), o.estado, NULL,
           nullif(btrim(o.corretor_nome), ''), nullif(regexp_replace(coalesce(o.corretor_telefone, ''), '\D', '', 'g'), ''),
           coalesce(nullif(btrim(l.nome), ''), l.telefone), l.telefone
      FROM privado.olx_visita o JOIN privado.olx_lead_whatsapp l ON l.id = o.lead
     WHERE o.quando < now() AND o.estado = 'confirmada'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'origem', v.origem, 'id', v.id, 'quando', v.quando, 'codigo', v.codigo, 'imovel', v.imovel, 'estado', v.estado,
           'resultado', v.resultado, 'corretor', v.corretor, 'corretor_telefone', v.corretor_telefone,
           'cliente', v.cliente, 'cliente_telefone', v.cliente_telefone) ORDER BY v.quando DESC), '[]'::jsonb)
    FROM v
   WHERE (p_de IS NULL OR v.quando >= (p_de::timestamp AT TIME ZONE 'America/Manaus'))
     AND (p_ate IS NULL OR v.quando < ((p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'))
$f$;

REVOKE ALL ON FUNCTION public.crm_visitantes(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_visitantes(date, date) TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.crm_olx_busca_parceiro_abrir(jsonb, text) TO nay_disparo;
COMMIT;
