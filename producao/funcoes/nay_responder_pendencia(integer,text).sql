CREATE OR REPLACE FUNCTION public.nay_responder_pendencia(p_id integer, p_resposta text)
 RETURNS TABLE(ok boolean, avisar text, codigo text, assunto text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  r record;
  v_texto text;
  v_outros int;
  v_esperando int := 0;
  v_ass text;
BEGIN
  UPDATE pendencias p
     SET resposta = p_resposta, status = 'respondida', respondida_em = now()
   WHERE p.id = p_id AND p.status = 'aberta'
  RETURNING p.avisar, p.codigo, p.o_que_falta, p.de_quem INTO r;

  IF r IS NULL THEN
    RETURN QUERY SELECT false, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  UPDATE escalacoes e SET status = 'resolvida', resolvida_em = now()
   WHERE e.status = 'aberta' AND e.telefone = r.avisar AND e.assunto = r.o_que_falta;

  -- ---------------------------------------------------------------
  -- O QUE ELE ACABOU DE ENSINAR FICA SABIDO, por assunto.
  --
  -- Só com código: resposta sem imóvel não é reusável, e a regra de 31/08
  -- (código nulo era curinga e casava com qualquer imóvel) vale aqui
  -- igual. E nunca com número de unidade dentro -- é a mesma parede do
  -- leque logo abaixo, pelo mesmo motivo: gravado, seria reusado para
  -- sempre naquele imóvel.
  IF r.codigo IS NOT NULL AND NOT nay_tem_numero_de_unidade(p_resposta) THEN
    v_ass := coalesce(nay_assunto_do_imovel(r.o_que_falta),
                      nay_assunto_do_imovel(p_resposta));
    IF v_ass IS NOT NULL THEN
      PERFORM nay_gravar_conhecimento(r.codigo, v_ass, btrim(p_resposta),
                                      'tel (RESPOSTA ' || p_id || ')');
    END IF;
  END IF;

  -- A SECRETARIA APRENDE (99b, Tel 22/09). A pergunta dela nao tem codigo de
  -- imovel -- e conhecimento geral da casa --, entao nao entra no
  -- `nay_gravar_conhecimento` acima, que e por imovel. Vai para o `nai_saber`,
  -- e e assim que ela para de perguntar a mesma coisa duas vezes.
  IF r.de_quem = 'secretaria' THEN
    PERFORM nai_saber_guardar(r.o_que_falta, btrim(p_resposta), 'tel', p_id);
  END IF;

  -- Quem mais perguntou a mesma coisa e ficou esperando em silêncio.
  v_texto := 'Sobre ' ||
             CASE WHEN r.codigo IS NOT NULL THEN 'o ' || r.codigo ELSE 'o que você perguntou' END
             || ': ' || p_resposta;

  -- O LEQUE NAO CARREGA NUMERO DE UNIDADE.
  --
  -- Responder UM corretor e decisao do Tel, e ele pode ter motivo -- o
  -- cara vai fazer a visita hoje. Mandar para os OUTROS e automatico,
  -- ninguem revisa, e a lista pode ter gente que ele nem lembra que
  -- perguntou. Aqui o padrao e negar. Achado no red team de 01/09.
  IF nay_tem_numero_de_unidade(p_resposta) THEN
    v_outros := -1;   -- sinaliza que houve gente esperando e NAO recebeu
    SELECT count(*) INTO v_esperando
      FROM pendencia_interessado i
     WHERE i.pendencia_id = p_id
       AND right(regexp_replace(i.telefone,'[^0-9]','','g'),8)
         <> right(regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'),8);
  ELSE
    INSERT INTO resposta_a_entregar (pendencia_id, telefone, texto)
    SELECT p_id, i.telefone, v_texto
      FROM pendencia_interessado i
     WHERE i.pendencia_id = p_id
       AND right(regexp_replace(i.telefone,'[^0-9]','','g'),8)
         <> right(regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'),8)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_outros = ROW_COUNT;
  END IF;

  -- O Tel PRECISA saber que o leque nao saiu, senao ele acha que os
  -- outros foram avisados.
  RETURN QUERY SELECT true, r.avisar, r.codigo,
    r.o_que_falta || CASE WHEN v_outros = -1 AND v_esperando > 0
      THEN ' [ATENCAO: sua resposta tem numero de unidade, entao NAO foi '
           || 'repassada aos outros ' || v_esperando || ' corretor(es) que '
           || 'esperavam. So quem perguntou primeiro recebeu.]'
      ELSE '' END;
END;
$function$;
