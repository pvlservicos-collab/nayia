-- 526: CORRETOR NÃO É "PROP" NO WHATSAPP LEADS (Pedro, 29/10/2026): "tem gente apontada como proprietário lá no WhatsApp
-- Lead que na verdade é corretor, veja lá".
-- A marca "Prop" da lista vem de crm_captacao_donos: todo telefone que a lista da captação tem como contato de um imóvel.
-- Quando o contato cadastrado do imóvel é o corretor que o representa, ele vira "dono": Agnaldo (Idealize Imobiliária,
-- "Sou corretor de imóveis"), Davi Izel (Imobiliária Izel, CRECI 4417), Moacy Aguiar (CRECI 1326), Sarah Souza (CRECI 6892),
-- Thiago Silva ("Corretor de Imóveis" no nome), Raquel Paiva (corretora das visitas) e a corretora de parceria que o
-- Pedro marcou em 16/10. E os números nossos (Tel, o próprio 8595, o de teste do Pedro).
-- Esta função diz quem, desses, é corretor ou da equipe; o CRM tira o "Prop" deles SÓ na linha do WhatsApp Leads (na
-- Oficial a campanha de captação segue igual). Quem diz "também sou corretor" é o dono que também é corretor: fica Prop;
-- "nenhuma corretora de imóveis" (a Andrea, dona) também não conta: só "sou corretor", CRECI com número ou a apresentação
-- da imobiliária dele ("Seja muito bem-vindo(a) à Imobiliária Izel").
-- Não mexe em nay_proprietario_bloqueio (a lista que a Nay respeita).
BEGIN;

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

REVOKE ALL ON FUNCTION public.crm_captacao_corretores() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_captacao_corretores() TO nay_disparo, nay;

COMMIT;
