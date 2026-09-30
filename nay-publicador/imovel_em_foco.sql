-- De qual imóvel esta conversa está falando, sem depender da memória.
--
-- O CASO (Márcio, 01 e 02/09). Às 18h32 ele mandou "1327". A Nay devolveu
-- o card da Casa em Nova Cidade. Onze horas depois, de manhã: "qual o
-- menor valor, dessa casa no Nova cidade" -- e ela respondeu "me passa o
-- código dessa casa na nova cidade pra eu confirmar". O Tel: *"ela precisa
-- lembrar o contexto da conversa"*.
--
-- POR QUE AUMENTAR A MEMÓRIA NÃO RESOLVERIA. Medido em `nay_memoria`: a
-- conversa dele pula de 18h33 para 19h21. O turno das 18h32 -- justamente
-- o que estabeleceu o imóvel -- **não está lá**, e não é a janela que o
-- cortou. Quando o corretor manda só o número, o fluxo atende pelo caminho
-- do `Achar codigo`, que NÃO passa pelo agente: ninguém escreve em
-- `nay_memoria`. O evento mais informativo da conversa é invisível para
-- ela por construção.
--
-- Então o contexto não pode morar na memória do modelo. Ele mora no dado:
-- `envios` sabe que mandamos o 1327 para ele (linha 194, 18h35), e
-- `mensagens` sabe que ele escreveu 1327. Isso não se perde e não depende
-- de o modelo lembrar.
--
-- A LINHA QUE NÃO PODE SER CRUZADA. O Tel foi explícito em 01/09: *"são
-- disparados mais de 3 imóveis por dia nos grupos, concluir que foi o
-- último disparado é um tiro no pé"*. Esta função **não olha disparo de
-- grupo**: só a conversa 1 a 1 com ESTE corretor. E se nessa conversa
-- houver mais de um imóvel na janela, ela devolve NULL e a lista -- para
-- ela perguntar qual, com as opções na mão, nunca escolher uma.
--
-- A janela mora em `config.imovel_em_foco_horas` (padrão 24) e muda com um
-- UPDATE, sem deploy.
--
--   docker cp imovel_em_foco.sql nay-postgres:/tmp/if.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/if.sql

INSERT INTO config (chave, valor)
VALUES ('imovel_em_foco_horas', '24')
ON CONFLICT (chave) DO NOTHING;

-- Os códigos que apareceram nesta conversa, pelas três fontes que existem.
CREATE OR REPLACE FUNCTION nay_codigos_da_conversa(p_telefone text, p_horas int DEFAULT NULL)
RETURNS text[] LANGUAGE sql STABLE AS $fn$
  WITH janela AS (
    SELECT now() - (coalesce(p_horas,
             (SELECT NULLIF(regexp_replace(valor,'[^0-9]','','g'),'')::int
                FROM config WHERE chave = 'imovel_em_foco_horas'),
             24) || ' hours')::interval AS desde,
           right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'), 8) AS tel
  ), achados AS (
    -- 1. o card que MANDAMOS para ele (inclui o caminho do codigo puro,
    --    que e justamente o que nao passa pelo agente)
    SELECT e.codigo AS cod
      FROM envios e, janela j
     WHERE e.destino = 'corretor'
       AND right(regexp_replace(coalesce(e.telefone,''),'[^0-9]','','g'), 8) = j.tel
       AND e.enviado_em >= j.desde
    UNION
    -- 2. o codigo que apareceu no texto, dos DOIS lados da conversa --
    --    inclusive quando o Tel responde pelo numero da Nay
    SELECT c AS cod
      FROM mensagens m, janela j,
           LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto,'')), ARRAY[]::text[])) c
     WHERE right(regexp_replace(coalesce(m.telefone,''),'[^0-9]','','g'), 8) = j.tel
       AND m.criada_em >= j.desde
    UNION
    -- 3. o texto que saiu por ela, quando nao virou linha em `envios`
    SELECT c AS cod
      FROM mensagem_saida s, janela j,
           LATERAL unnest(coalesce(nay_codigos_citados(coalesce(s.texto,'')), ARRAY[]::text[])) c
     WHERE right(regexp_replace(coalesce(s.telefone,''),'[^0-9]','','g'), 8) = j.tel
       AND s.enviado_em >= j.desde
  )
  -- Só código que é imóvel de verdade: número solto num texto pode ser
  -- qualquer coisa, e a faixa deste catálogo (45 a 5712) é a mesma de um
  -- valor de aluguel.
  SELECT array_agg(DISTINCT i.codigo::text ORDER BY i.codigo::text)
    FROM achados a JOIN imoveis i ON i.codigo::text = a.cod;
