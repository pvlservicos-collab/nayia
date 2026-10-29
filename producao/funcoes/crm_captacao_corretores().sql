CREATE OR REPLACE FUNCTION public.crm_captacao_corretores()
 RETURNS TABLE(fone8 text, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH donos AS (SELECT DISTINCT right(regexp_replace(telefone, '\D', '', 'g'), 8) AS f8 FROM crm_captacao_donos()),
  sinais AS (
    -- ele mesmo disse que é corretor (a apresentação da imobiliária dele, o CRECI com número)
    SELECT right(regexp_replace(m.telefone, '\D', '', 'g'), 8) AS f8, 'disse que é corretor' AS motivo
      FROM captacao_mensagens m
     WHERE m.direcao = 'recebida'
       AND m.texto ~* '(sou (um |uma )?corretora?\M|corretora? de im[oó]veis[^.]{0,30}creci|creci[^0-9]{0,4}[0-9]{3,}|seja (muito )?bem[- ]vindo.{0,40}imobili)'
       AND m.texto !~* '(tb|tamb[eé]m) sou corretor'
    UNION ALL
    SELECT right(regexp_replace(c.telefone, '\D', '', 'g'), 8), 'corretor no nome'
      FROM corretores c WHERE c.nome ~* '(corretor|corretora|creci|im[oó]veis|imobili)'
    UNION ALL
    SELECT right(regexp_replace(v.corretor_telefone, '\D', '', 'g'), 8), 'acompanha visitas da Nay Leads'
      FROM privado.olx_visita v WHERE coalesce(v.corretor_telefone, '') <> ''
    UNION ALL
    SELECT right(regexp_replace(l.telefone, '\D', '', 'g'), 8), 'marcado como corretor na Nay Leads'
      FROM privado.olx_lead_whatsapp l WHERE l.parada_motivo ~* '(corretor|corretora|creci)'
    UNION ALL
    SELECT right(regexp_replace(k.telefone, '\D', '', 'g'), 8), 'da equipe'
      FROM nai_contato k WHERE nai_e_da_equipe_contato(k.id)
  )
  SELECT s.f8, string_agg(DISTINCT s.motivo, ', ')
    FROM sinais s JOIN donos d ON d.f8 = s.f8
   WHERE length(s.f8) = 8
   GROUP BY s.f8
$function$;
