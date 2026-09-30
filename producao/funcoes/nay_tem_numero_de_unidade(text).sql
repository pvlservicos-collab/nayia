CREATE OR REPLACE FUNCTION public.nay_tem_numero_de_unidade(p_texto text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  t text := lower(unaccent(coalesce(p_texto,'')));
  -- O que cabe entre a palavra e o numero: "ap 401", "ap. n 401",
  -- "apartamento e o 401", "unidade: 51".
  conn constant text := '\.?\s*(n[o°º]?\.?|numero|e|eh|é|:|,)?\s*(o|a)?\s*';
  -- O que vem DEPOIS e que decide se e porta ou descricao: "ap 2 quartos"
  -- e tipo de imovel, nao numero de unidade. Sem esta exclusao o detector
  -- acusava 74 descricoes, quase todas assim.
  medida constant text := '(quarto|quartos|qto|qtos|dorm|suite|suites|ste|vaga|vagas|'
                       || 'banheiro|banheiros|m2|m²|metros|mil|reais|andar|andares|'
                       || 'piso|pisos|carro|carros|d\M|q\M)';
BEGIN
  IF t = '' THEN RETURN false; END IF;

  -- "porta 402" entra: e a forma que o Tel usaria respondendo. Numero
  -- SECO ("401") NAO entra, de proposito -- a resposta dele pode ser
  -- "3500" falando de preco, e bloquear todo numero mataria o reuso de
  -- conhecimento legitimo. A parede que impede a pergunta de virar
  -- pendencia e que carrega o peso; este detector e a segunda linha.
  IF t ~ ('\m(ap|apto|apart|apartamento|unidade|un|porta|casa|sobrado|lote|quadra)\M' || conn || '[0-9]{1,5}[a-z]?\M')
     AND t !~ ('\m(ap|apto|apart|apartamento|unidade|un|porta|casa|sobrado|lote|quadra)\M' || conn
            || '[0-9]{1,5}[a-z]?\s*' || medida)
  THEN
    RETURN true;
  END IF;

  -- "bloco B", "torre 2", "bl 3". O `\M` depois da palavra e essencial:
  -- sem ele, "Av. das Torres 4" casa como "torre" + "s", e vira falso
  -- positivo num nome de avenida de Manaus.
  IF t ~ ('\m(bloco|torre|bl|tr)\M' || conn || '[0-9a-z]{1,2}\M') THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$function$;
