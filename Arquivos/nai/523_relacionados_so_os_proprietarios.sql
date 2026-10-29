-- 523: EMBAIXO DA CONVERSA, SÓ OS PROPRIETÁRIOS (Pedro, 29/10/2026): "o Diego é nosso motoboy, ele não fica linkado abaixo
-- de uma conversa, e a Raquel é corretora, ela pode ficar lá normal, só fica embaixo da conversa como conversa relacionada
-- os proprietários que nosso sistema foi perguntar, os corretores não precisa".
-- A 517 ligava ao lead todo número a que a Nay Leads mandou mensagem por causa dele: dos 17 de hoje, 12 eram Neila,
-- Katherine, Raquel (corretoras) e Diego (motoboy), chamados para acompanhar a visita. Agora só fica quem é o DONO: do
-- imóvel citado (nai_proprietario_do_imovel), o perguntado numa dúvida (privado.duvida.dono_tel) ou o proprietário de uma
-- visita (privado.olx_visita.proprietario_telefone). O Eden Barreira (2683) está na tabela de corretores e é o dono: fica.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_contatos_relacionados()
 RETURNS TABLE(cliente text, contato text, em timestamp with time zone, motivos text, codigos integer[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH pares AS (
    SELECT right(regexp_replace(l.telefone, '\D', '', 'g'), 8) AS cliente,
           right(regexp_replace(m.telefone, '\D', '', 'g'), 8) AS contato,
           m.criada_em AS em, e.tipo AS motivo, e.codigo
      FROM privado.olx_cliente_enviada e
      JOIN captacao_mensagens m ON m.message_id = e.message_id AND m.direcao = 'enviada'
      JOIN privado.olx_lead_whatsapp l ON l.id = e.lead
     WHERE e.enviado_em > now() - interval '90 days'
    UNION ALL
    SELECT right(regexp_replace(d.cliente_tel, '\D', '', 'g'), 8), right(regexp_replace(d.dono_tel, '\D', '', 'g'), 8),
           coalesce(d.dono_perguntado_em, d.criada_em), 'duvida', d.codigo
      FROM privado.duvida d
     WHERE d.linha = 'captacao' AND d.dono_linha = 'captacao' AND d.dono_tel IS NOT NULL
  ), juntos AS (
    SELECT cliente, contato, max(em) AS em, string_agg(DISTINCT motivo, ',') AS motivos,
           array_remove(array_agg(DISTINCT codigo), NULL) AS codigos
      FROM pares
     WHERE length(contato) = 8 AND contato <> cliente
       -- quem também é cliente da Nay Leads é lead: fica na lista de cima
       AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o WHERE right(regexp_replace(o.telefone, '\D', '', 'g'), 8) = contato)
     GROUP BY cliente, contato
  )
  SELECT j.cliente, j.contato, j.em, j.motivos, j.codigos
    FROM juntos j
   -- 523: só o proprietário (corretor que acompanha a visita e o motoboy ficam na lista normal)
   WHERE EXISTS (SELECT 1 FROM unnest(j.codigos) cod CROSS JOIN LATERAL nai_proprietario_do_imovel(cod) p
                  WHERE right(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g'), 8) = j.contato)
      OR EXISTS (SELECT 1 FROM privado.duvida d WHERE right(regexp_replace(coalesce(d.dono_tel, ''), '\D', '', 'g'), 8) = j.contato)
      OR EXISTS (SELECT 1 FROM privado.olx_visita v
                  WHERE right(regexp_replace(coalesce(v.proprietario_telefone, ''), '\D', '', 'g'), 8) = j.contato)
$function$;

COMMIT;
