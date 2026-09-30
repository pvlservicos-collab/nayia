-- 223 (30/09/2026): O PERFIL DO CLIENTE DE CADA PEDIDO.
-- Pedro: "quando o corretor perguntar de um imóvel se tem elevador, ela responde
-- que sim ou que não, e pergunta depois se para o cliente dele só serve imóvel com
-- elevador, para poder fazer esse filtro ... ela vai estar sempre formando um
-- perfil do cliente que o corretor está oferecendo a cada solicitação diferente,
-- não é para ela fazer uma vez e nas próximas ignorar esse perfil e identificação."
-- E as decisões dele: "busca prédios com elevador perto; se não, pode negar mesmo,
-- de forma educada"; perfil novo "quando o corretor pedir outro imóvel depois de já
-- ter pedido um, ex.: pediu locação em um bairro até 4k, depois locação em outro a
-- partir de 3k".
--
--   nai_perfil_cliente     um por pedido: negócio, tipo, valor, bairros, quartos,
--                          mobília, e o que o cliente EXIGE (jsonb: elevador...).
--   busca                  grava o perfil a cada chamada; o que a chamada não trouxe
--                          vem do perfil (não pergunta de novo); bairro ou valor
--                          DIFERENTE do perfil = pedido novo (perfil novo); com
--                          "só com elevador", só prédio com elevador CONFIRMADO,
--                          também ao redor (219), e o "não" diz "com elevador".
--   "tem elevador?"        depois da resposta: "Para o seu cliente, só serve imóvel
--                          com elevador?"; a resposta dele vai para o perfil.
--   contexto               o perfil entra no cabeçalho de todo turno do corretor.
-- Elevador confirmado = o anúncio antigo cita (lazer do condomínio/características);
-- sem elevador = lances de escada >= 1, ou casa; o resto é "não sabemos".
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS nai_perfil_cliente (
  id            bigserial PRIMARY KEY,
  contato_id    bigint NOT NULL,   -- sem FK de propósito: criar FK trava nai_contato (a Nay escreve nela o tempo todo)
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  encerrado_em  timestamptz,
  negocio       text,
  tipo          text,
  teto          numeric,
  bairros       text,
  quartos       text,
  mobilia       text,
  exige         jsonb NOT NULL DEFAULT '{}'::jsonb,
  pendente      text,
  pendente_em   timestamptz
);
CREATE INDEX IF NOT EXISTS nai_perfil_cliente_ativo ON nai_perfil_cliente (contato_id, atualizado_em DESC) WHERE encerrado_em IS NULL;

CREATE OR REPLACE FUNCTION nai_imovel_tem_elevador(p_codigo integer)
 RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM imovel_ficha f WHERE f.codigo = i.codigo
                  AND (array_to_string(f.caracteristicas_condominio, ' ') ~* 'elevador'
                       OR coalesce(f.campos->>'elevadores', '') ~ '[1-9]'))
      OR array_to_string(i.caracteristicas, ' ') ~* 'elevador' THEN true
    WHEN coalesce(nullif(i.extras->>'lances de escada', ''), '0') ~ '^[1-9]' THEN false
    WHEN lower(coalesce(i.tipo, '')) ~ 'casa' THEN false
    ELSE NULL END
    FROM imoveis i WHERE i.codigo = p_codigo;
$$;

-- o perfil em andamento da pessoa (as duas linhas), até 7 dias sem mexer
CREATE OR REPLACE FUNCTION nai_perfil_ativo(p_contato bigint)
 RETURNS SETOF nai_perfil_cliente LANGUAGE sql STABLE AS $$
  SELECT p.* FROM nai_perfil_cliente p
   WHERE p.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))
     AND p.encerrado_em IS NULL AND p.atualizado_em > now() - interval '7 days'
   ORDER BY p.atualizado_em DESC LIMIT 1;
$$;

