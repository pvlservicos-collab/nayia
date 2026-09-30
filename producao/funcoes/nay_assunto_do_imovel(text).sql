CREATE OR REPLACE FUNCTION public.nay_assunto_do_imovel(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN lower(unaccent(coalesce(p_texto,''))) ~
         '(quitad|quitacao|financiad|financiamento|escritura|habite|documenta)'
      THEN 'quitacao'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~
         '(entrada|sinal|quanto.{0,15}(pra|para).{0,10}entrar|saldo devedor|gaveta|parcela)'
      THEN 'entrada'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~
         '(cauc|deposito|garantia|fiador|seguro fianca|renda|restric|serasa|spc|analise|antecipad)'
      THEN 'condicoes_locacao'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~ '(pet|animal|cachorro|gato)'
      THEN 'pet'
    -- AR E ARMÁRIO ENTRAM AQUI (22/09). A Maelita perguntou "Tem armários e
    -- ar em todos os cômodos?" duas vezes -- em 31/08 e de novo em 22/09 --
    -- e nenhuma das duas palavras era reconhecida. Na segunda a Nay
    -- respondeu "tem móveis planejados e ar-condicionado" sem ter o dado em
    -- lugar nenhum (o cadastro só diz "semi-mobiliado"), a corretora ia
    -- repassar ao cliente, e o Tel teve que corrigir: o ar está só nos dois
    -- quartos.
    --
    -- Sem estas palavras o conhecimento gravado só era achado pelo caminho
    -- de trás ("outras coisas que sei deste imóvel"), que responde mas não
    -- responde A PERGUNTA.
    WHEN lower(unaccent(coalesce(p_texto,''))) ~
         '(mobili|modulad|planejad|movei|armari|ar[- ]?condicionad|climatiz|split|\mar\M)'
      THEN 'mobilia'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~ '(reforma|estado|conservacao|pintura)'
      THEN 'estado'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~ '(negociad|proposta|reservad|em analise)'
      THEN 'situacao'
    ELSE NULL
  END;
$function$;
