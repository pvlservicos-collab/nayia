-- Foto do banco, SÓ LEITURA (a sessão roda com default_transaction_read_only).
-- Uma linha de JSON: as funções do schema public (sem as das extensões), o
-- nai_config e os prompts de nai_prompt com versão.
SELECT jsonb_build_object(
  'funcoes', (SELECT jsonb_agg(jsonb_build_object(
                 'nome', p.proname,
                 'tipos', oidvectortypes(p.proargtypes),
                 'def', pg_get_functiondef(p.oid)) ORDER BY p.proname, oidvectortypes(p.proargtypes))
                FROM pg_proc p
               WHERE p.pronamespace = 'public'::regnamespace AND p.prokind IN ('f', 'p')
                 AND NOT EXISTS (SELECT 1 FROM pg_depend d
                                  WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')),
  'config', (SELECT jsonb_agg(jsonb_build_object('chave', chave, 'valor', valor, 'descricao', descricao,
                                                 'atualizado_em', atualizado_em) ORDER BY chave) FROM nai_config),
  'prompts', (SELECT jsonb_agg(jsonb_build_object('papel', papel, 'versao', versao, 'atualizado_em', atualizado_em,
                                                  'atualizado_por', atualizado_por, 'texto', texto) ORDER BY papel)
                FROM nai_prompt));
