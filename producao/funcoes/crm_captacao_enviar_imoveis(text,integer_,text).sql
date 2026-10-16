CREATE OR REPLACE FUNCTION public.crm_captacao_enviar_imoveis(p_telefone text, p_codigos integer[], p_quem text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_cods integer[] := ARRAY(SELECT c FROM unnest(coalesce(p_codigos, '{}')) WITH ORDINALITY u(c, n) WHERE c > 0
                             GROUP BY c ORDER BY min(n));          -- sem repetir, na ordem que a pessoa escolheu
  id_    bigint;
BEGIN
  IF length(v_fone) < 10 THEN RAISE EXCEPTION 'telefone inválido'; END IF;
  IF cardinality(v_cods) = 0 THEN RAISE EXCEPTION 'escolha ao menos um imóvel'; END IF;
  IF cardinality(v_cods) > 10 THEN RAISE EXCEPTION 'no máximo 10 imóveis por vez'; END IF;
  IF EXISTS (SELECT 1 FROM privado.captacao_envio_pedido WHERE right(telefone, 8) = right(v_fone, 8)
                AND estado IN ('pendente', 'enviando')) THEN
    RAISE EXCEPTION 'já tem um envio para este contato saindo: espere terminar';
  END IF;
  INSERT INTO privado.captacao_envio_pedido (telefone, codigos, pedido_por)
  VALUES (v_fone, v_cods, left(coalesce(p_quem, ''), 80)) RETURNING id INTO id_;
  RETURN id_;
END
$function$;