-- grava (ou começa) o perfil: o que veio preenche, o que não veio fica como estava
CREATE OR REPLACE FUNCTION nai_perfil_gravar(p_contato bigint, p_novo boolean, p_bairros text, p_teto numeric,
                                             p_quartos text, p_mobilia text, p_negocio text, p_tipo text)
 RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM nai_perfil_ativo(p_contato);
  IF v_id IS NOT NULL AND p_novo THEN
    UPDATE nai_perfil_cliente SET encerrado_em = now() WHERE id = v_id;
    v_id := NULL;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO nai_perfil_cliente (contato_id, negocio, tipo, teto, bairros, quartos, mobilia)
    VALUES (p_contato, p_negocio, p_tipo, p_teto, nullif(btrim(coalesce(p_bairros, '')), ''),
            nullif(btrim(coalesce(p_quartos, '')), ''), nullif(btrim(coalesce(p_mobilia, '')), ''))
    RETURNING id INTO v_id;
  ELSE
    UPDATE nai_perfil_cliente SET
      negocio = coalesce(p_negocio, negocio), tipo = coalesce(p_tipo, tipo), teto = coalesce(p_teto, teto),
      bairros = coalesce(nullif(btrim(coalesce(p_bairros, '')), ''), bairros),
      quartos = coalesce(nullif(btrim(coalesce(p_quartos, '')), ''), quartos),
      mobilia = coalesce(nullif(btrim(coalesce(p_mobilia, '')), ''), mobilia),
      atualizado_em = now()
     WHERE id = v_id;
  END IF;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;   -- anotação auxiliar nunca derruba a busca (ver "estado da conversa não cala")
END $$;

-- o perfil para o modelo, no cabeçalho do turno
CREATE OR REPLACE FUNCTION nai_perfil_texto(p_contato bigint)
 RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p.id IS NULL THEN NULL ELSE
    'PERFIL DO CLIENTE DESTE PEDIDO (o que o corretor já disse): '
    || concat_ws(' · ',
         CASE p.negocio WHEN 'venda' THEN 'venda' WHEN 'locacao' THEN 'locação' END,
         nai_rotulo_do_tipo(p.tipo),
         CASE WHEN p.teto IS NOT NULL THEN 'até R$ ' || replace(to_char(p.teto, 'FM999,999,990'), ',', '.') END,
         CASE WHEN p.bairros IS NOT NULL THEN 'bairros: ' || p.bairros END,
         CASE WHEN p.quartos IS NOT NULL THEN 'quartos: ' || p.quartos END,
         CASE WHEN p.mobilia IS NOT NULL THEN 'mobília: ' || p.mobilia END,
         CASE WHEN (p.exige->>'elevador') = 'true' THEN 'só serve com elevador'
              WHEN (p.exige->>'elevador') = 'false' THEN 'pode ser sem elevador' END)
    || '. Use estes dados ao chamar buscar_por_perfil em vez de perguntar de novo. Se ele pedir outro imóvel com outro bairro ou outro valor, é um pedido novo.'
  END
    FROM (SELECT * FROM nai_perfil_ativo(p_contato)) p
   WHERE p.negocio IS NOT NULL OR p.tipo IS NOT NULL OR p.teto IS NOT NULL OR p.bairros IS NOT NULL
      OR p.quartos IS NOT NULL OR p.mobilia IS NOT NULL OR p.exige <> '{}'::jsonb;
$$;

