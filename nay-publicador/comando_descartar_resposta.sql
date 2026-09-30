-- O corpo INTEIRO de `nay_comando`, o caminho de TODOS os comandos do Tel.
--
-- REGENERADO A PARTIR DA PRODUÇÃO em 01/09. Não editar de cabeça: gerar
-- de novo com o script abaixo, conferir o diff e commitar junto com a
-- mudança. `rodar_testes.sh --com-banco` compara este arquivo com o
-- `prosrc` vivo e falha na divergência.
--
--   ssh SERVIDOR 'docker exec nay-postgres psql -U nay -d naydb -tAc \
--     "SELECT prosrc FROM pg_proc WHERE proname='"'"'nay_comando'"'"'"'
--
-- POR QUE ESTE ARQUIVO PASSOU A SER GERADO: ele se declarava "o corpo
-- inteiro como está em produção" e trazia o passo de deploy no cabeçalho.
-- Só que a função viva foi editada DEPOIS -- a confirmação do `RESPOSTA`
-- passou a dizer para quem e sobre o quê -- e a edição não voltou para
-- arquivo nenhum. Rodar o arquivo como o próprio cabeçalho mandava, que é
-- o que qualquer um faria no ajuste seguinte, apagaria a correção em
-- silêncio.
--
-- O QUE ELE JÁ CARREGA:
--
-- `DESCARTAR <id>` revoga resposta já gravada (01/09). Antes ele só agia
-- em pendência `aberta`; resposta errada já gravada ficava para sempre --
-- e `pendencias.resposta` é REUSADA para quem perguntar parecido naquele
-- imóvel. Não existia desfazer, e o caso do Gustavo mostrou como é fácil
-- gravar no imóvel errado. Agora a resposta sai e o reuso com ela; a
-- linha NÃO é apagada.
--
-- A CONFIRMAÇÃO DO `RESPOSTA` diz o nome de quem recebeu e o assunto
-- (01/09). O Tel escreveu "resposta 49 ..." querendo a 48. Um dígito. O
-- sistema entregou fielmente, e o Gustavo recebeu uma frase sem sentido,
-- sobre outro imóvel. Dizendo para quem foi, o erro aparece no segundo
-- seguinte.
--
-- `RESPOSTA <id> descartar` VIRA DESCARTAR (01/09). O Tel escreveu
-- "resposta 81 descartar" e o comando entregou a palavra "descartar" ao
-- corretor como se fosse a resposta sobre as vagas de garagem. Ele
-- respondeu "Não anunciar?".
--
--   docker cp comando_descartar_resposta.sql nay-postgres:/tmp/cd.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/cd.sql

CREATE OR REPLACE FUNCTION nay_comando(p_acao text, p_id_txt text, p_texto text)
RETURNS TABLE(avisar text, msg_corretor text, msg_tel text)
LANGUAGE plpgsql AS $nayfn$



DECLARE r record; n int; lista text; p_id int := NULLIF(regexp_replace(coalesce(p_id_txt,''),'[^0-9]','','g'),'')::int;
BEGIN
IF upper(p_acao) = 'RESPOSTA' THEN
  -- "resposta 81 descartar" e um DESCARTAR, nao uma resposta com a
  -- palavra "descartar" dentro. Em 01/09 o Tel escreveu isso e o Valois
  -- recebeu, sobre as vagas de garagem do 5035, a frase "o Condominio
  -- Itapuranga III, descartar" -- e respondeu "Nao anunciar?".
  -- Nenhuma resposta de verdade e SO um verbo de descarte, entao aqui
  -- nao ha ambiguidade a perder.
  IF lower(btrim(coalesce(p_texto,''))) ~ '^(descartar?|descarte|esquec[ea]r?|esque[çc]a|apag[ae]r?|cancel[ae]r?|ignor[ae]r?)$' THEN
    p_acao := 'DESCARTAR';
  END IF;
