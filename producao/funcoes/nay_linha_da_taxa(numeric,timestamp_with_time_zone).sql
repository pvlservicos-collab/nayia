CREATE OR REPLACE FUNCTION public.nay_linha_da_taxa(p_taxa numeric, p_taxa_em timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    -- FALHA FECHADA, e é a regra do projeto inteiro: taxa sem carimbo não sai.
    -- Hoje isso são as 124 taxas do import da planilha -- as mais velhas do
    -- catálogo, e as que ele mandou de fora. Elas voltam a sair sozinhas quando
    -- alguém reescrever o valor (o trigger carimba) ou quando a leitura do
    -- anúncio corrigir a taxa pelo site.
    WHEN coalesce(p_taxa, 0) <= 0 THEN NULL
    WHEN p_taxa_em IS NULL THEN NULL
    WHEN p_taxa_em < now() - make_interval(days => (
           SELECT coalesce(nullif(valor, '')::int, 45)
             FROM config WHERE chave = 'card_taxa_dias')) THEN NULL
    -- O FORMATO É O DELE, do card do 9013: "• taxa de condomínio 1092,10".
    -- Sem "R$" e sem ponto de milhar -- foi como ele escreveu, e a maior taxa
    -- do catálogo é 3.898,50, então o ponto de milhar quase nunca apareceria.
    -- Os centavos saem sempre: taxa é cobrança com centavos, e "592" ao lado de
    -- "1092,10" no mesmo grupo pareceria dado de qualidade diferente.
    ELSE '• taxa de condomínio '
         || replace(trim(to_char(p_taxa, 'FM999990.00')), '.', ',')
  END;
$function$;
