-- 183 -- o checklist de documentos, de aluguel e de venda, mandado pela Nay
-- (Pedro, 29/09/2026: "manda para a Rayssa os 2 tipos de checklist e como ela
-- pode pedir para a Nay mandar para algum contato, e implementa no card dos
-- corretores um botão enviar checklist, abre a opção venda ou aluguel, e a
-- Nay envia"). Era a pendência de 28/09 (a Rayssa pediu e a Nay não entendeu).
--
-- - documentos_venda: NOVO. Rascunho aprovado pelo Pedro em 29/09; muda com um
--   UPDATE em nai_config, sem deploy.
-- - documentos_locacao: sai a linha repetida do comprovante de renda (ficou a
--   mais completa).
-- - nai_ler_pedido_de_checklist: a frase de comando, com grafia errada
--   ("checlist", "cheklist", "check list") e sem ordem fixa. Devolve o
--   telefone e o tipo; o que faltar vira pergunta, não chute.
-- - nai_enviar_checklist_para: o envio pela caixa da Nay (papel 'entrega', o
--   mesmo do "envia 92... o 3050"), de um turno de comando.
-- - nai_checklist_enfileirar: o botão do CRM (turno do Tel, como o disparo 145).
-- O comando entra no nai_abrir_turno e no nai_comando_tel pela 184 (gerada da
-- função viva).

BEGIN;
SET LOCAL lock_timeout = '5s';

INSERT INTO nai_config (chave, valor, descricao)
VALUES ('documentos_venda',
'✅ VENDEDOR (PROPRIETÁRIO)

- RG e CPF ou CNH (e do cônjuge, se casado)
- Certidão de casamento ou nascimento atualizada
- Comprovante de residência
- Matrícula atualizada do imóvel (Cartório de Registro de Imóveis)
- Carnê do IPTU do ano ou certidão negativa de IPTU
- Declaração de quitação do condomínio (se for condomínio)
- Certidões negativas: débitos federais, trabalhistas, protestos e ações cíveis

✅ COMPRADOR — de CADA pessoa que vai assinar

- RG e CPF ou CNH (frente e verso, legível)
- Certidão de casamento ou nascimento
- Nacionalidade, profissão, estado civil
- Telefone/WhatsApp e e-mail
- Comprovante de residência
- Se for financiar: comprovante de renda (3 contracheques ou IR) e extrato do FGTS
- Se PJ: contrato social, CNPJ e documentos dos sócios',
'Checklist de documentos da VENDA, que a Nay manda pelo comando "checklist venda para 92..." e pelo botão do CRM (183). Rascunho aprovado pelo Pedro em 29/09.')
ON CONFLICT (chave) DO NOTHING;

-- a linha repetida do comprovante de renda (fica a mais completa, logo abaixo)
UPDATE nai_config
   SET valor = replace(valor, E'- Comprovante de renda: 3 contracheques, 3 extratos ou IR\n', '')
 WHERE chave = 'documentos_locacao'
   AND valor LIKE E'%- Comprovante de renda: 3 contracheques, 3 extratos ou IR\n%'
   AND valor LIKE '%- Comprovante de renda: 3 últimos contracheques%';

CREATE OR REPLACE FUNCTION nai_checklist_texto(p_tipo text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT nullif(btrim(valor), '') FROM nai_config
   WHERE chave = CASE p_tipo WHEN 'venda' THEN 'documentos_venda' WHEN 'locacao' THEN 'documentos_locacao' END
$$;

-- "checklist aluguel 92 99999-9999", "manda o checklist de venda pra 92...",
-- "92 9999-9999 cheklist locação". Sem a palavra do checklist, nada.
CREATE OR REPLACE FUNCTION nai_ler_pedido_de_checklist(p text)
RETURNS TABLE(telefone text, tipo text)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  s      text := lower(unaccent(btrim(coalesce(p, ''))));
  v_fone text := '(?:55[\s.-]*)?\(?[0-9]{2}\)?[\s.-]*[0-9]{4,5}[\s.-]*[0-9]{4}';
  m      text[];
BEGIN
  IF s !~ '(che(ck|k|c|q)u?e?[\s-]*li?st|lista\s+de\s+documentos|check\s*-?\s*list)' THEN
    RETURN;
  END IF;
  -- é pedido de envio, não conversa: curto e com verbo de mandar ou número
  IF length(s) > 160 OR (s !~ '(envi|mand|repass|encaminh)' AND s !~ v_fone) THEN
    RETURN;
  END IF;
  m := regexp_match(s, '(' || v_fone || ')');
  RETURN QUERY SELECT
    CASE WHEN m IS NOT NULL THEN m[1] END,
    CASE WHEN s ~ '(alug|loca[cç]|inquilin|locat)' AND s !~ '(vend|compr)' THEN 'locacao'
         WHEN s ~ '(vend|compr)' AND s !~ '(alug|loca[cç]|inquilin|locat)' THEN 'venda' END;
END;
$$;

CREATE OR REPLACE FUNCTION nai_e_comando_checklist(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT EXISTS (SELECT 1 FROM nai_ler_pedido_de_checklist(p));
$$;

CREATE OR REPLACE FUNCTION nai_enviar_checklist_para(p_turno bigint, p_tipo text, p_telefone text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_digitos text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_chave   text;
  v_destino bigint;
  v_texto   text;
  v_hora    int := extract(hour FROM now() AT TIME ZONE 'America/Manaus');
  v_nome    text := CASE p_tipo WHEN 'venda' THEN 'venda' WHEN 'locacao' THEN 'aluguel' END;
BEGIN
  IF v_nome IS NULL THEN
    RETURN 'De aluguel ou de venda? Manda assim: checklist aluguel para 92 99999-9999 (ou checklist venda para 92 99999-9999).';
  END IF;
  IF length(v_digitos) < 10 OR nai_chave(v_digitos) IS NULL THEN
    RETURN 'Para qual número? Manda assim: checklist ' || v_nome || ' para 92 99999-9999';
  END IF;
  v_texto := nai_checklist_texto(p_tipo);
  IF v_texto IS NULL THEN
    RETURN 'Ainda não tenho o checklist de ' || v_nome || ' cadastrado.';
  END IF;
  v_chave := nai_chave(v_digitos);

  -- o contato do destino (nasce aqui se não existir), como no envio de imóvel
  SELECT id INTO v_destino FROM nai_contato WHERE chave = v_chave;
  IF v_destino IS NULL THEN
    INSERT INTO nai_contato (chave, telefone, nome_whatsapp) VALUES (v_chave, v_digitos, NULL)
    RETURNING id INTO v_destino;
  END IF;

  PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'entrega',
    'Oi, ' || CASE WHEN v_hora < 12 THEN 'bom dia' WHEN v_hora < 18 THEN 'boa tarde' ELSE 'boa noite' END
    || '! Segue a lista de documentos para ' || CASE p_tipo WHEN 'venda' THEN 'a venda' ELSE 'o aluguel' END || E':\n\n'
    || v_texto,
    'checklist', 1);
  RETURN 'Mandei o checklist de ' || v_nome || ' para ' || nai_fone_fmt(v_digitos) || '.';
END;
$$;

-- o botão do CRM: um turno do Tel, como o disparo do painel (145)
CREATE OR REPLACE FUNCTION nai_checklist_enfileirar(p_telefone text, p_tipo text, p_quem text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tel   bigint := nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel');
  v_turno bigint;
  v_msg   text;
BEGIN
  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (v_tel, 'tel', left('checklist pelo CRM (' || coalesce(nullif(btrim(p_quem), ''), '?') || '): '
                            || coalesce(p_tipo, '?') || ' para ' || coalesce(p_telefone, ''), 500))
  RETURNING id INTO v_turno;
  v_msg := nai_enviar_checklist_para(v_turno, p_tipo, p_telefone);
  UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
  UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  RETURN v_msg;
END;
$$;

REVOKE ALL ON FUNCTION nai_checklist_enfileirar(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_checklist_enfileirar(text, text, text) TO nay_disparo;

COMMIT;
