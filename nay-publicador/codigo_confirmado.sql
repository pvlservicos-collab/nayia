-- O código do imóvel não pode vir da cabeça do modelo.
--
-- O CASO (01/09, 00h21), reconstruído linha por linha em `nay_memoria`:
-- o Gustavo MARCOU no WhatsApp o card do imóvel 4946 e escreveu "Depois
-- me informe se esse Apartamento tá quitado, e o valor de entrada". A
-- Z-API manda o ID da mensagem citada (`referenceMessageId`) mas nunca o
-- TEXTO dela, e nem esse ID era lido até 01/09 -- o código procurava um
-- campo de nome parecido e errado. O agente recebeu só o texto, sem
-- imóvel nenhum. E ele chamou:
--
--   escalar_ao_tel(disse: "Depois me informe se esse Apartamento...",
--                  codigo: "5717",        <-- INVENTADO
--                  assunto: "quitação e entrada")
--
-- O 5717 vinha da memória de conversa (`nay_memoria`, janela de 15
-- mensagens): tinham falado dele antes, e o modelo preencheu o buraco com
-- o que estava à mão. Não chamou `imovel_do_disparo`, não perguntou.
--
-- POR QUE ISSO É PIOR QUE UMA RESPOSTA ERRADA: `nay_escalar` aceitava o
-- código sem conferir. A pendência nasce no imóvel 5717, o Tel responde,
-- e a resposta fica em `pendencias.resposta` amarrada ao 5717 -- e passa
-- a ser REUSADA para todo mundo que perguntar parecido sobre o 5717.
-- Uma alucinação de um segundo vira conhecimento permanente do imóvel
-- errado.
--
-- A PAREDE: o código só vale se o CORRETOR o tiver mencionado, ou se a
-- Nay tiver mandado exatamente UM card para ele na janela. Igual à parede
-- de `nay_responder_conversando`, onde o telefone vem do fluxo e não do
-- modelo: o que o modelo não pode forjar é o que o dado prova.
--
-- E O TEL FOI EXPLÍCITO sobre a alternativa: "são disparados mais de 3
-- imóveis por dia nos grupos, concluir que foi o último disparado é um
-- tiro no pé para vários erros". Então quando não dá para saber, ela
-- PERGUNTA. Não chuta.
--
--   docker cp codigo_confirmado.sql nay-postgres:/tmp/cc.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/cc.sql

-- --------------------------------------------------------------------
-- O corretor mencionou este código, ou recebeu esse card?
--
-- Devolve a razão, não só o booleano: quem chama precisa saber se pode
-- seguir, e o log de depois precisa saber por quê.
CREATE OR REPLACE FUNCTION nay_codigo_confirmado(
  p_telefone text,
  p_codigo   text,
  p_horas    int DEFAULT 48
) RETURNS text                       -- 'dito_por_ele' | 'unico_card' | 'nao'
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_tel  text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_n    int;
  v_um   text;
BEGIN
  IF v_cod IS NULL OR length(v_tel) < 8 THEN
    RETURN 'nao';
  END IF;

  -- PROVA FORTE: ele escreveu o código. `nay_codigos_citados` já tira os
  -- valores ("paga até 4000" não é o imóvel 4000).
  IF EXISTS (
    SELECT 1 FROM mensagens m
     WHERE right(regexp_replace(m.telefone,'[^0-9]','','g'),8) = v_tel
       AND m.criada_em > now() - make_interval(hours => greatest(p_horas,1))
       AND v_cod = ANY(nay_codigos_citados(coalesce(m.texto,'') || ' ' || coalesce(m.citado,'')))
  ) THEN
    RETURN 'dito_por_ele';
  END IF;

  -- PROVA FRACA MAS SUFICIENTE: a Nay mandou UM card só para ele na
  -- janela, e é esse. Com dois ou mais, "esse" é ambíguo e ela pergunta --
  -- é o mesmo critério do `nay_imovel_do_disparo`, mas olhando ESTA
  -- conversa, que é evidência muito melhor que o disparo em grupo.
  SELECT count(DISTINCT e.codigo), min(e.codigo) INTO v_n, v_um
    FROM envios e
   WHERE e.destino = 'corretor'
     AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = v_tel
     AND e.enviado_em > now() - make_interval(hours => greatest(p_horas,1));

  IF coalesce(v_n,0) = 1 AND v_um = v_cod THEN
    RETURN 'unico_card';
  END IF;

  RETURN 'nao';
END;
$fn$;

-- --------------------------------------------------------------------
-- O que ela deve dizer quando não dá para saber de qual imóvel ele fala.
--
-- NÃO pede "me manda o código" seco: o corretor teria que ir procurar.
-- Lista o que ele viu recentemente para ele só apontar. Se não houver
-- nada para listar, aí sim pede o código.
CREATE OR REPLACE FUNCTION nay_qual_imovel(p_telefone text, p_horas int DEFAULT 48)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_tel   text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_lista text;
  v_n     int;
BEGIN
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
      'de qual imóvel você fala? me manda o código'::text,
      ('voce NAO sabe de qual imovel ele fala e NAO mandou card nenhum para ele '
       || 'nas ultimas ' || p_horas || ' horas. PERGUNTE o codigo. NAO CHUTE, NAO '
       || 'use o ultimo imovel que voces conversaram e NAO use o ultimo imovel '
       || 'postado nos grupos -- sao mais de 3 por dia, e mandar informacao de um '
       || 'imovel como se fosse de outro e o pior erro possivel.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('qual desses?' || chr(10) || v_lista || chr(10)
     || '• nenhum desses — me manda o código')::text,
    ('sao ' || v_n || ' imoveis que voce mandou para ele. Mostre a lista do '
     || 'texto_pronto e deixe ele escolher -- nao peca o codigo seco, ele teria '
     || 'que ir procurar. A opcao "nenhum desses" tem que aparecer: ele pode '
     || 'estar falando de um card que veio de outro corretor, do grupo ou do '
     || 'site, e menu sem saida so empurra ele a escolher errado. '
     || 'NAO ESCOLHA POR ELE.')::text;
END;
$fn$;
