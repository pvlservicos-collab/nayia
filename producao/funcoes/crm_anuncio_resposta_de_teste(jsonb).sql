CREATE OR REPLACE FUNCTION public.crm_anuncio_resposta_de_teste(r jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT jsonb_strip_nulls((r - 'acao' - 'mensagem' - 'id_consulta' - 'explicacao')
         || jsonb_build_object('teste', true, 'acao', 'nenhuma', 'seria', r ->> 'acao',
                               'mensagem_exemplo', r ->> 'mensagem',
                               'explicacao', 'Teste de conexão: nada foi gravado e isto NÃO é ordem. Em `seria` está o que eu responderia de verdade.'));
$function$;
