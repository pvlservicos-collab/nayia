-- Foto do banco, SÓ LEITURA (a sessão roda com default_transaction_read_only).
-- Uma linha de JSON: as funções do schema public (sem as das extensões), o
-- nai_config, os prompts de nai_prompt com versão e -- desde 02/10 -- AS TABELAS
-- (colunas, índices, restrições, gatilhos, permissões por papel, e a definição
-- das views), dos schemas public e privado.
--
-- Por que as tabelas entraram: medido na sessão de 01/10, de cada 10 comandos
-- num pedido da Nay, 5 a 7 eram para DESCOBRIR ("que coluna existe?", "esse papel
-- pode ler essa tabela?") indo ao servidor, e vários voltavam com "column does
-- not exist". Com a foto, isso é um grep local.
SELECT jsonb_build_object(
  'funcoes', (SELECT jsonb_agg(jsonb_build_object(
                 'nome', p.proname,
                 'tipos', oidvectortypes(p.proargtypes),
                 'def', pg_get_functiondef(p.oid)) ORDER BY p.proname, oidvectortypes(p.proargtypes))
                FROM pg_proc p
               WHERE p.pronamespace = 'public'::regnamespace AND p.prokind IN ('f', 'p')
                 AND NOT EXISTS (SELECT 1 FROM pg_depend d
                                  WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')),
  'tabelas', (SELECT jsonb_agg(jsonb_build_object(
                 'schema', n.nspname,
                 'nome', c.relname,
                 'tipo', CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'view materializada' ELSE 'tabela' END,
                 'linhas', greatest(c.reltuples, 0)::bigint,
                 'comentario', obj_description(c.oid, 'pg_class'),
                 'colunas', (SELECT jsonb_agg(jsonb_build_object(
                                'nome', a.attname,
                                'tipo', format_type(a.atttypid, a.atttypmod),
                                'obrigatoria', a.attnotnull,
                                'padrao', pg_get_expr(d.adbin, d.adrelid),
                                'comentario', col_description(c.oid, a.attnum)) ORDER BY a.attnum)
                               FROM pg_attribute a
                               LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                              WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped),
                 'indices', (SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY pg_get_indexdef(i.indexrelid))
                               FROM pg_index i WHERE i.indrelid = c.oid),
                 'restricoes', (SELECT jsonb_agg(k.conname || ': ' || pg_get_constraintdef(k.oid) ORDER BY k.conname)
                                  FROM pg_constraint k WHERE k.conrelid = c.oid),
                 'gatilhos', (SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.tgname)
                                FROM pg_trigger t WHERE t.tgrelid = c.oid AND NOT t.tgisinternal),
                 -- quem pode o quê: na tabela inteira e, à parte, só em algumas colunas
                 -- (é o caso de imoveis e imovel_fotos para o papel do site)
                 'permissoes', (SELECT jsonb_object_agg(g.papel, g.privs)
                                  FROM (SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS papel,
                                               string_agg(x.privilege_type, ', ' ORDER BY x.privilege_type) AS privs
                                          FROM aclexplode(c.relacl) x GROUP BY 1) g),
                 'permissoes_por_coluna', (SELECT jsonb_object_agg(g.papel, g.privs)
                                  FROM (SELECT y.papel, string_agg(y.priv || '(' || y.cols || ')', '; ' ORDER BY y.priv) AS privs
                                          FROM (SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS papel,
                                                       x.privilege_type AS priv,
                                                       string_agg(a.attname, ', ' ORDER BY a.attnum) AS cols
                                                  FROM pg_attribute a, aclexplode(a.attacl) x
                                                 WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
                                                 GROUP BY 1, 2) y
                                         GROUP BY y.papel) g),
                 'definicao', CASE WHEN c.relkind IN ('v', 'm') THEN pg_get_viewdef(c.oid, true) END
               ) ORDER BY n.nspname, c.relname)
                FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname IN ('public', 'privado') AND c.relkind IN ('r', 'p', 'v', 'm')
                 AND NOT EXISTS (SELECT 1 FROM pg_depend d
                                  WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')),
  'config', (SELECT jsonb_agg(jsonb_build_object('chave', chave, 'valor', valor, 'descricao', descricao,
                                                 'atualizado_em', atualizado_em) ORDER BY chave) FROM nai_config),
  'prompts', (SELECT jsonb_agg(jsonb_build_object('papel', papel, 'versao', versao, 'atualizado_em', atualizado_em,
                                                  'atualizado_por', atualizado_por, 'texto', texto) ORDER BY papel)
                FROM nai_prompt));
