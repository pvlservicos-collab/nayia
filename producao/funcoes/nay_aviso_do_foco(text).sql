CREATE OR REPLACE FUNCTION public.nay_aviso_do_foco(p_telefone text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE f record;
BEGIN
  SELECT * INTO f FROM nay_imovel_em_foco(p_telefone);

  IF f.codigo IS NOT NULL THEN
    RETURN 'CONTEXTO DESTA CONVERSA: o imovel que voces vem tratando e '
        || f.descricao || '. Se ele falar "essa casa", "esse imovel", "esse ai", '
        || '"o do nova cidade" ou qualquer referencia sem numero, e ESSE -- NAO peca '
        || 'o codigo de novo, voce acabou de mandar esse imovel para ele. Ao responder, '
        || 'DIGA qual e -- comece com "sobre a ' || f.descricao || '" -- para ele te '
        || 'corrigir na hora se for outro. ';
  END IF;

  IF f.opcoes IS NOT NULL THEN
    RETURN 'CONTEXTO DESTA CONVERSA: voces falaram de MAIS DE UM imovel. Se ele fizer '
        || 'referencia sem numero, PERGUNTE qual, mostrando esta lista como veio:'
        || chr(10) || f.opcoes || chr(10)
        || 'NAO escolha um por conta propria. ';
  END IF;

  RETURN NULL;
END;
$function$;
