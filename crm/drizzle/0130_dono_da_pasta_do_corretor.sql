-- 0130 (30/09/2026): A PASTA DO CORRETOR NÃO FUNCIONAVA. A 0128 criou
-- `corretor_documentos` pelo usuário `nay` (superusuário), e o CRM entra no crmdb
-- como `crm`: "permission denied for table corretor_documentos" em toda leitura e
-- gravação. A tabela passa a ser do `crm`, como as outras do CRM.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE corretor_documentos OWNER TO crm;
COMMIT;
