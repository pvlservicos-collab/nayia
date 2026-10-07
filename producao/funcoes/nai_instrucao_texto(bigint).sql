CREATE OR REPLACE FUNCTION public.nai_instrucao_texto(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 235: a instrução mais recente que ainda vale, para o cabeçalho do turno
  SELECT 'INSTRUÇÃO DA EQUIPE (vale até ' || to_char(i.valido_ate AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')
         || '): ' || i.texto || E'\n'
         || 'Siga esta instrução na resposta: ela diz quem é o cliente, o que ele procura e como atender. '
         || 'Continue usando as ferramentas para todo dado de imóvel.' || E'\n'
    FROM nai_instrucao i
   WHERE i.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))
     AND i.valido_ate > now()
     -- 304: a que o núcleo novo já executou não volta para o agente velho
     AND NOT EXISTS (SELECT 1 FROM core_instrucao_feita f WHERE f.instrucao_id = i.id)
   ORDER BY i.criado_em DESC LIMIT 1;
$function$;
