CREATE OR REPLACE FUNCTION public.nai_e_da_equipe_contato(p_contato bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM nai_contato c
     WHERE c.id = ANY (nai_contato_irmaos(p_contato))
       AND (
             c.chave = nai_chave(nai_cfg('tel_telefone'))
          OR c.chave = ANY (nai_chaves_de('so_estes_numeros'))
          OR EXISTS (SELECT 1 FROM nay_e_da_equipe(c.telefone))
          -- 143: quem pode dar comando (a "voz do Tel": o número da Imob Easy)
          OR nai_pode_comandar(c.chave)
       )
  );
$function$
;
