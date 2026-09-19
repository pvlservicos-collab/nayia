-- Busca imóvel por bairro e faixa de valor -- a ferramenta que faltava.
--
-- O CASO (Sérgio, 29 e 30/08): ele pediu apartamento no Parque 10 ou perto,
-- até R$ 2.000. A Nay respondeu "vou verificar e retorno" e repetiu isso
-- por um dia inteiro, num domingo, sem nunca voltar. Não foi desleixo do
-- modelo: as duas ferramentas de busca que ela tinha
-- (`resumo_do_condominio` e `listar_no_condominio`) exigem o NOME DO
-- CONDOMÍNIO. Não existia como procurar por bairro e valor. Ela não tinha
-- o que consultar, então prometeu.
--
-- É a mesma família das fotos, da visita e do nome: instrução (ou
-- expectativa) sobre algo que ela não tem como fazer.
--
-- O PISO DE R$ 2.000: a Imob Easy não trabalha com locação abaixo disso.
-- A regra vem colada no resultado, não solta no prompt -- assim ela não
-- tem como "ponderar" e sair procurando mesmo assim.
--
--   docker cp buscar_por_perfil.sql nay-postgres:/tmp/bp.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/bp.sql

CREATE OR REPLACE FUNCTION nay_buscar_por_perfil(
  p_bairro  text,
  p_negocio text,
  p_teto    text,
  p_quartos text,
  p_mobilia text DEFAULT NULL
) RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_bairro  text := btrim(coalesce(p_bairro,''));
  v_neg     text := lower(btrim(coalesce(p_negocio,'')));
  -- `nay_valor_em_reais` e nao regexp cru: "4 mil" virava R$ 4 e a Nay
  -- dizia que o orcamento estava abaixo do piso de locacao. Ver
  -- valor_em_reais.sql.
  v_teto    numeric := nay_valor_em_reais(p_teto);
  v_quartos int := NULLIF(regexp_replace(coalesce(p_quartos,''),'[^0-9]','','g'),'')::int;
  v_locacao boolean := v_neg LIKE 'loc%' OR v_neg LIKE 'alug%';
  -- MOBILIA: o corretor diz "sem mobilia", "so modulados", "mobiliado".
  -- Sem este filtro ela ofereceu ao Enio um mobiliado quando ele pediu sem
  -- (31/08), tendo no banco um cuja descricao diz "sem mobilia". O campo
  -- `mobilia` cobre parte; a `descricao` cobre o resto, e as duas contam.
  v_mob  text := lower(unaccent(btrim(coalesce(p_mobilia,''))));
  v_quer_sem boolean := v_mob ~ '\m(sem|nao|vazio)\M';
  v_quer_com boolean := (NOT (v_mob ~ '\m(sem|nao|vazio)\M'))
                        AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';
  v_lista   text;
  v_n       int;
  v_perto   text;
  v_vizinhos text[];
  v_alt      text;
  v_alt_n    int;
