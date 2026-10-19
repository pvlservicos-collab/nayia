SELECT g.id_grupo AS g1 FROM grupos g WHERE g.ativo AND g.apelido IS NULL ORDER BY g.nome LIMIT 1 \gset
SELECT g.id_grupo AS g2 FROM grupos g WHERE g.ativo AND g.apelido IS NULL ORDER BY g.nome OFFSET 1 LIMIT 1 \gset
SELECT i.codigo AS cod FROM imoveis i WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AND NOT coalesce(i.e_parceiro,false) ORDER BY i.codigo DESC LIMIT 1 \gset
SELECT site_grade_salvar(jsonb_build_object('horario','23:59','recorrencia','unica','data',(current_date+30)::text,'codigos',jsonb_build_array(:'cod'),'grupos_ids',jsonb_build_array(:'g1',:'g2'),'destino','easy')) AS r \gset
SELECT :'r' AS salvou;
SELECT grupos_ids, destino FROM vagas WHERE id = (:'r'::jsonb->>'id')::int;
SELECT v->'grupos_ids' gids, v->'previstos' previstos FROM jsonb_array_elements(site_grade_agenda(current_date+30, current_date+30)->'vagas') v WHERE (v->>'id')::int = (:'r'::jsonb->>'id')::int;
SELECT site_grade_salvar(jsonb_build_object('horario','23:59','recorrencia','unica','data',(current_date+30)::text,'codigos',jsonb_build_array(:'cod'),'grupos_ids',jsonb_build_array('nao-existe'))) AS grupo_invalido;
SELECT site_grade_salvar(jsonb_build_object('horario','23:58','recorrencia','unica','data',(current_date+30)::text,'codigos',jsonb_build_array(:'cod'))) AS sem_grupos_continua;
DELETE FROM vagas WHERE horario IN ('23:59','23:58') AND data_unica = current_date+30;