-- a resposta dele à pergunta do perfil ("só serve com elevador?")
CREATE OR REPLACE FUNCTION nai_perfil_resposta(p_contato bigint, p_texto text, p_turno bigint)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE p nai_perfil_cliente; v_ultima text; s text := lower(unaccent(coalesce(p_texto, ''))); v bool;
BEGIN
  SELECT * INTO p FROM nai_perfil_ativo(p_contato);
  IF p.id IS NULL OR p.pendente IS NULL OR p.pendente_em < now() - interval '6 hours' THEN RETURN; END IF;
  -- só vale se a ÚLTIMA fala dela foi a pergunta do perfil
  SELECT s2.texto INTO v_ultima FROM nai_saida s2
   WHERE s2.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato])) AND s2.tipo = 'texto'
     AND s2.estado IN ('enviado', 'enviando', 'simulado')
   ORDER BY s2.criado_em DESC LIMIT 1;
  IF coalesce(v_ultima, '') !~* 'só serve imóvel com elevador' THEN RETURN; END IF;
  v := CASE
    WHEN s ~ '(nao precisa|tanto faz|pode ser sem|sem problema|qualquer|indiferente|nao importa|nao faz diferenca|nao e obrigat)' THEN false
    WHEN s ~ '(\msim\M|s[oó] (com|serve)|precisa|tem que ter|obrigat|somente|necessari|com elevador|\misso\M)' THEN true
    WHEN s ~ '^\s*(nao|n)\M' THEN false
    ELSE NULL END;
  IF v IS NULL THEN RETURN; END IF;
  UPDATE nai_perfil_cliente SET exige = exige || jsonb_build_object('elevador', v), pendente = NULL, pendente_em = NULL,
                                atualizado_em = now()
   WHERE id = p.id;
  PERFORM nai_anotar(p_turno, 1, 'perfil_do_cliente', 'mudou', 'elevador: ' || CASE WHEN v THEN 'só com elevador' ELSE 'pode ser sem' END);
EXCEPTION WHEN OTHERS THEN
  RETURN;
END $$;

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

-- A BUSCA -----------------------------------------------------------------
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_ultima       text;     -- 215: a última pergunta do filtro que ela fez (24 h)
$a$, $b$  v_ultima       text;     -- 215: a última pergunta do filtro que ela fez (24 h)
  v_perfil       nai_perfil_cliente;  -- 223: o perfil do cliente deste pedido
  v_pedido_novo  boolean := false;    -- 223: bairro ou valor diferente do perfil
  v_elev         boolean := false;    -- 223: o cliente só aceita com elevador
$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  -- 218: QUARTOS -- "1 ou 2" é de 1 a 2 (antes virava 12); "2 ou mais" é 2 para cima$a$,
$b$  -- 223: O PERFIL DO CLIENTE. Bairro ou valor DIFERENTE do perfil em andamento é
  -- pedido novo (Pedro: "pediu locação em um bairro até 4k, depois locação em outro a
  -- partir de 3k"); senão, o que a chamada não trouxe vem do perfil.
  SELECT * INTO v_perfil FROM nai_perfil_ativo(k.id);
  IF v_perfil.id IS NOT NULL THEN
    v_pedido_novo :=
         (nullif(btrim(coalesce(p_bairro, '')), '') IS NOT NULL AND v_perfil.bairros IS NOT NULL
          AND NOT nai_sem_preferencia_de_bairro(p_bairro)
          AND nay_normalizar_lugar(p_bairro, true) <> nay_normalizar_lugar(v_perfil.bairros, true))
      OR (v_teto IS NOT NULL AND v_perfil.teto IS NOT NULL AND abs(v_teto - v_perfil.teto) > 0.1 * v_perfil.teto);
    IF NOT v_pedido_novo THEN
      p_bairro   := coalesce(nullif(btrim(coalesce(p_bairro, '')), ''), v_perfil.bairros);
      p_teto     := coalesce(nullif(btrim(coalesce(p_teto, '')), ''), v_perfil.teto::text);
      p_quartos  := coalesce(nullif(btrim(coalesce(p_quartos, '')), ''), v_perfil.quartos);
      p_mobilia  := coalesce(nullif(btrim(coalesce(p_mobilia, '')), ''), v_perfil.mobilia);
      v_teto     := coalesce(nay_maior_valor(p_teto), nay_valor_em_reais(p_teto));
      v_mob      := lower(unaccent(btrim(coalesce(p_mobilia, ''))));
      v_elev     := coalesce((v_perfil.exige->>'elevador')::boolean, false);
    END IF;
  END IF;

  -- 218: QUARTOS -- "1 ou 2" é de 1 a 2 (antes virava 12); "2 ou mais" é 2 para cima$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$                    ELSE 'nenhum ' || v_rotulo END;
  v_diz     := CASE WHEN v_negocio = 'venda' THEN 'venda' ELSE 'locação' END;$a$,
$b$                    ELSE 'nenhum ' || v_rotulo END;
  v_diz     := CASE WHEN v_negocio = 'venda' THEN 'venda' ELSE 'locação' END;
  -- 223: o "não" educado diz o que falta ("nenhum apartamento com elevador")
  IF v_elev THEN v_nada := v_nada || ' com elevador'; END IF;
  -- 223: grava o perfil deste pedido (o que veio preenche; pedido novo começa outro)
  PERFORM nai_perfil_gravar(k.id, v_pedido_novo, p_bairro, v_teto, p_quartos, p_mobilia, v_negocio, v_tipo);
  IF v_pedido_novo THEN
    PERFORM nai_anotar(p_turno, 7, 'perfil_do_cliente', 'mudou', 'pedido novo: outro bairro ou outro valor');
  END IF;$b$);

