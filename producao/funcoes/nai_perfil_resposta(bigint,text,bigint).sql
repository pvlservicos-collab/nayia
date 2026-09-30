CREATE OR REPLACE FUNCTION public.nai_perfil_resposta(p_contato bigint, p_texto text, p_turno bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE p nai_perfil_cliente; v_ultima text; s text := lower(unaccent(coalesce(p_texto, ''))); v bool;
BEGIN
  SELECT * INTO p FROM nai_perfil_ativo(p_contato);
  IF p.id IS NULL OR p.pendente IS NULL OR p.pendente_em < now() - interval '6 hours' THEN RETURN; END IF;
  -- só vale se a ÚLTIMA fala dela foi a pergunta do perfil
  SELECT s2.texto INTO v_ultima FROM nai_saida s2
   WHERE s2.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato])) AND s2.tipo = 'texto'
     AND s2.estado IN ('enviado', 'enviando', 'simulado')
   ORDER BY s2.criado_em DESC LIMIT 1;
  IF coalesce(v_ultima, '') !~* 'só serve imóvel com elevador' THEN RETURN; END IF;
  v := CASE
    WHEN s ~ '(nao precisa|tanto faz|pode ser sem|sem problema|qualquer|indiferente|nao importa|nao faz diferenca|nao e obrigat)' THEN false
    WHEN s ~ '(\msim\M|s[oó] (com|serve)|precisa|tem que ter|obrigat|somente|necessari|com elevador|\misso\M)' THEN true
    WHEN s ~ '^\s*(nao|n)\M' THEN false
    ELSE NULL END;
  IF v IS NULL THEN RETURN; END IF;
  UPDATE nai_perfil_cliente SET exige = exige || jsonb_build_object('elevador', v), pendente = NULL, pendente_em = NULL,
                                atualizado_em = now()
   WHERE id = p.id;
  PERFORM nai_anotar(p_turno, 1, 'perfil_do_cliente', 'mudou', 'elevador: ' || CASE WHEN v THEN 'só com elevador' ELSE 'pode ser sem' END);
EXCEPTION WHEN OTHERS THEN
  RETURN;
END $function$;
