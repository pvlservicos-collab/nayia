-- 04/11/2026 (Pedro: "lá nas Funções eu quero poder liberar aba por aba para cada SDR; o Lucas é uma função nova chamada
-- Captador"). As abas da v2 por função (permissions.abas, lib/versaoDoCrm.ts AREAS_V2):
--   SDR       Atendimento, Visita, Proprietários, Fechamento (o que o Diego e a Rayssa já viam)
--   Captador  Captação (o Lucas), com as outras permissões iguais às do SDR
BEGIN;
SET ROLE crm;

UPDATE organization_roles
   SET permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object('abas', jsonb_build_object(
         'captacao', false, 'atendimento', true, 'visita', true, 'proprietarios', true, 'fechamento', true,
         'administracao', false, 'oficial', false)),
       updated_at = now()
 WHERE id = '5f741a55-41f3-4ac0-b68f-b87a599ff0a6' AND name = 'SDR';

INSERT INTO organization_roles (organization_id, name, permissions)
SELECT r.organization_id, 'Captador',
       (coalesce(r.permissions, '{}'::jsonb) - 'abas') || jsonb_build_object('abas', jsonb_build_object(
         'captacao', true, 'atendimento', false, 'visita', false, 'proprietarios', false, 'fechamento', false,
         'administracao', false, 'oficial', false))
  FROM organization_roles r
 WHERE r.id = '5f741a55-41f3-4ac0-b68f-b87a599ff0a6'
   AND NOT EXISTS (SELECT 1 FROM organization_roles x WHERE x.organization_id = r.organization_id AND x.name = 'Captador');

UPDATE organization_members m
   SET role_id = (SELECT x.id FROM organization_roles x WHERE x.organization_id = m.organization_id AND x.name = 'Captador'),
       updated_at = now()
 WHERE m.id = 'e65453e7-febe-4071-9895-963477080f55';

SELECT p.full_name, r.name AS funcao, r.permissions->'abas' AS abas
  FROM organization_members m JOIN profiles p ON p.id = m.user_id JOIN organization_roles r ON r.id = m.role_id
 WHERE m.deleted_at IS NULL ORDER BY 1;
COMMIT;
