CREATE OR REPLACE FUNCTION public.nay_imovel_do_disparo(p_horas integer DEFAULT 12)
 RETURNS TABLE(texto_pronto text, codigo text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_n    int;
  v_cod  text;
  v_nome text;
BEGIN
  SELECT count(DISTINCT e.codigo), min(e.codigo)
    INTO v_n, v_cod
    FROM envios e
   WHERE e.destino = 'grupo'
     AND e.enviado_em > now() - make_interval(hours => greatest(p_horas, 1));

  IF coalesce(v_n, 0) = 0 THEN
    RETURN QUERY SELECT
      ('De qual imóvel você fala? Se tiver o código me manda, '
       || 'ou me diz o bairro que eu procuro aqui.')::text,
      NULL::text,
      ('nao houve disparo em grupo nas ultimas ' || p_horas || ' horas, entao nao da '
       || 'para saber de qual imovel ele fala. PERGUNTE o codigo. Nao chute. '
       || 'Devolva o cumprimento dele antes, se ele cumprimentou, e troque o '
       || '"voce" da frase pelo tratamento dele.')::text;
    RETURN;
  END IF;

  IF v_n > 1 THEN
    -- Sao ~4 disparos por dia, entao ambiguidade e a REGRA, nao a excecao.
    -- Perguntar "me manda o codigo" obriga o corretor a ir procurar; listar
    -- o que saiu deixa ele responder "o Acquarelle" e seguir.
    SELECT string_agg(linha, chr(10) ORDER BY ultimo DESC) INTO v_nome
      FROM (
        SELECT '• ' || e.codigo || ' — '
               || coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'imóvel') AS linha,
               max(e.enviado_em) AS ultimo
          FROM envios e
          LEFT JOIN imoveis i ON i.codigo::text = e.codigo
         WHERE e.destino = 'grupo'
           AND e.enviado_em > now() - make_interval(hours => greatest(p_horas, 1))
         GROUP BY e.codigo, i.condominio_nome, i.tipo
      ) s;

    RETURN QUERY SELECT
      ('É de algum destes que saiu no grupo?' || chr(10) || coalesce(v_nome,''))::text,
      NULL::text,
      ('foram ' || v_n || ' imoveis nos grupos nesse periodo, entao "esse" e '
       || 'ambiguo. Mostre a lista do texto_pronto e deixe ele escolher -- NAO '
       || 'peca o codigo seco, ele teria que ir procurar. E NAO chute: mandar '
       || 'informacao de um imovel como se fosse de outro e o pior erro possivel. '
       || 'Devolva o cumprimento dele antes da lista, se ele cumprimentou.')::text;
    RETURN;
  END IF;

  SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'o imóvel')
    INTO v_nome FROM imoveis i WHERE i.codigo::text = v_cod;

  RETURN QUERY SELECT
    ''::text,
    v_cod,
    ('ele esta falando do imovel ' || v_cod || ' (' || coalesce(v_nome,'?')
     || '), o unico que foi para os grupos nas ultimas ' || p_horas
     || ' horas. Use imovel_por_codigo com esse codigo para responder. Se a '
     || 'pergunta dele nao for respondida pela consulta, escale ao Tel COM esse '
     || 'codigo, para a resposta virar conhecimento do imovel certo.')::text;
END;
$function$;
