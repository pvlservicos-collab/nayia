-- 280 (03/10/2026): A AGENDA DOS GRUPOS MOSTRA A MENSAGEM COMO ELA CHEGA.
--
-- Pedro, 03/10: "divide cada grupo uma cor... e preciso que o conteúdo apareça separado como na conversa do
-- whatsapp normal, e com diferenciação de cor para ficar mais fácil entender".
--
-- A tela (admin › Grupos) agora desenha o post como ele chega em cada grupo: o texto do card e, depois, a
-- foto. Para isso ela precisa das mesmas regras que o publicador usa por grupo (montar_destinos.py e
-- _fotos_para_grupo): quais grupos levam TODAS as fotos em vez da metadinha, o piso de valor (o Alto Padrão
-- não mostra o aluguel abaixo de 6.500) e quais estão "lotados" (fora dos disparos). Só a função de opções
-- muda: os campos novos entram ao lado dos que já existiam.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.site_grade_opcoes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'grupos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', g.id_grupo, 'nome', g.nome, 'apelido', g.apelido,
                                  'ativo', g.ativo, 'venda', g.aceita_venda, 'locacao', g.aceita_locacao,
                                  'so_condominio', g.so_condominio, 'so_comercial', g.so_comercial,
                                  -- 280: o que a tela precisa para mostrar o post como ele chega neste grupo
                                  'todas_fotos', g.todas_fotos, 'venda_minima', g.venda_minima,
                                  'aluguel_minimo', g.aluguel_minimo, 'lotado', coalesce(g.apelido = 'lotado', false))
                                ORDER BY g.nome) FROM grupos g), '[]'::jsonb),
    'destinos', coalesce((SELECT jsonb_agg(jsonb_build_object('apelido', d.apelido, 'grupos', d.nomes) ORDER BY d.apelido)
                            FROM (SELECT g.apelido, array_agg(g.nome ORDER BY g.nome) AS nomes FROM grupos g
                                   WHERE g.ativo AND coalesce(g.apelido, '') NOT IN ('', 'lotado') GROUP BY g.apelido) d), '[]'::jsonb));
$function$;

GRANT EXECUTE ON FUNCTION public.site_grade_opcoes() TO nay_site_escrita, nay_site_leitura;

COMMIT;
