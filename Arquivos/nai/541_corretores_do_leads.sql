-- 541 (Pedro, 30/10/2026): "você colocou todos os corretores como proprietários ... se o cara tem corretor no nome, ou
-- CRECI, ou imobiliária, é corretor; se ele envia outro imóvel ou fez alguma conversa diferente de nós perguntando uma
-- dúvida e ele respondendo e parando por aí, é corretor". A 526 (crm_captacao_corretores) só olhava quem também era dono
-- de campanha (11 pessoas): o corretor fora da lista de donos caía como proprietário pelo cadastro.
--
-- crm_leads_corretores(): os corretores de quem fala com o 8595 (8 últimos dígitos) e por quê. Só leitura.
--   - o nome (lista de corretores, cliente da Nay Leads, contato do cadastro) tem corretor, CRECI ou imobiliária
--   - ele disse que é corretor / tem CRECI / é de imobiliária
--   - fala do cliente dele; ou ofereceu OUTRO imóvel (tenho outro, parceria, segue as opções) sem ser dono de campanha
--   - é membro dos grupos de corretores, está na lista de corretores, mandou imóvel pelo grupo de cadastro, falou com a
--     Nay Corretores, acompanha visita ou é da equipe
--   - é o contato de imóvel de parceiro (o cadastro salva o corretor parceiro como "proprietário" do imóvel)
--   ("Puxou a conversa" ficou de fora: muitas mensagens nossas pelo 8595 não ficam em captacao_mensagens, e a amostra
--   misturou cliente, dono que respondeu ao disparo e equipe.)
-- O nome no CRM (título do lead) o CRM confere do lado dele (/api/captacao/corretores).
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_leads_corretores()
 RETURNS TABLE(fone8 text, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH msg AS (
    SELECT right(regexp_replace(m.telefone, '\D', '', 'g'), 8) AS f8, m.direcao, m.texto, m.criada_em, m.id
      FROM captacao_mensagens m WHERE m.telefone IS NOT NULL),
  clientes AS (SELECT DISTINCT right(regexp_replace(telefone, '\D', '', 'g'), 8) AS f8 FROM olx_lead_whatsapp),
  -- o dono das campanhas: o disparo foi para ELE (a primeira mensagem guardada pode ser a resposta dele) e a campanha
  -- "outro imóvel" pergunta se ele tem outro ("Tenho outro imóvel" é dono, não corretor)
  donos AS (SELECT DISTINCT right(regexp_replace(telefone, '\D', '', 'g'), 8) AS f8 FROM crm_captacao_donos()),
  sinais AS (
    SELECT f8, 'disse que é corretor' AS motivo FROM msg
     WHERE direcao = 'recebida'
       AND texto ~* '(\mcreci\M|sou (um |uma )?corretora?\M|corretora? de im[oó]veis|\mimobili[aá]ria\M|minha imobili|trabalho com im[oó]veis)'
       AND texto !~* '(tb|tamb[eé]m) sou corretor'
    UNION ALL
    SELECT f8, 'fala do cliente dele' FROM msg
     WHERE direcao = 'recebida' AND texto ~* '(meu cliente|minha cliente|meus clientes)'
    UNION ALL
    -- ofereceu OUTRO imóvel: só quem não é dono de campanha (o dono responde sobre o imóvel dele e sobre "outro imóvel")
    SELECT f8, 'ofereceu imóvel' FROM msg
     WHERE direcao = 'recebida' AND f8 NOT IN (SELECT f8 FROM donos)
       AND texto ~* '(tenho (outr[oa]s?|mais)\M|outros? im[oó]ve|mais (um|uma) (apartamento|casa|op[cç])|\mparceria\M|olha esse|segue (as|os) op[cç])'
       AND texto !~* '\mn[aã]o (tenho|trabalho|fa[cç]o|aceito)'
    UNION ALL
    SELECT right(regexp_replace(c.telefone, '\D', '', 'g'), 8), 'corretor/CRECI/imobiliária no nome'
      FROM corretores c WHERE c.nome ~* '(corretor|creci|imobili|im[oó]veis)'
    UNION ALL
    SELECT right(regexp_replace(l.telefone, '\D', '', 'g'), 8), 'corretor/CRECI/imobiliária no nome'
      FROM olx_lead_whatsapp l WHERE l.nome ~* '(corretor|creci|imobili)'
    UNION ALL
    SELECT right(regexp_replace(w.contato_tel, '\D', '', 'g'), 8), 'corretor/CRECI/imobiliária no nome'
      FROM cadastro_whats w WHERE w.contato_nome ~* '(corretor|creci|imobili)'
    UNION ALL
    SELECT right(regexp_replace(c.telefone, '\D', '', 'g'), 8), 'na lista de corretores' FROM corretores c
    UNION ALL
    SELECT g.telefone8, 'membro dos grupos de corretores' FROM busca_grupo_membro g
    UNION ALL
    SELECT right(regexp_replace(w.contato_tel, '\D', '', 'g'), 8), 'mandou imóvel pelo grupo de cadastro'
      FROM cadastro_whats w WHERE w.papel = 'corretor'
    UNION ALL
    SELECT b.telefone8, 'conversou com a Nay Corretores' FROM busca_corretor b
    UNION ALL
    SELECT right(regexp_replace(v.corretor_telefone, '\D', '', 'g'), 8), 'acompanha visitas'
      FROM olx_visita v WHERE coalesce(v.corretor_telefone, '') <> ''
    UNION ALL
    SELECT right(regexp_replace(l.telefone, '\D', '', 'g'), 8), 'marcado como corretor na Nay Leads'
      FROM olx_lead_whatsapp l WHERE l.parada_motivo ~* '(corretor|corretora|creci)'
    UNION ALL
    SELECT right(regexp_replace(k.telefone, '\D', '', 'g'), 8), 'da equipe'
      FROM nai_contato k WHERE nai_e_da_equipe_contato(k.id)
    UNION ALL
    -- o "proprietário" de imóvel de PARCEIRO é o corretor (o cadastro pelo WhatsApp salva assim o contato do parceiro):
    -- 924 dos 5.728 contatos de proprietarios em 30/10. Só quando TODOS os imóveis dele são de parceiro.
    SELECT right(regexp_replace(p.telefone, '\D', '', 'g'), 8), 'contato de imóvel de parceiro'
      FROM proprietarios p JOIN imoveis i ON i.proprietario_id = p.id
     GROUP BY 1 HAVING bool_and(coalesce(i.e_parceiro, false))
  )
  SELECT s.f8, string_agg(DISTINCT s.motivo, ', ')
    FROM sinais s
   WHERE length(s.f8) = 8
     AND s.f8 IN (SELECT f8 FROM msg)
   GROUP BY s.f8
$function$;

REVOKE ALL ON FUNCTION public.crm_leads_corretores() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_leads_corretores() TO nay_disparo;

COMMIT;
