CREATE OR REPLACE FUNCTION public.imoveis_parceiro_pelo_captador()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_manual text := lower(coalesce(NEW.extras, '{}'::jsonb)->>'parceiro_manual');
BEGIN
  -- 400: quem marcou à mão no admin (Situação > Parceiros) manda, nos dois sentidos
  IF v_manual = 'nao' THEN
    NEW.e_parceiro := false;
    RETURN NEW;
  END IF;
  -- `administrado` e parceiro ao mesmo tempo viola chk_parceiro_nao_administrado:
  -- nesse caso nao mexe (e o humano quem resolve).
  IF NOT coalesce(NEW.administrado, false)
     AND (v_manual = 'sim'
          OR nai_captador_e_parceiro(NEW.captado_por)
          OR nai_captador_e_parceiro(coalesce(NEW.extras, '{}'::jsonb)->>'captado por')
          -- 560: no site antigo o parceiro pode estar só no "indicado por" ("Imob corretor parceiro", o 5180)
          OR coalesce(NEW.extras, '{}'::jsonb)->>'indicado por' ~* 'parceir') THEN
    NEW.e_parceiro := true;
  END IF;
  RETURN NEW;
END;
$function$;
