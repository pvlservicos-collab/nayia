-- 540 (Pedro, 30/10/2026): "os parceiros [antigos] retira mesmo, deixa só os novos" (no site imobeasy.online).
-- O parceiro ANTIGO (do site antigo, extras.parceiro_antigo = 'sim', 413) não fica publicado no site. A leitura diária
-- do site antigo (sincronizar_catalogo.py, 09:17) marca publicado_no_site = true em tudo o que está lá -- foi assim
-- que os 562 despublicados em 27/09 (127) voltaram. A regra mora no gatilho, para valer venha a mudança de onde vier.
-- Liberar um: desligar a chave "Parceiro antigo" no editar (parceiro_antigo = 'nao'); aí ele pode ser publicado.
-- Os parceiros NOVOS não mudam (a 539 pôs os de aluguel no site).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.imoveis_parceiro_antigo_fora_do_site()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF coalesce(NEW.e_parceiro, false) AND coalesce(NEW.extras->>'parceiro_antigo', '') = 'sim'
     AND coalesce(NEW.publicado_no_site, false) THEN
    NEW.publicado_no_site := false;
  END IF;
  RETURN NEW;
END;
$function$;

-- depois de imoveis_parceiro_pelo_captador (que liga o e_parceiro): os gatilhos BEFORE rodam em ordem de nome
DROP TRIGGER IF EXISTS imoveis_pz_parceiro_antigo_fora_do_site ON public.imoveis;
CREATE TRIGGER imoveis_pz_parceiro_antigo_fora_do_site BEFORE INSERT OR UPDATE ON public.imoveis
  FOR EACH ROW EXECUTE FUNCTION imoveis_parceiro_antigo_fora_do_site();

-- os que estão no site hoje saem (só o anúncio; a situação, a marca e o resto ficam)
UPDATE imoveis SET publicado_no_site = false
 WHERE coalesce(e_parceiro, false) AND coalesce(extras->>'parceiro_antigo', '') = 'sim' AND publicado_no_site;

COMMIT;
