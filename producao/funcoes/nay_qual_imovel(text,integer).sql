CREATE OR REPLACE FUNCTION public.nay_qual_imovel(p_telefone text, p_horas integer DEFAULT 48)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_tel   text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_lista text;
  v_n     int;
  -- CORDIALIDADE (Tel, 16/09): "o Sr." / "a Sra." / "voce", pelo cadastro.
  -- Sem isto a frase saia com "voce" para todo mundo, inclusive para quem ela
  -- trata por Sr. no resto da conversa.
  v_pron  text;
BEGIN
  -- SEM SR. E SRA. (Tel, 28/09/2026): sempre "você".
  SELECT 'você'::text
    INTO v_pron
    FROM nai_contato k
   WHERE k.chave = nai_chave(coalesce(p_telefone, ''));
  v_pron := coalesce(v_pron, 'você');
  SELECT count(*), string_agg(linha, chr(10) ORDER BY quando DESC)
    INTO v_n, v_lista
  FROM (
    SELECT DISTINCT ON (e.codigo)
           '• ' || e.codigo || ' — '
           || coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'imóvel')
           || coalesce(' (' || i.bairro || ')', '') AS linha,
           max(e.enviado_em) AS quando
      FROM envios e
      LEFT JOIN imoveis i ON i.codigo::text = e.codigo
     WHERE e.destino = 'corretor'
       AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = v_tel
       AND e.enviado_em > now() - make_interval(hours => greatest(p_horas,1))
     GROUP BY e.codigo, i.condominio_nome, i.tipo, i.bairro
     ORDER BY e.codigo, max(e.enviado_em) DESC
     LIMIT 6
  ) s;

  IF coalesce(v_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('De qual imóvel ' || v_pron || ' fala? Se tiver o código me manda, '
       || 'ou me diz o bairro que eu procuro aqui.')::text,
      ('voce NAO sabe de qual imovel ele fala e NAO mandou card nenhum para ele '
       || 'nas ultimas ' || p_horas || ' horas. PERGUNTE o codigo. NAO CHUTE, NAO '
       || 'use o ultimo imovel que voces conversaram e NAO use o ultimo imovel '
       || 'postado nos grupos -- sao mais de 3 por dia, e mandar informacao de um '
       || 'imovel como se fosse de outro e o pior erro possivel.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('É de algum destes que te mandei?' || chr(10) || v_lista || chr(10)
     || '• nenhum desses — me diz o bairro ou o código')::text,
    ('sao ' || v_n || ' imoveis que voce mandou para ele. Mostre a lista do '
     || 'texto_pronto e deixe ele escolher -- nao peca o codigo seco, ele teria '
     || 'que ir procurar. A opcao "nenhum desses" tem que aparecer: ele pode '
     || 'estar falando de um card que veio de outro corretor, do grupo ou do '
     || 'site, e menu sem saida so empurra ele a escolher errado. '
     || 'NAO ESCOLHA POR ELE. '
     || 'Devolva o cumprimento dele antes da lista, se ele cumprimentou.')::text;
END;
$function$;
