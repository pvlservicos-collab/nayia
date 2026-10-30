-- crmdb, 30/10/2026 (Pedro: "ainda tem contatos como o que o Anderson mandou que não estão disponíveis, revisa os
-- últimos contatos mandados e resolve"). Os cartões de contato que chegaram antes do conserto (8be85d9) ficaram só
-- com o nome. A Z-API não devolve mensagem antiga (multi-device) e o banco da Nay não os guardou; o número vem de:
--   1. o n8n (execuções que ainda tinham o vCard): pelo id da mensagem, ou pelo mesmo nome de cartão;
--   2. o CRM: exatamente UMA pessoa com esse nome (título da conversa ou nome de quem escreveu, 120 dias);
--   3. nenhum: o cartão fica com o nome e sem número (a tela pede para mandar de novo).
BEGIN;

CREATE TEMP TABLE do_n8n (mid text, nome text, tel text) ON COMMIT DROP;
INSERT INTO do_n8n VALUES
  ('2ADDB823F83F905D67A4', 'Luciana Baldeon Corretora', '559282238973'),
  ('3AEA7E0709CA19C0452E', 'Advogado Aleksander', '559291030698');

WITH c AS (
  SELECT a.id, a.metadata->>'zapi_message_id' AS mid,
         btrim(replace(a.content, '👤 Contato compartilhado: ', '')) AS nome
    FROM lead_activities a
   WHERE a.content LIKE '👤 Contato compartilhado:%' AND NOT (a.metadata ? 'contato_compartilhado')
), quem AS (
  SELECT lower(btrim(l.title)) AS nome, right(regexp_replace(l.phone, '\D', '', 'g'), 8) AS f8, l.phone
    FROM leads l WHERE l.deleted_at IS NULL AND l.phone ~ '^55' AND NOT coalesce(l.is_group, false)
  UNION
  SELECT lower(btrim(x.metadata->>'sender_name')), right(regexp_replace(l.phone, '\D', '', 'g'), 8), l.phone
    FROM lead_activities x JOIN leads l ON l.id = x.lead_id
   WHERE x.metadata->>'direction' = 'inbound' AND coalesce(x.metadata->>'sender_name', '') <> ''
     AND l.phone ~ '^55' AND NOT coalesce(l.is_group, false) AND x.created_at > now() - interval '120 days'
), pelo_nome AS (
  SELECT c.id, min(q.phone) AS tel
    FROM c JOIN quem q ON q.nome = lower(c.nome)
   GROUP BY c.id HAVING count(DISTINCT q.f8) = 1
), escolha AS (
  SELECT c.id, c.nome,
         coalesce(n1.tel, n2.tel, p.tel) AS tel,
         CASE WHEN n1.tel IS NOT NULL OR n2.tel IS NOT NULL THEN 'n8n' WHEN p.tel IS NOT NULL THEN 'nome' ELSE 'sem_numero' END AS origem
    FROM c
    LEFT JOIN do_n8n n1 ON n1.mid = c.mid
    LEFT JOIN do_n8n n2 ON n2.nome = c.nome AND n1.mid IS NULL
    LEFT JOIN pelo_nome p ON p.id = c.id
), feito AS (
  UPDATE lead_activities a
     SET metadata = a.metadata || jsonb_build_object('contato_compartilhado', jsonb_build_object(
           'nome', e.nome,
           'telefones', CASE WHEN e.tel IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(regexp_replace(e.tel, '\D', '', 'g')) END,
           'origem', e.origem))
    FROM escolha e WHERE e.id = a.id
  RETURNING e.origem
)
SELECT origem, count(*) FROM feito GROUP BY 1 ORDER BY 1;

COMMIT;