END IF;
IF upper(p_acao) = 'RESPOSTA' THEN
  SELECT * INTO r FROM nay_responder_pendencia(p_id, p_texto);
  IF r.ok THEN
    RETURN QUERY SELECT regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'), (SELECT CASE WHEN coalesce(x.nome,'') <> '' THEN 'o ' || x.nome || ', ' ELSE '' END FROM (SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo) AS nome FROM imoveis i WHERE i.codigo::text = regexp_replace(coalesce(r.codigo,''),'[^0-9]','','g')) x) || p_texto, 'pendencia ' || p_id || ' respondida. Mandei para ' || coalesce((SELECT coalesce(NULLIF(split_part(btrim(c.nome),' ',1),''), r.avisar) FROM corretores c WHERE right(regexp_replace(c.telefone,'[^0-9]','','g'),8) = right(regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'),8) LIMIT 1), coalesce(r.avisar,'?')) || ' sobre "' || coalesce(r.assunto,'?') || '"' || coalesce(' (imovel ' || r.codigo || ')', '') || '.';
  ELSE
    RETURN QUERY SELECT NULL::text, NULL::text, 'pendencia ' || p_id || ' nao encontrada ou ja respondida.';
  END IF; RETURN;
END IF;
IF upper(p_acao) = 'DESCARTAR' THEN
  UPDATE pendencias SET status='descartada' WHERE id=p_id AND status='aberta';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    -- REVOGA resposta ja gravada. Ate 01/09 isso nao existia: resposta
    -- errada ficava para sempre, e ela e REUSADA para quem perguntar
    -- parecido naquele imovel. A linha nao e apagada -- so a resposta
    -- sai, e com ela o reuso.
    UPDATE pendencias
       SET resposta = NULL, status = 'descartada'
     WHERE id = p_id AND status = 'respondida';
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN QUERY SELECT NULL::text, NULL::text,
      CASE WHEN n>0 THEN 'pendencia ' || p_id || ' esquecida: a resposta antiga nao vai mais ser reusada.'
           ELSE 'pendencia ' || p_id || ' nao encontrada.' END; RETURN;
  END IF;
  RETURN QUERY SELECT NULL::text, NULL::text, 'pendencia ' || p_id || ' descartada.'; RETURN;
END IF;
IF upper(p_acao) = 'DESCARTAR TUDO' THEN
  SELECT count(*) INTO n FROM pendencias WHERE status='aberta';
  RETURN QUERY SELECT NULL::text, NULL::text, CASE WHEN n=0 THEN 'Nenhuma pendencia aberta.' ELSE 'Sao ' || n || ' pendencia(s) aberta(s). Para confirmar envie: DESCARTAR TUDO SIM' END; RETURN;
END IF;
IF upper(p_acao) = 'DESCARTAR TUDO SIM' THEN
  UPDATE pendencias SET status='descartada' WHERE status='aberta';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN QUERY SELECT NULL::text, NULL::text, n || ' pendencia(s) descartada(s).'; RETURN;
END IF;
IF upper(p_acao) = 'PENDENCIAS' THEN
  SELECT string_agg(x, chr(10) ORDER BY ordem) INTO lista FROM (
    SELECT p.criada_em AS ordem,
           p.id || ' - '
           || rpad(left(coalesce(c.nome, m.nome, 'sem nome'), 12), 12)
           || ' - ' || coalesce('imovel ' || p.codigo || ' - ', '')
           || p.o_que_falta
           || ' - ' || CASE
                WHEN now() - p.criada_em >= interval '1 day'
                  THEN floor(extract(epoch FROM now() - p.criada_em)/86400)::int
                       || CASE WHEN floor(extract(epoch FROM now() - p.criada_em)/86400)::int = 1
                               THEN ' dia' ELSE ' dias' END
                ELSE floor(extract(epoch FROM now() - p.criada_em)/3600)::int || 'h'
              END AS x
      FROM pendencias p
      LEFT JOIN corretores c ON c.telefone = p.avisar
      LEFT JOIN LATERAL (
        SELECT nome FROM mensagens
         WHERE telefone = p.avisar AND coalesce(nome,'') <> ''
         ORDER BY id DESC LIMIT 1
      ) m ON true
     WHERE p.status = 'aberta'
  ) s;
  RETURN QUERY SELECT NULL::text, NULL::text, coalesce('Pendencias abertas:' || chr(10) || lista, 'Nenhuma pendencia aberta.'); RETURN;
END IF;
RETURN QUERY SELECT NULL::text, NULL::text, 'comando nao reconhecido.';
END;





$nayfn$;
