CREATE OR REPLACE FUNCTION public.nai_cadastro_modelo(p_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- O to_char do Postgres usa o separador da LOCALE, que aqui sai
  -- 3,650.00 -- jeito americano. O translate troca no fim: ponto vira
  -- virgula e virgula vira ponto.
  SELECT '📍 ' || coalesce(n.condominio, n.bairro, 'Imóvel')
    || E'\n* Bairro: '                  || coalesce(n.bairro, '?')
    || E'\n* Tamanho: '                 || coalesce(n.area::text || 'm2', '?')
    || E'\n* Cômodos: '                 || coalesce(n.quartos::text || ' quartos', '?')
         || coalesce(' sendo ' || n.suites::text || ' suíte', '')
    || E'\n* Banheiros: '               || coalesce(n.banheiros::text || ' banheiros', '?')
    || E'\n* Vagas de estacionamento: ' || coalesce(n.vagas::text || ' vaga', '?')
    || E'\n* Mobilia: '                 || coalesce(n.mobilia, '?')
    || E'\nPreço de '                   || CASE lower(coalesce(n.finalidade, ''))
                                              WHEN 'locacao' THEN 'Locação'
                                              WHEN 'venda'   THEN 'Venda'
                                              ELSE 'Venda ou aluguel' END
         || ': ' || coalesce('R$ ' || translate(to_char(n.valor, 'FM999G999G999D00'),
                                                ',.', '.,'), '?')
  FROM nai_imovel_novo n WHERE n.id = p_id;
$function$
;
