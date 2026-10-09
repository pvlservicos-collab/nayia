CREATE OR REPLACE FUNCTION public.captacao_honorarios_guardar(p_telefone text, p_resposta text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_resposta text := left(nullif(btrim(coalesce(p_resposta, '')), ''), 300);
BEGIN
  IF v_resposta IS NULL THEN
    RETURN 'Nao gravei: passe o que ele respondeu sobre os honorarios (incluso, por fora, ou o que ele disse).';
  END IF;
  INSERT INTO privado.captacao_honorarios (lead_id, telefone, valor, resposta)
  SELECT l.id, p_telefone, captacao_honorarios_valor(p_telefone), v_resposta
    FROM (SELECT 1) x LEFT JOIN captacao_leads l ON l.telefone_chave = nay_fone_chave(p_telefone);
  RETURN 'Anotado. Agradeca em uma linha e encerre a conversa (encerrar_conversa, motivo concluido).';
END
$function$;
