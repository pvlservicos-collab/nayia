-- 213 (revisão de 30/09/2026, pedido do Pedro: "revisa tudo ... para a Nay não
-- mandar imóvel para quem não está pedindo"). Achado nos envios reais do dia:
--
--   09:06 a Nay manda o follow-up ao corretor …3297;
--   09:09 chega a RESPOSTA AUTOMÁTICA do WhatsApp Business dele: "Olá! Obrigado pela
--         sua mensagem. No momento, estou ausente e retornarei em breve ... Que 2026
--         seja um ano repleto de boas oportunidades";
--   09:09 a Nay lê "2026" como o CÓDIGO do imóvel 2026 (indisponível), responde "o
--         2026 está indisponível" e manda card e fotos do 5696, que ninguém pediu.
--
-- Dois consertos, um para cada erro:
--   1. ANO NÃO É CÓDIGO: "que 2026 seja", "em 2026", "feliz 2026", "2026 foi" saem
--      antes de procurar código (nay_codigos_citados). "o 2026 está disponível?"
--      continua sendo o imóvel 2026. (A 78 já tirava "maio de 2026" e "10/05/2026".)
--   2. RESPOSTA AUTOMÁTICA NÃO É MENSAGEM DELE: nai_abrir_turno grava e não responde
--      (o mesmo "ok falso" do 186/197). Medido em 90 dias de mensagens: pega "estou
--      ausente", "retornarei seu contato", "recebi sua mensagem", "agradecemos seu
--      contato", "atendemos de segunda..."; NÃO pega "obrigado pelo contato mas eu já
--      fechei negócio" nem "agradeço seu contato, mas não temos interesse".
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION nai_tirar_anos(p_texto text)
 RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT regexp_replace(lower(coalesce(p_texto, '')),
    '\m(em|de|desde|ano|feliz|que|para|pra)[ \t]+20[1-3][0-9]\M|\m20[1-3][0-9][ \t]+(seja|sera|será|foi|vai|chegou|chegando)\M',
    ' ', 'g');
$$;

CREATE OR REPLACE FUNCTION public.nay_codigos_citados(p_texto text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE COST 300
AS $function$
  -- 213: o ano sai antes ("Que 2026 seja um ano..." virava o imóvel 2026)
  SELECT coalesce(array_agg(DISTINCT m[1]), ARRAY[]::text[])
    FROM regexp_matches(' ' || nay_tirar_valores(nai_tirar_anos(p_texto)) || ' ',
                        '[^0-9.,]([0-9]{3,5})[^0-9.,]', 'g') AS m;
$function$;

CREATE OR REPLACE FUNCTION nai_e_resposta_automatica(p_texto text)
 RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT length(btrim(coalesce(p_texto, ''))) >= 20
     AND lower(unaccent(p_texto)) ~ ('(estou ausente|retornarei (o |seu |o seu )?contato|retornarei em breve'
         || '|responderei (assim que|com toda|em breve)|logo retorno o contato|assim que possivel,? eu retorno'
         || '|recebi sua mensagem|mensagem automatica|resposta automatica'
         || '|(agradece|agradecemos) (o |seu )?contato|atend(emos|imento) de segunda)')
     AND cardinality(nay_codigos_citados(p_texto)) = 0;
$$;

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('nai_abrir_turno(text,text,text,text,bigint[])',
$a$      RETURN jsonb_build_object('ok', false, 'motivo', v_rayssa, 'turno_id', v_turno,
                                'contato_id', v_contato, 'papel', v_papel);
    END IF;
  END IF;
$a$, $b$      RETURN jsonb_build_object('ok', false, 'motivo', v_rayssa, 'turno_id', v_turno,
                                'contato_id', v_contato, 'papel', v_papel);
    END IF;
  END IF;

  -- 213: a RESPOSTA AUTOMÁTICA do WhatsApp Business do corretor ("estou ausente",
  -- "retornarei seu contato") não é mensagem dele: fica gravada e a Nay não responde.
  -- Em 30/09 uma delas ("Que 2026 seja um ano...") fez a Nay mandar um imóvel.
  IF v_papel = 'corretor' AND nai_e_resposta_automatica(v_texto) THEN
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
    RETURN jsonb_build_object('ok', false, 'motivo', 'resposta_automatica', 'turno_id', v_turno,
                              'contato_id', v_contato, 'papel', v_papel);
  END IF;
$b$);

-- A BATERIA passa a conferir as três regras novas do dia (206 e 213)
SELECT pg_temp.trocar('nai_rodar_casos()',
$a$      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'$a$,
$b$      WHEN 'codigos'    THEN nay_codigos_citados(c.frase)::text  -- 213
      WHEN 'automatica' THEN nai_e_resposta_automatica(c.frase)::text  -- 213
      WHEN 'lugar'      THEN coalesce(nai_bairros_do_lugar(c.frase)::text, '-')  -- 206
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'$b$);

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('revisão 30/09', 'Que 2026 seja um ano repleto de boas oportunidades', 'codigos', '{}', 'ano não é código de imóvel'),
  ('revisão 30/09', 'o 2026 está disponível?', 'codigos', '{2026}', 'o imóvel 2026 continua sendo código'),
  ('revisão 30/09', 'Olá! Obrigado pela sua mensagem. No momento, estou ausente e retornarei em breve.', 'automatica', 'true', 'resposta automática: a Nay não responde'),
  ('revisão 30/09', 'Olá, boa tarde. Muito obrigado pelo contato mas eu já fechei negócio. Obrigado', 'automatica', 'false', 'gente agradecendo não é resposta automática'),
  ('revisão 30/09', 'estou ausente hoje, mas me manda o 5718 que eu vejo depois', 'automatica', 'false', 'ausente mas pedindo imóvel: responde'),
  ('Pedro 30/09', 'tem apto no cj eldorado?', 'lugar', '{"Parque 10 de Novembro"}', 'conjunto vira o bairro dele'),
  ('Pedro 30/09', 'sou a Débora, corretora', 'lugar', '-', 'nome de gente não é conjunto'),
  ('Pedro 30/09', 'visita dia 31 de março', 'lugar', '-', 'data não é conjunto'),
  ('Pedro 30/09', 'bairro tancredo neves', 'lugar', '-', 'o bairro Tancredo Neves não é a avenida');
COMMIT;
