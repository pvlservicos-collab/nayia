CREATE OR REPLACE FUNCTION public.nai_janela_segundos(p_telefone text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN nai_chave(p_telefone) = ANY (nai_chaves_teste())
                OR EXISTS (SELECT 1 FROM nai_contato c
                             JOIN nai_contato i ON i.id = ANY (nai_contato_irmaos(c.id))
                            WHERE c.chave = nai_chave(p_telefone)
                              AND i.chave = ANY (nai_chaves_teste()))
              THEN nai_cfg_int('janela_segundos_teste', 15)
              ELSE nai_cfg_int('janela_segundos', 20) END;
$function$
;
