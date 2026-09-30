CREATE OR REPLACE FUNCTION public.nai_assuntos_da_mensagem(p_texto text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  t     text := btrim(coalesce(p_texto, ''));
  linha text;
  parte text;
  saida text[] := '{}';
BEGIN
  IF t = '' THEN RETURN '{}'; END IF;

  -- CARD COLADO NAO E LISTA DE PEDIDOS. O card tem uma dezena de linhas
  -- ("Bairro:", "Codigo: 2014", "Locacao: R$ ...") e contar cada uma como um
  -- assunto faria a Nay achar que ele pediu dez coisas de uma vez.
  IF t ~* 'C[oó]digo:\s*[0-9]{3,5}' AND t ~* '(Bairro:|Loca[cç][aã]o:|Venda:|quartos)' THEN
    RETURN '{}';
  END IF;

  -- Cada linha e um assunto; dentro da linha, cada pergunta tambem e.
  -- "Por favor / Esse e casa ?" sao dois: o sim para a pergunta anterior e uma
  -- pergunta nova sobre outro imovel (Tel, 16/09, conversa da Martinha).
  FOREACH linha IN ARRAY regexp_split_to_array(t, '[\r\n]+') LOOP
    linha := btrim(linha);
    CONTINUE WHEN linha = '';
    IF linha ~ '[?]' THEN
      FOREACH parte IN ARRAY regexp_split_to_array(linha, '(?<=[?])') LOOP
        parte := btrim(parte);
        CONTINUE WHEN length(parte) < 2;
        -- "(Se sim, qual e o valor?" e a continuacao da pergunta de cima, nao
        -- um pedido novo: volta para a parte anterior.
        IF parte ~ '^[(]' AND coalesce(array_length(saida, 1), 0) > 0 THEN
          saida[array_length(saida, 1)] := saida[array_length(saida, 1)] || ' ' || parte;
        ELSE
          saida := saida || parte;
        END IF;
      END LOOP;
    ELSIF length(linha) >= 2 THEN
      saida := saida || linha;
    END IF;
  END LOOP;

  -- CUMPRIMENTO NAO E ASSUNTO. "Bom dia" numa linha so somava um pedido que
  -- nao existe -- e cordialidade, e a Nay ja sabe devolver.
  SELECT coalesce(array_agg(x ORDER BY o), '{}') INTO saida
    FROM unnest(saida) WITH ORDINALITY AS u(x, o)
   WHERE NOT nai_so_cumprimentou(x);

  RETURN saida;
END;
$function$;