$fn$;

-- --------------------------------------------------------------------
-- O imóvel em foco: um só, ou nenhum.
--
-- `texto_pronto` é para ELA falar; `codigo` só vem preenchido quando não
-- há dúvida. Com dúvida, `opcoes` traz a lista e ela pergunta.
CREATE OR REPLACE FUNCTION nay_imovel_em_foco(p_telefone text, p_horas int DEFAULT NULL)
RETURNS TABLE(codigo text, descricao text, opcoes text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_cods text[] := nay_codigos_da_conversa(p_telefone, p_horas);
  v_n    int := coalesce(array_length(v_cods,1),0);
BEGIN
  IF v_n = 0 THEN
    RETURN QUERY SELECT NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  IF v_n = 1 THEN
    RETURN QUERY
    SELECT i.codigo::text,
           (coalesce(NULLIF(i.condominio_nome,''), NULLIF(i.tipo,''), 'o imóvel')
            || coalesce(' em ' || NULLIF(i.bairro,''), '')
            || ', código ' || i.codigo)::text,
           NULL::text
      FROM imoveis i WHERE i.codigo::text = v_cods[1];
    RETURN;
  END IF;

  -- Mais de um imóvel nesta conversa: ela pergunta, com as opções. Isto
  -- é o oposto de supor -- e é a mesma escolha do `nay_qual_imovel`.
  RETURN QUERY
  SELECT NULL::text, NULL::text,
         string_agg('• ' || i.codigo || ' — '
                    || coalesce(NULLIF(i.condominio_nome,''), NULLIF(i.tipo,''), 'imóvel')
                    || coalesce(' em ' || NULLIF(i.bairro,''), ''),
                    chr(10) ORDER BY i.codigo)::text
    FROM imoveis i WHERE i.codigo::text = ANY (v_cods);
END;
$fn$;

-- --------------------------------------------------------------------
-- O aviso pronto para o turno do agente.
--
-- Uma função só, para o `Reservar mensagens` chamar uma vez por mensagem
-- em vez de três.
--
-- A SEGURANÇA NÃO É ELA ACERTAR SOZINHA: é ela DIZER de qual imóvel está
-- falando. Se supuser errado, o corretor corrige na mensagem seguinte --
-- o que não pode é pedir o código de um imóvel que ela acabou de mandar,
-- nem escolher calada entre dois.
CREATE OR REPLACE FUNCTION nay_aviso_do_foco(p_telefone text)
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE f record;
BEGIN
  SELECT * INTO f FROM nay_imovel_em_foco(p_telefone);

  IF f.codigo IS NOT NULL THEN
    RETURN 'CONTEXTO DESTA CONVERSA: o imovel que voces vem tratando e '
        || f.descricao || '. Se ele falar "essa casa", "esse imovel", "esse ai", '
        || '"o do nova cidade" ou qualquer referencia sem numero, e ESSE -- NAO peca '
        || 'o codigo de novo, voce acabou de mandar esse imovel para ele. Ao responder, '
        || 'DIGA qual e -- comece com "sobre a ' || f.descricao || '" -- para ele te '
        || 'corrigir na hora se for outro. ';
  END IF;

  IF f.opcoes IS NOT NULL THEN
    RETURN 'CONTEXTO DESTA CONVERSA: voces falaram de MAIS DE UM imovel. Se ele fizer '
        || 'referencia sem numero, PERGUNTE qual, mostrando esta lista como veio:'
        || chr(10) || f.opcoes || chr(10)
        || 'NAO escolha um por conta propria. ';
  END IF;

  RETURN NULL;
END;
$fn$;
