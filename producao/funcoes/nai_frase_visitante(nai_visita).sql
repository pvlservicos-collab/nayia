CREATE OR REPLACE FUNCTION public.nai_frase_visitante(v nai_visita)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT 'O ' || nai_acompanhante() || ', da nossa equipe, acompanha a visita. O visitante é ' || coalesce(v.visitante_nome, 'o cliente do corretor') ||
         coalesce(', CPF ' || nai_cpf_fmt(v.visitante_cpf), '') ||
         coalesce(', com o corretor ' || coalesce(c.nome_completo, nay_nome_de_pessoa(c.nome_whatsapp)), '') || '.'
    FROM nai_contato c WHERE c.id = v.corretor_id;
$function$;
