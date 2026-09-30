-- nay_comando: a resposta ao corretor passa a citar o CONDOMÍNIO, não o código.
--
-- O CASO (31/08): o Tel respondeu a pendência 22 e o corretor recebeu
-- "Sobre o imovel 5611: ele está igual nas fotos MOACY". Ele apontou que
-- o certo seria "o acquarelle, ele está igual nas fotos" -- corretor não
-- pensa em código, pensa em condomínio, e a conversa era recente sobre
-- aquele imóvel de qualquer forma.
--
-- Se não houver nome de condomínio, cai para o tipo. Se não houver nada,
-- vai sem prefixo -- nunca volta a mostrar o código cru.
--
--   docker cp resposta_com_nome_do_condominio.sql nay-postgres:/tmp/nc.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/nc.sql

CREATE OR REPLACE FUNCTION public.nay_comando(p_acao text, p_id_txt text, p_texto text)
 RETURNS TABLE(avisar text, msg_corretor text, msg_tel text)
 LANGUAGE plpgsql
AS $function$
DECLARE r record; n int; lista text; p_id int := NULLIF(regexp_replace(coalesce(p_id_txt,''),'[^0-9]','','g'),'')::int;
BEGIN
IF upper(p_acao) = 'RESPOSTA' THEN
  SELECT * INTO r FROM nay_responder_pendencia(p_id, p_texto);
  IF r.ok THEN
    RETURN QUERY SELECT regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'), (SELECT CASE WHEN coalesce(x.nome,'') <> '' THEN 'o ' || x.nome || ', ' ELSE '' END FROM (SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo) AS nome FROM imoveis i WHERE i.codigo::text = regexp_replace(coalesce(r.codigo,''),'[^0-9]','','g')) x) || p_texto, 'pendencia ' || p_id || ' respondida, avisei o corretor.';
  ELSE
    RETURN QUERY SELECT NULL::text, NULL::text, 'pendencia ' || p_id || ' nao encontrada ou ja respondida.';
  END IF; RETURN;
END IF;
IF upper(p_acao) = 'DESCARTAR' THEN
  UPDATE pendencias SET status='descartada' WHERE id=p_id AND status='aberta';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN QUERY SELECT NULL::text, NULL::text, CASE WHEN n>0 THEN 'pendencia ' || p_id || ' descartada.' ELSE 'pendencia ' || p_id || ' nao estava aberta.' END; RETURN;
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
$function$

