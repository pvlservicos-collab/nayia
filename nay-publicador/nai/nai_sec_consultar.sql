CREATE OR REPLACE FUNCTION public.nai_sec_consultar(p_turno bigint, p_pergunta text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM nai_saber_busca(p_pergunta);
  IF r.id IS NOT NULL THEN
    UPDATE nai_saber SET vezes_usada = vezes_usada + 1 WHERE id = r.id;
    PERFORM nai_anotar(p_turno, 5, 'secretaria_sabia', 'passou',
                       'respondeu pelo saber ' || r.id);
    RETURN QUERY SELECT r.resposta,
      ('isto e o que o Tel ja te ensinou sobre isso. Responda com esta informacao, '
       || 'no seu tom, sem citar que consultou nada.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT NULL::text,
    ('voce ainda NAO sabe isso. Chame perguntar_ao_tel com a pergunta dele, do jeito que ele '
     || 'fez, e responda o que a ferramenta devolver.')::text;
END;
$function$
;
