CREATE OR REPLACE FUNCTION public.site_inteligencia_salvar(p jsonb, p_quem text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id bigint := nullif(p->>'id', '')::bigint;
  v_lista text[] := ARRAY['parceria', 'leads', 'captacao', 'olx'];
  v_vale text[] := ARRAY(SELECT x FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'vale_para') = 'array' THEN p->'vale_para' ELSE '[]' END) x WHERE x = ANY (v_lista));
  v_apl text[] := ARRAY(SELECT x FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'aplicada_em') = 'array' THEN p->'aplicada_em' ELSE '[]' END) x WHERE x = ANY (v_lista));
BEGIN
  IF btrim(coalesce(p->>'regra', '')) = '' THEN RAISE EXCEPTION 'a regra está vazia'; END IF;
  IF v_id IS NULL THEN
    INSERT INTO nay_inteligencia_geral (regra, porque, origem, vale_para, aplicada_em, assunto, ativa, criada_por)
    VALUES (btrim(p->>'regra'), nullif(btrim(coalesce(p->>'porque', '')), ''), coalesce(nullif(p->>'origem', ''), 'tel'),
            CASE WHEN cardinality(v_vale) > 0 THEN v_vale ELSE v_lista END, v_apl,
            nullif(btrim(coalesce(p->>'assunto', '')), ''), coalesce((p->>'ativa')::boolean, true), left(p_quem, 80))
    RETURNING id INTO v_id;
  ELSE
    UPDATE nay_inteligencia_geral
       SET regra = btrim(p->>'regra'), porque = nullif(btrim(coalesce(p->>'porque', '')), ''),
           vale_para = CASE WHEN cardinality(v_vale) > 0 THEN v_vale ELSE vale_para END, aplicada_em = v_apl,
           assunto = nullif(btrim(coalesce(p->>'assunto', '')), ''), ativa = coalesce((p->>'ativa')::boolean, ativa),
           mudada_em = now()
     WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'não achei a inteligência %', v_id; END IF;
  END IF;
  RETURN v_id;
END;
$function$;
