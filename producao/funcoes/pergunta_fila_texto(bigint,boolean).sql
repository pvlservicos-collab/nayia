CREATE OR REPLACE FUNCTION public.pergunta_fila_texto(p_id bigint, p_cobranca boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN p_cobranca THEN '⏰ *Ainda sem resposta — Pergunta ' ELSE '❓ *Pergunta ' END
         || p.k || '/' || p.n || '*' || E'\n'
         || '📱 WhatsApp: ' || pergunta_fila_linha(f.linha) || E'\n'
         || '🔑 Código: ' || coalesce('#' || f.codigo, 'não informado') || E'\n'
         || '🏠 Imóvel: ' || coalesce(nullif(btrim(f.imovel), ''), 'não informado') || E'\n'
         || '👤 Cliente: ' || coalesce(nullif(btrim(f.cliente), '') || ' — ', '') || nai_fone_fmt(f.chave) || E'\n\n'
         || btrim(f.pergunta) || E'\n'
         || coalesce('_(a Nay não achou na ficha: ' || nullif(btrim(f.detalhe), '') || ')_' || E'\n', '') || E'\n'
         || '_Responda aqui que eu mando ao cliente. PULAR deixa para depois; DESCARTAR tira da fila._' || E'\n'
         || '_Quer que eu aprenda para as próximas? ADICIONAR INTELIGÊNCIA: e a regra._'
    FROM pergunta_fila f, pergunta_fila_posicao() p
   WHERE f.id = p_id
$function$;
