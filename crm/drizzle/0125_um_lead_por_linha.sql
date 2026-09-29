-- =====================================================================
-- 0125 — UM LEAD POR PESSOA EM CADA LINHA DE WHATSAPP (28/09/2026)
--
-- Tel: "São 3 WhatsApp, cada um em uma tab lá no CRM: API oficial com as
-- coisas que recebemos só da API oficial, a de parceria que já está lá
-- certinho, e o número de captação, que é o outro, em outra instância da
-- Z-API... preciso das 3 lá funcionais, e não misturando contatos".
--
-- O que misturava: o índice era (organização, telefone) -- um lead por
-- pessoa -- e a mensagem que chegava por qualquer número puxava esse lead
-- para a sua linha. A conversa do Tel tinha 279 mensagens da Parceria, 15 da
-- API oficial e 8 da captação no mesmo lead, e pulava de aba a cada uma.
--
-- Aqui:
--   1. o índice vira (organização, telefone, linha) com NULLS NOT DISTINCT:
--      um lead em cada linha, e um só sem linha nenhuma;
--   2. os leads já misturados são separados -- cada mensagem vai para o lead
--      da linha por onde passou. O lead original fica com a linha da PRIMEIRA
--      mensagem dele (etapa, etiquetas e dono continuam nele).
--
-- A linha de cada mensagem (medido em 28/09):
--   metadata.channel gravado                     -> ele mesmo
--   source facebook_cloud / whatsapp_app / templates -> API oficial
--   Z-API sem channel (tudo antes de 28/09 14:54, quando a Z-API era só a
--   Parceria)                                     -> Parceria
--
-- Esperado (prévia de 28/09 ~17:40): 5 leads misturados, 4 leads novos.
--   5511999910621 e Pedro: sem linha -> oficial (só ganham a linha)
--   Tel Sobreira: Parceria + oficial + captação  (2 novos)
--   83846972350484 e Imob Easy: Parceria + captação  (1 novo cada)
-- A primeira prévia (~17:10) dava 3 e 3: o código velho continuava puxando
-- lead de linha enquanto isto esperava. Se o número for outro, nada é gravado
-- (ver as conferências no meio) -- rode a prévia de novo e confira.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- 1) O índice ----------------------------------------------------------
DROP INDEX IF EXISTS leads_org_phone_unique;
CREATE UNIQUE INDEX leads_org_phone_unique
    ON leads (organization_id, phone, integration_id) NULLS NOT DISTINCT
 WHERE deleted_at IS NULL AND phone IS NOT NULL AND phone <> '';

-- 2) A linha de cada mensagem -----------------------------------------
CREATE TEMP TABLE msg_linha ON COMMIT DROP AS
SELECT a.id AS activity_id, a.lead_id, a.created_at, l.organization_id,
       CASE
         WHEN a.metadata->>'channel' IN ('whatsapp_cloud_official', 'whatsapp_zapi', 'whatsapp_zapi_captacao')
           THEN a.metadata->>'channel'
         WHEN a.metadata->>'source' IN ('facebook_cloud', 'whatsapp_app', 'templates')
           THEN 'whatsapp_cloud_official'
         WHEN a.metadata->>'source' = 'zapi' OR a.metadata ? 'zapi_message_id'
           THEN 'whatsapp_zapi'
       END AS tipo
  FROM lead_activities a
  JOIN leads l ON l.id = a.lead_id AND l.deleted_at IS NULL
 WHERE a.type = 'whatsapp';

ALTER TABLE msg_linha ADD COLUMN integracao uuid;
UPDATE msg_linha m
   SET integracao = i.id
  FROM integrations i
 WHERE i.organization_id = m.organization_id AND i.type = m.tipo AND i.deleted_at IS NULL;

-- 3) Quem está misturado: mensagens de mais de uma linha, ou de uma linha
--    que não é a do lead (inclusive o lead sem linha nenhuma).
CREATE TEMP TABLE misturado ON COMMIT DROP AS
SELECT m.lead_id,
       (array_agg(m.integracao ORDER BY m.created_at))[1] AS casa
  FROM msg_linha m
  JOIN leads l ON l.id = m.lead_id
 WHERE m.integracao IS NOT NULL
 GROUP BY m.lead_id, l.integration_id
HAVING count(DISTINCT m.integracao) > 1
    OR bool_or(m.integracao IS DISTINCT FROM l.integration_id);

