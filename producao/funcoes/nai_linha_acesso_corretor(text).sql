CREATE OR REPLACE FUNCTION public.nai_linha_acesso_corretor(p_acesso text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_acesso
    -- Chave conosco: o corretor nao precisa saber do arranjo (Tel, 12/09).
    WHEN 'chave_conosco' THEN '🔑 A chave fica por nossa conta, deixa que eu providencio.'
    WHEN 'buscar_chave' THEN '🔑 O ' || nai_acompanhante() || ' pega a chave antes e abre pra vocês.'
    WHEN 'fechadura' THEN '🔐 O imóvel tem fechadura eletrônica, o ' || nai_acompanhante() || ' abre pra vocês.'
    WHEN 'proprietario_acompanha' THEN '🙋 O proprietário vai estar lá pra abrir. Chega no horário certinho, tá?'
    ELSE '' END;
$function$;