-- só prédio com elevador CONFIRMADO, quando o cliente exige (nas listas e ao redor)
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$(v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max)$a$,
$b$(v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max) AND (NOT v_elev OR nai_imovel_tem_elevador(i.codigo) IS TRUE)$b$, 5);

-- A PERGUNTA DO PERFIL depois de "tem elevador?" ----------------------------
SELECT pg_temp.trocar('nai_enfileirar_resposta_ferramentas(bigint,text,jsonb,text,jsonb,jsonb)',
$a$  RETURN v_r;
END;
$function$$a$,
$b$  -- 223: ELE PERGUNTOU DO ELEVADOR: depois da resposta, a pergunta do perfil
  -- ("Para o seu cliente, só serve imóvel com elevador?"), uma vez por perfil
  BEGIN
    IF v_contato IS NOT NULL AND v_papel = 'corretor' AND coalesce(p_escreveu, '') ~* 'elevador'
       AND EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = p_turno)
       AND NOT EXISTS (SELECT 1 FROM nai_perfil_ativo(v_contato) pa
                        WHERE pa.exige ? 'elevador' OR pa.pendente = 'elevador') THEN
      PERFORM nai_perfil_gravar(v_contato, false, NULL, NULL, NULL, NULL, NULL, NULL);
      UPDATE nai_perfil_cliente SET pendente = 'elevador', pendente_em = now()
       WHERE id = (SELECT id FROM nai_perfil_ativo(v_contato));
      -- uma pergunta por vez: a sugestão de visita deste turno sai (volta depois)
      DELETE FROM nai_saida WHERE turno_id = p_turno AND motivo = 'sugere_visita' AND estado = 'pendente';
      PERFORM nai_enfileirar_texto(p_turno, NULL, v_contato, 'turno',
        'Para o seu cliente, só serve imóvel com elevador?', 'perfil_do_cliente', 95);
      PERFORM nai_anotar(p_turno, 24, 'perfil_do_cliente', 'mudou', 'perguntou se o cliente só aceita com elevador');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;   -- a pergunta do perfil nunca derruba a resposta
  END;

  RETURN v_r;
END;
$function$$b$);

-- O CABEÇALHO: a resposta à pergunta do perfil, e o perfil no contexto -------
SELECT pg_temp.trocar('nai_abrir_turno(text,text,text,text,bigint[])',
$a$  -- 141b: a etapa e atualizada ANTES de montar o cabecalho. Dentro do$a$,
$b$  -- 223: a resposta dele à pergunta do perfil ("só serve com elevador?") vai para o perfil
  IF v_papel = 'corretor' THEN
    PERFORM nai_perfil_resposta(v_contato, v_texto, v_turno);
  END IF;

  -- 141b: a etapa e atualizada ANTES de montar o cabecalho. Dentro do$b$);

SELECT pg_temp.trocar('nai_abrir_turno(text,text,text,text,bigint[])',
$a$    'contexto', CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' || coalesce(nai_retomada_texto(v_contato), '') ELSE '' END$a$,
$b$    'contexto', CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' || coalesce(nai_retomada_texto(v_contato), '')
                        || coalesce(E'\n' || nai_perfil_texto(v_contato), '') ELSE '' END$b$);
COMMIT;