DO $$
DECLARE n int := (SELECT count(*) FROM misturado);
BEGIN
  RAISE NOTICE 'leads misturados: %', n;
  IF n <> 5 THEN
    RAISE EXCEPTION 'esperava 5 leads misturados e achei % -- nada gravado; confira antes', n;
  END IF;
END $$;

-- 4) O lead original fica na linha da primeira mensagem dele ------------
UPDATE leads l
   SET integration_id = x.casa, updated_at = now()
  FROM misturado x
 WHERE l.id = x.lead_id AND l.integration_id IS DISTINCT FROM x.casa;

-- 5) Um lead novo para cada OUTRA linha, e as mensagens dela vão para ele --
-- (o DISTINCT vem ANTES do id novo: com o gen_random_uuid() dentro dele, cada
-- mensagem virava um par diferente -- 24 leads em vez de 3, e o índice barrou)
CREATE TEMP TABLE separacao ON COMMIT DROP AS
SELECT d.de, d.linha, gen_random_uuid() AS para
  FROM (SELECT DISTINCT m.lead_id AS de, m.integracao AS linha
          FROM msg_linha m
          JOIN misturado x ON x.lead_id = m.lead_id
         WHERE m.integracao IS NOT NULL AND m.integracao <> x.casa) d;

DO $$
DECLARE n int := (SELECT count(*) FROM separacao);
BEGIN
  IF n <> 4 THEN
    RAISE EXCEPTION 'esperava 4 leads novos e sairiam % -- nada gravado', n;
  END IF;
END $$;

INSERT INTO leads (id, organization_id, title, phone, avatar_url, is_group, integration_id,
                   custom_attributes, created_at, updated_at)
SELECT s.para, l.organization_id, l.title, l.phone, l.avatar_url, coalesce(l.is_group, false), s.linha,
       jsonb_build_object('origem', 'conversa_whatsapp', 'separado_de', l.id, 'separado_em', '0125'),
       (SELECT min(m.created_at) FROM msg_linha m WHERE m.lead_id = s.de AND m.integracao = s.linha),
       now()
  FROM separacao s
  JOIN leads l ON l.id = s.de;

UPDATE lead_activities a
   SET lead_id = s.para
  FROM msg_linha m
  JOIN separacao s ON s.de = m.lead_id AND s.linha = m.integracao
 WHERE a.id = m.activity_id;

UPDATE pinned_messages p
   SET lead_id = a.lead_id
  FROM lead_activities a
 WHERE a.id = p.activity_id AND p.lead_id IS DISTINCT FROM a.lead_id;

-- 6) A última mensagem de cada lead envolvido (é o que a lista mostra) ----
UPDATE leads l
   SET last_message_content = u.content,
       last_message_sender_type = CASE WHEN u.dir = 'inbound' THEN 'lead' ELSE 'human' END,
       last_activity_at = u.created_at,
       last_activity_type = 'whatsapp',
       -- a conversa separada é história: não nasce como "não lida"
       is_unread = CASE WHEN l.id IN (SELECT para FROM separacao) THEN false ELSE l.is_unread END
  FROM (
    SELECT DISTINCT ON (a.lead_id) a.lead_id, a.content, a.metadata->>'direction' AS dir, a.created_at
      FROM lead_activities a
     WHERE a.type = 'whatsapp'
       AND a.lead_id IN (SELECT lead_id FROM misturado UNION SELECT para FROM separacao)
     ORDER BY a.lead_id, a.created_at DESC
  ) u
 WHERE l.id = u.lead_id;

-- conferência: nenhum lead com mensagem de outra linha
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
    FROM lead_activities a
    JOIN msg_linha m ON m.activity_id = a.id
    JOIN leads l ON l.id = a.lead_id
   WHERE m.integracao IS NOT NULL AND m.integracao IS DISTINCT FROM l.integration_id;
  IF n > 0 THEN RAISE EXCEPTION 'sobrou % mensagem em lead de outra linha', n; END IF;
END $$;

SELECT l.title, i.type AS linha, count(a.*) AS mensagens
  FROM leads l
  JOIN integrations i ON i.id = l.integration_id
  LEFT JOIN lead_activities a ON a.lead_id = l.id AND a.type = 'whatsapp'
 WHERE l.id IN (SELECT lead_id FROM misturado UNION SELECT para FROM separacao)
 GROUP BY l.title, i.type
 ORDER BY 1, 2;

COMMIT;
