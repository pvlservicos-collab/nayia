CREATE OR REPLACE FUNCTION public.nai_pede_imovel_novo(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- "Tem apto proximo ao Distrito ate 1.800?", "procuro casa no Aleixo", "algum apartamento de 2 quartos?". O que fala
  -- da visita, da localização ou do dono continua com a Rayssa ("tem como enviar a localização da casa?").
  SELECT s ~ '\m(tem|teria|tens|algum|alguma|procur\w*|busc\w*|precis\w*|quer\w*|gostaria)\M[^?!\n]{0,40}\m(apto|apt|ap|apartamentos?|casas?|kitnet|kit|kitinete|flat|studio|terrenos?|sobrado|cobertura|imove(l|is)|opc(ao|oes))\M'
     AND s !~ '(localiza|endereco|\mpin\M|onde fica|chave|horario|\mhora\M|visita|proprietari|\mdono|document|contrato|proposta)'
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;
