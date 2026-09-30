CREATE OR REPLACE FUNCTION public.nai_parar_chat(p_contato bigint, p_motivo text)
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE nai_contato SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
                         humano_motivo = coalesce(humano_motivo, left(p_motivo, 200))
   WHERE id = p_contato
     -- Excecao (Tel, 13/09: "poe a ia para voltar a me responder mesmo que escale
     -- para o tel, mas so para o meu numero"): nai_config.escala_sem_parar.
     AND NOT (chave = ANY (SELECT nai_chave(btrim(x)) FROM unnest(string_to_array(nai_cfg('escala_sem_parar', ''), ',')) x
                            WHERE btrim(x) <> ''));
$function$
;
