CREATE OR REPLACE FUNCTION public.nay_lembretes_devidos()
 RETURNS TABLE(telefone text, ids bigint[], mensagem text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH devidos AS (
    SELECT l.*,
           coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'o imóvel') AS nome_imovel
      FROM lembrete l
      -- `imoveis.codigo` e INTEGER e `lembrete.codigo` e TEXT (a mesma
      -- inconsistencia de `pendencias`). Sem o ::text explode com
      -- 'operator does not exist: integer = text'.
      LEFT JOIN imoveis i ON i.codigo::text = l.codigo
     WHERE l.estado = 'agendado'
       AND l.disparar_em <= now()
       AND l.codigo IS NOT NULL          -- sem imóvel não cobra: a mensagem
                                          -- ficaria genérica demais
       AND coalesce(i.disponivel, true)   -- imóvel que saiu não se cobra
       AND nay_pode_falar(l.telefone)
  )
  SELECT d.telefone,
         array_agg(d.id ORDER BY d.criado_em),
         CASE WHEN count(*) = 1
              THEN 'sobre o ' || min(d.codigo) || ' (' || min(d.nome_imovel) || '), '
                   || coalesce(min(d.referencia), 'o cliente') || ' já te deu retorno?'
              ELSE 'ficaram ' || count(*) || ' coisas pendentes:' || chr(10)
                   || string_agg('• ' || d.codigo || ' (' || d.nome_imovel || ')'
                                 || coalesce(' — ' || d.referencia, ''),
                                 chr(10) ORDER BY d.criado_em)
                   || chr(10) || 'alguma delas já te deu retorno?'
         END
    FROM devidos d
   GROUP BY d.telefone;
$function$;