BEGIN
  IF v_bairro = '' THEN
    RETURN QUERY SELECT
      'em qual bairro o cliente procura?'::text,
      'sem bairro nao da para buscar. pergunte antes de chamar de novo.'::text;
    RETURN;
  END IF;

  -- O piso da locação decide antes de qualquer consulta: não adianta
  -- procurar o que a empresa não trabalha.
  IF v_locacao AND v_teto IS NOT NULL AND v_teto < 2000 THEN
    RETURN QUERY SELECT
      ('não temos imóvel para locação nesse perfil, o valor está abaixo do que trabalhamos')::text,
      ('a Imob Easy nao trabalha locacao abaixo de R$ 2.000 e ele pediu ate ' || v_teto ||
       '. NAO prometa procurar depois e NAO diga que vai verificar. ' ||
       'Escale ao Tel como demanda nao atendida, com o bairro e o valor.')::text;
    RETURN;
  END IF;

  -- CONTA TUDO e LISTA 8. Antes o count vinha de dentro do LIMIT, entao
  -- ela dizia "encontrei 8 opcoes" havendo 66 -- e o corretor achava que
  -- tinha visto o catalogo inteiro daquele perfil.
  -- UM corpo só, contado e listado. Duas consultas iguais lado a lado
  -- divergem na primeira edição -- é o padrão 4.3 do HISTORICO. O `bloqueado`
  -- entra aqui: era a única das três buscas que não o excluía.
  WITH achados AS (
    SELECT '• ' || coalesce(NULLIF(i.condominio_nome,''), i.tipo)
           || coalesce(' — ' || i.quartos || ' quartos', '')
           || coalesce(' — ' || replace(to_char(
                CASE WHEN v_locacao THEN i.valor_aluguel ELSE i.valor_venda END,
                'FM999,999,990'),',','.'), '')
           || ' — Código: ' || i.codigo AS x
      FROM imoveis i
     -- Os dois lados normalizados: "taruma" acha "Tarumã" e "pq dez"
     -- acha "Parque 10 de Novembro". Ver bairro_sem_acento.sql.
     WHERE nay_normalizar_lugar(i.bairro, true)
           LIKE '%' || nay_normalizar_lugar(v_bairro, true) || '%'
       AND coalesce(i.disponivel, true)
       AND NOT coalesce(i.bloqueado, false)
       AND NOT coalesce(i.e_parceiro, false)
       AND (CASE WHEN v_locacao THEN coalesce(i.valor_aluguel,0)
                 ELSE coalesce(i.valor_venda,0) END) > 0
       AND (v_teto IS NULL OR
            (CASE WHEN v_locacao THEN i.valor_aluguel ELSE i.valor_venda END) <= v_teto)
       AND (v_quartos IS NULL OR v_quartos = 0 OR i.quartos = v_quartos)
       AND (NOT v_quer_sem OR (
             coalesce(i.mobilia,'') !~* 'mobiliad'
             AND coalesce(i.descricao,'') !~* '\mmobiliad'))
       AND (NOT v_quer_com OR (
             coalesce(i.mobilia,'') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
             OR coalesce(i.descricao,'') ~* '(mobiliad|modulad|planejad)'))
  )
  -- CONTA TUDO e LISTA 8. Antes o count vinha de dentro do LIMIT, então
  -- ela dizia "encontrei 8 opções" havendo 66 -- e o corretor achava que
  -- tinha visto tudo daquele perfil.
  SELECT (SELECT count(*) FROM achados),
         (SELECT string_agg(x, chr(10) ORDER BY x)
            FROM (SELECT x FROM achados ORDER BY x LIMIT 8) p)
    INTO v_n, v_lista;

  IF coalesce(v_n,0) = 0 THEN
    -- Vazio tem TRÊS motivos e a resposta certa é diferente em cada um.
    -- A primeira pergunta é sempre a mesma que a busca fez: o BAIRRO bateu?
    -- Se bateu, o que não serviu foi preço/quartos/mobília, e sugerir outro
    -- nome aqui seria confundir o corretor com um bairro que ele já acertou.
    IF EXISTS (SELECT 1 FROM imoveis i
                WHERE nay_normalizar_lugar(i.bairro, true)
                      LIKE '%' || nay_normalizar_lugar(v_bairro, true) || '%'
                  AND coalesce(i.disponivel, true)) THEN
      -- O QUE TEM PERTO, e só o que é perto de verdade.
      --
      -- O CASO (Waldyrene, 01/09): a cliente queria o Life Parque 10, no
      -- Parque 10 de Novembro, e ela recebeu quatro cards do Acquarelle,
      -- em Ponta Negra -- outro lado da cidade. O Tel: "a ideia é enviar
      -- imóvel nos bairros ao lado somente".
      --
      -- Bairro sem zona cadastrada não oferece NADA de outro bairro: não
      -- ter o dado é motivo para calar, nunca para chutar perto.
      v_vizinhos := nay_bairros_proximos(v_bairro);
      IF coalesce(array_length(v_vizinhos,1),0) > 1 THEN
        WITH perto AS (
          SELECT '• ' || coalesce(NULLIF(i.condominio_nome,''), i.tipo)
                 || ' (' || i.bairro || ')'
                 || coalesce(' — ' || i.quartos || ' quartos', '')
                 || coalesce(' — ' || replace(to_char(
                      CASE WHEN v_locacao THEN i.valor_aluguel ELSE i.valor_venda END,
                      'FM999,999,990'),',','.'), '')
                 || ' — Código: ' || i.codigo AS x
            FROM imoveis i
           WHERE i.bairro = ANY (v_vizinhos)
             AND nay_normalizar_lugar(i.bairro, true)
                 <> nay_normalizar_lugar(v_bairro, true)
             AND coalesce(i.disponivel, true)
             AND NOT coalesce(i.bloqueado, false)
             AND NOT coalesce(i.e_parceiro, false)
             AND (CASE WHEN v_locacao THEN coalesce(i.valor_aluguel,0)
                       ELSE coalesce(i.valor_venda,0) END) > 0
             AND (v_teto IS NULL OR
                  (CASE WHEN v_locacao THEN i.valor_aluguel ELSE i.valor_venda END) <= v_teto)
             AND (v_quartos IS NULL OR v_quartos = 0 OR i.quartos = v_quartos)
        )
        SELECT (SELECT count(*) FROM perto),
               (SELECT string_agg(x, chr(10) ORDER BY x)
                  FROM (SELECT x FROM perto ORDER BY x LIMIT 5) q)
          INTO v_alt_n, v_alt;
      END IF;

      IF coalesce(v_alt_n,0) > 0 THEN
        RETURN QUERY SELECT
          ('em ' || v_bairro || ' não tenho nada nesse perfil agora. aqui perto eu tenho:'
           || chr(10) || v_alt)::text,
          ('nao ha nada no bairro pedido. Esses sao de bairros VIZINHOS -- diga isso ' ||
           'com todas as letras, o bairro de cada um ja vem na lista, e NAO ofereca ' ||
           'nada de outra regiao da cidade. Se ele nao quiser, pergunte ate que valor, ' ||
           'quantos quartos e quais bairros o cliente aceita, e ESCALE ao Tel como ' ||
           'demanda nao atendida com essas tres coisas. NAO diga que vai verificar.')::text;
        RETURN;
      END IF;

      RETURN QUERY SELECT
        ('em ' || v_bairro || ' não temos imóvel nesse perfil no momento, nem nos bairros ' ||
         'aqui perto. me diz até que valor o cliente vai, quantos quartos precisa e ' ||
         'quais bairros ele aceita, que eu vejo o que dá para fazer')::text,
        ('o bairro ' || v_bairro || ' EXISTE no catalogo, mas nada bate com negocio, ' ||
         'quartos, mobilia e valor pedidos, e nos bairros vizinhos tambem nao. ' ||
         'Diga o texto_pronto -- as TRES perguntas (valor, quartos, bairros) fazem ' ||
         'parte dele -- e ESCALE ao Tel como demanda nao atendida, com bairro, ' ||
         'negocio, quartos e valor. NAO ofereca imovel de outra regiao da cidade e ' ||
         'NAO diga que vai verificar e retornar: voce ja verificou agora.')::text;
      RETURN;
    END IF;

    -- O bairro não bateu de jeito nenhum: ou ele escreveu diferente, ou o
    -- bairro não é nosso.
    v_perto := nay_bairro_parecido(v_bairro);

    IF v_perto IS NULL THEN
      -- Nem parecido existe: não é demanda não atendida, é bairro fora da
      -- nossa área. Escalar isso enche o Tel de recado sem assunto.
      RETURN QUERY SELECT
        ('não trabalhamos com imóvel em ' || v_bairro || ' no momento. quais outros ' ||
         'bairros o cliente aceita? me diz também até que valor ele vai e quantos ' ||
         'quartos precisa, que eu procuro')::text,
        ('nao existe NENHUM imovel em ' || v_bairro || ' no catalogo, nem parecido. ' ||
         'Isso e area fora da nossa atuacao, NAO e demanda nao atendida: nao escale. ' ||
         'As TRES perguntas (bairros, valor, quartos) fazem parte do texto_pronto -- ' ||
         'e assim que ele responder, chame buscar_por_perfil de novo. NAO ofereca ' ||
         'imovel de outra regiao por conta propria e NAO diga que vai verificar.')::text;
      RETURN;
    END IF;

    -- Escreveu diferente do cadastro (erro de digitação, nome popular).
    -- Confirmar antes de dizer que não tem: dizer "não temos" de um bairro
    -- que temos é o bug que este arquivo veio consertar.
    RETURN QUERY SELECT
      ('você quis dizer ' || v_perto || '?')::text,
      ('nao achei ' || v_bairro || ' exatamente, mas temos imovel em "' || v_perto ||
       '". Pergunte se e esse mesmo e chame buscar_por_perfil de novo com ' ||
       'esse nome. NAO diga que nao temos e NAO escale ainda.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('encontrei ' || v_n || CASE WHEN v_n > 1 THEN ' opções' ELSE ' opção' END ||
     ' em ' || v_bairro ||
     CASE WHEN v_n > 8 THEN ' (mostrando 8)' ELSE '' END ||
     ':' || chr(10) || v_lista)::text,
    ('repita o texto_pronto como veio. Se ele quiser detalhe de um, chame ' ||
     'imovel_por_codigo com o codigo. Nao invente imovel que nao esta nesta lista.')::text;
END;
$fn$;
