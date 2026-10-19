-- 422: CRM › BUSCAR IMÓVEL OLX (Pedro, 19/10/2026: "constrói uma função para buscar esse imóvel fora lá no menu do CRM,
-- Buscar imóvel OLX, vai ter uns campos a preencher com os dados do lead, põe lá e ele segue o mesmo caminho").
--
-- crm_olx_busca_parceiro_abrir(dados, quem): a ordem de busca (416/421) aberta à mão. O cliente é o lead da Nay do
-- WhatsApp com esse telefone; se não houver, nasce um lead 'manual' (sem assumido_em: a Nay não passa a conversar com
-- ele sozinha). Daí é o mesmo caminho: busca na OLX pela nota dos Grupos, pergunta ao anunciante conhecido ("sim" =
-- oferece pelo 8595), ou pré-cadastro + grupo e, quando ficar Disponível, a Nay manda ao cliente.
-- crm_olx_buscas_parceiro(dias): a lista da tela, agora com o código do pré-cadastro e a origem do cliente.
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
    '_aberta_por', coalesce(nullif(btrim(p_quem), ''), 'CRM'), '_observacao', nullif(btrim(p->>'observacao'), '')));

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

CREATE OR REPLACE FUNCTION public.crm_olx_buscas_parceiro(p_dias integer DEFAULT 7)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado', 'pg_temp' AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'estado', b.estado, 'teste', b.teste, 'criado_em', b.criado_em, 'atualizado_em', b.atualizado_em,
           'cliente', coalesce(l.nome, ''), 'cliente_tel', l.telefone, 'origem', l.origem, 'filtros', b.filtros, 'nota', b.nota,
           'titulo', b.escolhido->>'titulo', 'link', b.escolhido->>'url', 'preco', b.escolhido->>'preco_texto',
           'anunciante', b.contato_nome, 'contato', b.contato_tel, 'linha', b.linha, 'resposta', b.resposta_texto,
           'codigo', b.codigo, 'status_do_imovel', (SELECT i.status FROM imoveis i WHERE i.codigo = b.codigo),
           'candidatos', jsonb_array_length(b.candidatos), 'erro', b.erro) ORDER BY b.id DESC), '[]'::jsonb)
    FROM privado.olx_busca_parceiro b JOIN privado.olx_lead_whatsapp l ON l.id = b.lead
   WHERE b.criado_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 90)))
$function$;

REVOKE ALL ON FUNCTION public.crm_olx_busca_parceiro_abrir(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_busca_parceiro_abrir(jsonb, text) TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.crm_olx_buscas_parceiro(integer) TO nay_disparo;
COMMIT;
