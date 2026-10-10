-- 339 -- Captação ativa: ENVIO MANUAL (o botão "Enviar ao corretor")
--
-- Pedro, 09/10/2026 à noite: "põe um botão de enviar manualmente; eu já tinha deixado a msg padrão".
--
-- A mensagem padrão é a da especificação dele (config.json do nay-grupos, `mensagem_de_abertura`):
--   "Oi, vi sua solicitação no grupo, tenho um imóvel que pode se encaixar no que o seu cliente quer, vou te
--    enviar aqui ok? Qualquer dúvida me avisa"
--
-- O envio é sempre um clique DELE, por pedido. Nada sai sozinho: o serviço que lê os grupos continua sem ter por
-- onde enviar. O clique chama `site_captacao_grupos_enviar`, que põe na caixa de saída da Nay (papel 'entrega',
-- o MESMO caminho da aba "Enviar imóvel": `nai_enviar_imoveis_para`) a abertura e, se `enviar_dados_e_fotos`, o
-- card e as fotos. Quem entrega é o enviador manual, pelo número da Parceria, com as travas de sempre: parceiro
-- não sai, indisponível não sai, o mesmo imóvel não vai duas vezes à mesma pessoa em 24 h.
--
-- As travas daqui (as "regras de segurança" da especificação):
--   - só pedido de grupo, dentro da janela (48 h), não rejeitado, com o telefone de quem escreveu;
--   - só um imóvel que casou com o pedido, e o mesmo imóvel nunca duas vezes para o mesmo pedido;
--   - duas mensagens ao mesmo corretor só com `intervalo_min_entre_envios` minutos entre elas;
--   - `envio_manual` = false no config.json desliga o botão e esta função.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- as ofertas feitas (sem chave estrangeira, de propósito: a tabela de pedidos está em uso)
CREATE TABLE IF NOT EXISTS privado.grupo_pedido_oferta (
  id         bigserial   PRIMARY KEY,
  pedido_id  bigint      NOT NULL,
  codigo     integer     NOT NULL,
  telefone   text        NOT NULL,
  abertura   text        NOT NULL,
  com_card   boolean     NOT NULL,
  turno_id   bigint,                              -- o turno da caixa da Nay por onde saiu
  resumo     text,
  quem       text,
  enviado_em timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pedido_id, codigo)
);
CREATE INDEX IF NOT EXISTS grupo_pedido_oferta_telefone ON privado.grupo_pedido_oferta (telefone, enviado_em DESC);

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_enviar(p_id bigint, p_codigo integer, p_abertura text DEFAULT NULL, p_quem text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  q       privado.grupo_pedido;
  e       privado.grupo_captacao_estado;
  v_fone  text;
  v_abert text;
  v_card  boolean;
  v_min   int;
  v_ult   timestamptz;
  v_turno bigint;
  v_dest  bigint;
  v_msg   text;
  v_fila  record;
  v_resumo text;
BEGIN
  SELECT * INTO e FROM privado.grupo_captacao_estado WHERE id = 1;
  IF coalesce(e.config->>'envio_manual', 'false') <> 'true' THEN
    RETURN jsonb_build_object('erro', 'O envio manual está desligado na configuração (envio_manual).');
  END IF;
  SELECT * INTO q FROM privado.grupo_pedido WHERE id = p_id FOR UPDATE;
  IF q.id IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  IF q.fonte = 'teste' THEN
    RETURN jsonb_build_object('erro', 'Isto é um teste colado na tela: não tem corretor para receber.');
  END IF;
  IF q.estado = 'rejeitado' THEN
    RETURN jsonb_build_object('erro', 'Esta solicitação está rejeitada. Desfaça a rejeição antes de enviar.');
  END IF;
  IF q.enviada_em < now() - make_interval(hours => coalesce(nullif(e.config->>'janela_h', '')::numeric::int, 48)) THEN
    RETURN jsonb_build_object('erro', 'Este pedido já passou de ' || coalesce(nullif(e.config->>'janela_h', ''), '48') || ' h: não envio.');
  END IF;
  v_fone := regexp_replace(coalesce(q.remetente, ''), '\D', '', 'g');
  IF length(v_fone) NOT BETWEEN 10 AND 13 OR nai_chave(v_fone) IS NULL THEN
    RETURN jsonb_build_object('erro', 'Não tenho o telefone de quem escreveu (a mensagem veio sem número). Fale com a pessoa pelo grupo.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_par p WHERE p.pedido_id = q.id AND p.codigo = p_codigo) THEN
    RETURN jsonb_build_object('erro', 'Esse imóvel não está entre os que casaram com este pedido.');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta o WHERE o.pedido_id = q.id AND o.codigo = p_codigo) THEN
    RETURN jsonb_build_object('erro', 'Esse imóvel já foi enviado para este pedido.');
  END IF;
  -- duas mensagens ao mesmo corretor, só com o intervalo (para não parecer spam nem arriscar o número)
  v_min := greatest(coalesce(nullif(e.config->>'intervalo_min_entre_envios', '')::numeric::int, 30), 0);
  SELECT max(o.enviado_em) INTO v_ult FROM privado.grupo_pedido_oferta o WHERE nai_chave(o.telefone) = nai_chave(v_fone);
  IF v_ult IS NOT NULL AND v_ult > now() - make_interval(mins => v_min) THEN
    RETURN jsonb_build_object('erro', 'Esse corretor já recebeu uma mensagem daqui às ' || to_char(v_ult AT TIME ZONE 'America/Manaus', 'HH24:MI')
                                      || '. O intervalo é de ' || v_min || ' min: dá para mandar de novo às '
                                      || to_char((v_ult + make_interval(mins => v_min)) AT TIME ZONE 'America/Manaus', 'HH24:MI') || '.');
  END IF;
  v_abert := left(btrim(coalesce(nullif(btrim(p_abertura), ''), e.config->>'mensagem_de_abertura', '')), 700);
  IF v_abert = '' THEN RETURN jsonb_build_object('erro', 'A mensagem de abertura está vazia.'); END IF;
  v_card := coalesce(e.config->>'enviar_dados_e_fotos', 'true') = 'true';

  -- daqui para baixo é tudo ou nada: se o imóvel não puder ir, nem a abertura fica na caixa
  BEGIN
    INSERT INTO nai_turno (contato_id, papel, texto)
    VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
            left('captação ativa pelo painel (' || coalesce(nullif(btrim(p_quem), ''), 'site') || '): ' || p_codigo
                 || ' para ' || v_fone || ', pedido ' || q.id, 500))
    RETURNING id INTO v_turno;
    v_dest := nai_contato_do_cadastro(v_fone, q.remetente_nome);
    -- a abertura entra ANTES do card: a caixa entrega na ordem em que as linhas nascem
    PERFORM nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega', v_abert, 'captacao_ativa_abertura', 1);
    IF v_card THEN
      v_msg := nai_enviar_imoveis_para(v_turno, ARRAY[p_codigo], v_fone);
      IF v_msg NOT LIKE 'Mandei para %' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = v_msg;
      END IF;
    END IF;
    -- sai no próximo ciclo do enviador (como a aba Enviar imóvel)
    UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    RETURN jsonb_build_object('erro', regexp_replace(SQLERRM, '^Não mandei nada para [^:]*:\s*', 'Não enviei: '));
  END;

  SELECT count(*) FILTER (WHERE s.tipo = 'imagem' AND s.estado = 'pendente') AS fotos,
         count(*) FILTER (WHERE s.estado = 'bloqueado') AS barradas,
         string_agg(DISTINCT s.bloqueio, '; ') FILTER (WHERE s.estado = 'bloqueado') AS motivos
    INTO v_fila FROM nai_saida s WHERE s.turno_id = v_turno;
  v_resumo := 'Na fila de envio: a abertura'
              || CASE WHEN v_card THEN ', o card e ' || v_fila.fotos || CASE WHEN v_fila.fotos = 1 THEN ' foto' ELSE ' fotos' END ELSE ' (só ela)' END
              || CASE WHEN v_fila.barradas > 0 THEN '. ' || v_fila.barradas || ' mensagem(ns) barrada(s): ' || coalesce(v_fila.motivos, '?') ELSE '' END || '.';

  INSERT INTO privado.grupo_pedido_oferta (pedido_id, codigo, telefone, abertura, com_card, turno_id, resumo, quem)
  VALUES (q.id, p_codigo, v_fone, v_abert, v_card, v_turno, v_resumo, nullif(btrim(coalesce(p_quem, '')), ''));
  UPDATE privado.grupo_pedido SET estado = 'enviado' WHERE id = q.id;
  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'turno', v_turno);
END
$function$;

REVOKE ALL ON FUNCTION public.site_captacao_grupos_enviar(bigint, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_captacao_grupos_enviar(bigint, integer, text, text) TO nay_site_escrita;

-- a tela passa a receber o que já foi enviado em cada pedido
DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.site_captacao_grupos(text,integer,integer)'::regprocedure);
  v_velho text := $v$               'julgamento', (SELECT jsonb_build_object('leitura', j.leitura,$v$;
  v_novo  text := $n$               'ofertas', coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', o.codigo, 'quando', o.enviado_em,
                                                                        'com_card', o.com_card, 'resumo', o.resumo) ORDER BY o.enviado_em)
                                      FROM privado.grupo_pedido_oferta o WHERE o.pedido_id = q.id), '[]'::jsonb),   -- 339
               'julgamento', (SELECT jsonb_build_object('leitura', j.leitura,$n$;
BEGIN
  IF position('grupo_pedido_oferta' IN v_def) > 0 THEN RAISE EXCEPTION '339: já aplicada'; END IF;
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '339: o trecho de site_captacao_grupos mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

COMMIT;
