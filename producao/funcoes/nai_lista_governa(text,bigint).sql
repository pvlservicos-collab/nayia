CREATE OR REPLACE FUNCTION public.nai_lista_governa(p_chave text, p_contato bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 84 (Tel, 22/09): "garanta que ela so responda esses". Fica FORA da regra
  -- da lista so quem nunca e atendido como corretor: o Tel, quem pode dar
  -- comando, o acompanhante, a equipe e o dono de uma visita EM ANDAMENTO.
  -- Dono de imovel sem visita aberta agora passa pela lista como qualquer
  -- um: com o desvio para o Tel ligado, a Nay nao conversa com dono.
  SELECT NOT (
       p_chave = nai_chave(nai_cfg('tel_telefone'))
    OR nai_pode_comandar(p_chave)
    OR nai_e_motoboy(p_chave)
    OR EXISTS (SELECT 1 FROM equipe e WHERE nai_chave(e.telefone) = p_chave)
    OR (p_contato IS NOT NULL AND EXISTS (
          SELECT 1 FROM nai_visita x
           WHERE x.proprietario_id = p_contato AND nai_visita_aberta(x.estado)))
  );
$function$;
