-- 451: o papel nay_leitura passa a LER o banco do CRM (crmdb), para os chats de projeto do Agente Claude.
-- Pedro, 20/10/2026: "criei uns terminais do claude na minha vps em /agentes mas eles não estão lendo o banco de dados
-- e os códigos da minha vps"; escolha dele: "Ler tudo, sem mudar". O nay_leitura já entrava no crmdb, mas não lia
-- nenhuma tabela. Só SELECT. Ficam de fora as tabelas de senha e token (api_tokens, integration_secrets, sessions,
-- setup_tokens, push_subscriptions), a senha dos usuários (users.password_hash) e a configuração das integrações
-- (integrations.config, onde mora a chave da Z-API). Tabela nova do CRM NÃO entra sozinha: é preciso um GRANT novo.
-- Rodar no crmdb (psql -d crmdb). Desfazer: REVOKE ALL ON ALL TABLES IN SCHEMA public FROM nay_leitura;
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'p')
      AND c.relname NOT IN ('api_tokens', 'integration_secrets', 'sessions', 'setup_tokens', 'push_subscriptions',
                            'users', 'integrations')
  LOOP
    EXECUTE format('GRANT SELECT ON public.%I TO nay_leitura', t);
  END LOOP;
END $$;

GRANT SELECT (id, email, created_at, updated_at) ON public.users TO nay_leitura;
GRANT SELECT (id, organization_id, name, type, status, created_at, updated_at, deleted_at) ON public.integrations
  TO nay_leitura;

COMMIT;
