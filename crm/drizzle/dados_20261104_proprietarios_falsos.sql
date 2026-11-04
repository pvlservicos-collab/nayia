-- 04/11 (Pedro: "revisar todas as tags do CRM e tirar os proprietários falsos"): os 21 de confiança alta da revisão.
-- O tipo de contato escolhido à mão vence todas as regras de "dono" (usePapelDoContato) e o espelho da etiqueta (funis.ts,
-- mudado no mesmo dia); a etiqueta Proprietários sai deles. O que era fica em proprietario_falso_antes_0411.
BEGIN;
SET ROLE crm;
CREATE TABLE IF NOT EXISTS proprietario_falso_antes_0411 AS
SELECT l.id AS lead_id, l.custom_attributes->>'tipo_contato' AS tipo_antes,
       EXISTS (SELECT 1 FROM lead_tags lt JOIN tags t ON t.id = lt.tag_id
                WHERE lt.lead_id = l.id AND coalesce(t.nome_original, t.name) = 'Proprietários') AS tinha_etiqueta,
       now() AS em
  FROM leads l WHERE false;

WITH novo(id, tipo) AS (VALUES
  ('4a2d1f3b-4902-4b73-85fb-0e4d8448eaa5'::uuid, 'corretor'), ('09bf1033-f737-4d3f-be72-545129967b8a', 'corretor'),
  ('74c0d6bf-306c-4946-8012-34e5bc8de8c8', 'corretor'), ('fe5721e4-028e-4646-a846-4c2bd8bda00f', 'corretor'),
  ('b89fac82-16e8-485f-bc45-280270a0a314', 'corretor'), ('442066c5-b662-457e-8201-cf3e19684251', 'corretor'),
  ('040140e7-0032-4c12-8806-2d963ce24503', 'corretor'), ('6b1bc104-efaa-4606-aad8-13de3d828b21', 'corretor'),
  ('282efd8b-b6e3-4f10-a0cc-df8127bd94f6', 'corretor'), ('4e7fedd6-8990-4240-a879-c4af1ced7151', 'equipe'),
  ('0d048a06-967c-4ad4-bedb-9447e95addf6', 'corretor'), ('71f36e8b-5590-4a78-9a1b-8e851832f910', 'cliente'),
  ('75b113ac-08ff-4499-92d3-2f208c555610', 'cliente'), ('5d770b93-012c-4b10-b47a-c2e87328ff99', 'corretor'),
  ('395eb181-2a6d-4c8d-9cbf-0857629400d6', 'cliente'), ('eb5e1f3c-fa52-4040-960a-65c02b48384c', 'corretor'),
  ('a4a1ff3a-02a0-4b2f-9eb6-bb33ce987bb8', 'equipe'), ('74d8b223-a624-4df8-9e31-94317847fee8', 'corretor'),
  ('17f96c00-ea91-43a2-a1fc-83b296856b94', 'cliente'), ('2fb555f5-6a04-4627-bb53-7ca4f1caf14f', 'corretor'),
  ('6f949a3d-f678-4f3e-9fd4-925fd412f5f2', 'corretor')),
antes AS (
  INSERT INTO proprietario_falso_antes_0411 (lead_id, tipo_antes, tinha_etiqueta, em)
  SELECT l.id, l.custom_attributes->>'tipo_contato',
         EXISTS (SELECT 1 FROM lead_tags lt JOIN tags t ON t.id = lt.tag_id
                  WHERE lt.lead_id = l.id AND coalesce(t.nome_original, t.name) = 'Proprietários'), now()
    FROM leads l JOIN novo n ON n.id = l.id RETURNING 1),
tipo AS (
  UPDATE leads l SET custom_attributes = coalesce(l.custom_attributes, '{}'::jsonb) || jsonb_build_object('tipo_contato', n.tipo),
         updated_at = now()
    FROM novo n WHERE l.id = n.id RETURNING l.id)
DELETE FROM lead_tags lt USING tags t, novo n
 WHERE lt.lead_id = n.id AND t.id = lt.tag_id AND coalesce(t.nome_original, t.name) = 'Proprietários';

SELECT (SELECT count(*) FROM proprietario_falso_antes_0411) guardados,
       (SELECT count(*) FROM leads WHERE id IN (SELECT lead_id FROM proprietario_falso_antes_0411) AND custom_attributes ? 'tipo_contato') com_tipo;
COMMIT;
