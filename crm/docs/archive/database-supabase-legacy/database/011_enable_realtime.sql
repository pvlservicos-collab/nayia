-- =========================================================
-- 011) ENABLE REALTIME
-- Habilita o Supabase Realtime para tabelas chave do Chat
-- =========================================================

-- Cria a publication do supabase_realtime caso não exista 
-- (normalmente o Supabase Cloud já inicia com ela, mas é seguro garantir)
BEGIN;
  DO $$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
      CREATE PUBLICATION supabase_realtime;
    END IF;
  END
  $$;
COMMIT;

-- Adiciona a tabela leads à publication (para atualizar a lista quando chegar msg)
ALTER PUBLICATION supabase_realtime ADD TABLE public.leads;

-- Adiciona a tabela lead_activities à publication (para mostrar novas mensagens no chat)
ALTER PUBLICATION supabase_realtime ADD TABLE public.lead_activities;
