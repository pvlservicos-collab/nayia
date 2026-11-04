CREATE OR REPLACE FUNCTION public.campanha_modelo(p_codigos integer[], p_voc text)
 RETURNS TABLE(modelo text, valores text[], texto text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- situacao_condominio_1: "Olá, {{1}}! ... a situação do seu imóvel no {{2}}, cadastrado conosco. ..."
  -- situacao_imovel_cadastrado_5: "Olá, {{1}}. O seu imóvel {{2}} está cadastrado na Imob Easy e ..."
  WITH c AS (SELECT p_codigos[1] AS codigo, campanha_condominio(p_codigos[1]) AS condo, campanha_no_bairro(p_codigos[1]) AS bairro,
                    coalesce(p_voc, 'tudo bem') AS voc),
  v AS (SELECT *, CASE WHEN condo IS NOT NULL THEN condo || ' (cód. ' || codigo || ')'
                       ELSE '(cód. ' || codigo || ')' || CASE WHEN bairro <> '' THEN ', ' || bairro || ',' ELSE '' END END AS dois
          FROM c)
  SELECT CASE WHEN condo IS NOT NULL THEN 'situacao_condominio_1' ELSE 'situacao_imovel_cadastrado_5' END,
         ARRAY[voc, dois],
         CASE WHEN condo IS NOT NULL
              THEN 'Olá, ' || voc || '! Este é o novo número da Imob Easy. Precisamos atualizar a situação do seu imóvel no ' || dois
                   || ', cadastrado conosco. Por favor, selecione a opção que corresponde à situação atual: [Disponível | Alugado | Vendido]'
              ELSE 'Olá, ' || voc || '. O seu imóvel ' || dois || ' está cadastrado na Imob Easy e precisamos atualizar a situação dele. '
                   || 'Este é o nosso novo número de atendimento. Selecione a situação atual: [Disponível | Alugado | Vendido]' END
    FROM v
$function$;
