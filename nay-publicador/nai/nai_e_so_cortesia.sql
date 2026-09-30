CREATE OR REPLACE FUNCTION public.nai_e_so_cortesia(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Mensagem curta que nao abre assunto: agradecimento, confirmacao,
  -- saudacao solta. Se tiver QUALQUER palavra de assunto junto, nao e
  -- cortesia -- "ok, e o 5611?" continua sendo pergunta.
  SELECT length(s) <= 40
     AND s ~ ('^(ok|okay|blz|beleza|certo|isso|sim|nao|show|otimo|perfeito|combinado|'
           || 'obrigad[oa]|obg|vlw|valeu|de nada|imagina|bom dia|boa tarde|boa noite|'
           || 'oi|ola|oii+|opa|eae|e ai|tudo bem|tudo bom|entendi|entendido|ta bom|'
           || 'ta certo|tamo junto|abraco|abs|att|falou|até|ate mais|👍|🙏|👏)[\s!.,;:)]*$')
    FROM (SELECT btrim(lower(unaccent(coalesce(p_texto, '')))) AS s) x;
$function$
;
