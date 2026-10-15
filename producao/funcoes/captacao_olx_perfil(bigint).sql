CREATE OR REPLACE FUNCTION public.captacao_olx_perfil(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  o  captacao_olx;
  a  jsonb;
  r  jsonb;
  t  text;
  d  text;
  v_grupo text;
  v_elev  text;
  v_condo text;
BEGIN
  SELECT * INTO o FROM captacao_olx WHERE lead_id = p_lead;
  IF o.lead_id IS NULL THEN RETURN NULL; END IF;
  a := o.anuncio; r := o.respostas;
  t := lower(nay_sem_acento(coalesce(a->>'tipo', '')));
  d := lower(nay_sem_acento(coalesce(a->>'titulo', '') || ' ' || coalesce(a->>'descricao', '')));
  v_condo := a->>'condominio';
  IF v_condo IS NOT NULL AND (v_condo ~* 'n[aã]o identificad' OR lower(nay_sem_acento(v_condo)) ~ '^(casa|predio|apartamento|lote|terreno)( em via publica)?$') THEN
    v_condo := NULL;
  END IF;
  v_grupo := CASE
    WHEN t ~ '^(apartamento|cobertura|flat|kitnet|kitinete|loft|studio)' THEN 'ap'
    WHEN t ~ '^(casa|sobrado)' AND (t ~ 'condominio' OR v_condo IS NOT NULL) AND t !~ 'via publica' THEN 'casa_cond'
    WHEN t ~ '^(casa|sobrado)' THEN 'casa_rua'
    ELSE 'outro' END;
  v_elev := CASE
    WHEN r ? 'elevador' THEN CASE WHEN lower(nay_sem_acento(r->>'elevador')) ~ '(^|\W)(nao|escada|sem elevador)' THEN 'nao' ELSE 'sim' END
    WHEN lower(nay_sem_acento(coalesce(a->>'elevador', ''))) ~ '^sim' THEN 'sim'
    WHEN lower(nay_sem_acento(coalesce(a->>'elevador', ''))) ~ '^nao' THEN 'nao'
    WHEN d ~ '(sem elevador|nao (tem|possui) elevador|de escada)' THEN 'nao'
    WHEN d ~ 'elevador' THEN 'sim'
    ELSE 'desconhecido' END;
  RETURN jsonb_build_object(
    'negocio', coalesce(a->>'negocio', 'venda'), 'grupo', v_grupo, 'elevador', v_elev, 'condominio', v_condo,
    'terreo', (lower(nay_sem_acento(coalesce(a->>'andar', ''))) ~ '^(0|t|terreo)' OR d ~ '\mterreo\M'),
    'valor', CASE WHEN coalesce(a->>'negocio', 'venda') = 'locacao' THEN a->'valor_aluguel' ELSE a->'valor_venda' END);
END $function$;
