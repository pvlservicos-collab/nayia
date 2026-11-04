-- 04/11 (Pedro: "pode retirar do Diego os leads de vendas, deixa só locação e proprietários"): o Diego sai da função SDR
-- (que é a mesma da Rayssa) e ganha a função "Locação": as mesmas permissões, com as abas Atendimento (no Leads, só a
-- locação: FUNCAO_DO_SDR.diego.soLocacao) e Proprietários. Visita e Fechamento saem para ele.
BEGIN;
INSERT INTO organization_roles (organization_id, name, version, permissions)
SELECT organization_id, 'Locação', 1,
       jsonb_set(permissions, '{abas}', '{"atendimento": true, "proprietarios": true, "visita": false, "fechamento": false,
                                         "captacao": false, "administracao": false, "oficial": false}'::jsonb)
  FROM organization_roles WHERE id = '5f741a55-41f3-4ac0-b68f-b87a599ff0a6'
   AND NOT EXISTS (SELECT 1 FROM organization_roles r WHERE r.name = 'Locação');
UPDATE organization_members SET role_id = (SELECT id FROM organization_roles WHERE name = 'Locação'), updated_at = now()
 WHERE id = '5d51205b-c217-45fd-a609-0a88ca7af179';
SELECT p.full_name, r.name, r.permissions->'abas' FROM organization_members m JOIN profiles p ON p.id = m.user_id
  JOIN organization_roles r ON r.id = m.role_id WHERE m.deleted_at IS NULL ORDER BY 1;
COMMIT;
