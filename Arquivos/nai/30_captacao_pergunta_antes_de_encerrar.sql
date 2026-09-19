-- =====================================================================
-- CAPTACAO -- 30: perguntar de outros imoveis ANTES de encerrar
--                 (Tel, 15/09/2026)
--
-- Ele, olhando a conversa do Sr. Marcelo: "nesse caso ela pode dizer: entendi
-- Sr. Marcelo, o Sr. tem outro imovel que queira vender ou alugar? SEMPRE
-- antes de terminar se pergunta de mais imoveis antes de encerrar".
--
-- O que aconteceu: ele disse "Estou usando, nao tenho interesse em alugar" e
-- ela respondeu "Desculpe, Sr. Marcelo. Vou remover o contato das mensagens" --
-- encerrou sem nunca perguntar se ele tinha outro imovel. Cada conversa dessas
-- e uma chance de captacao perdida, e a conversa ja estava aberta.
--
-- A REGRA VIRA PAREDE, nao instrucao: `encerrar_conversa` RECUSA encerrar
-- enquanto a pergunta dos outros imoveis nao tiver saido, e devolve a frase
-- pronta para ela dizer. Nao depende do modelo lembrar.
--
-- COMO SE SABE QUE JA PERGUNTOU: olhando o que ELA JA MANDOU para esse lead --
-- se alguma mensagem enviada fala em "outro imovel"/"outros imoveis", a
-- pergunta saiu. E medida, nao memoria do modelo.
--
-- A UNICA EXCECAO, e ela importa: quando a pessoa PEDIU para parar de receber
-- ("nao quero receber", "me tire da lista", "descadastrar"), encerra na hora.
-- Insistir com quem pediu para sair rende reclamacao, nao imovel.
--
-- A logica mora aqui no banco de proposito: o proximo ajuste nesta regra e um
-- CREATE OR REPLACE, sem import de fluxo e sem a NAI sair do ar.
-- =====================================================================

-- A pessoa pediu, com todas as letras, para parar de receber?
CREATE OR REPLACE FUNCTION captacao_pediu_para_sair(p_texto text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(unaccent(coalesce(p_texto, ''))) ~
         ('\m(nao quero (mais )?receber|nao me (mande|manda|envie)|para de (me )?mandar|'
       || 'pare de (me )?(mandar|enviar)|me (tira|tire|remove|remova) (da|dessa|desta) lista|'
       || 'descadastr|sair da lista|nao envie mais|nao manda mais|me exclui|nao perturbe)');
$$;

-- Ela ja perguntou dos outros imoveis para este lead?
CREATE OR REPLACE FUNCTION captacao_ja_perguntou_outros(p_lead bigint)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM captacao_mensagens m
     WHERE m.lead_id = p_lead AND m.direcao = 'enviada'
       AND lower(unaccent(coalesce(m.texto, ''))) ~ '\m(outro imovel|outros imoveis|algum outro)\M');
$$;

-- A frase pronta, no tratamento certo (Sr./Sra./voce), como o Tel escreveu.
CREATE OR REPLACE FUNCTION captacao_frase_outros(p_lead bigint)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE coalesce(l.tratamento, '')
           WHEN 'Sra.' THEN 'Entendi, Sra. ' || coalesce(l.nome, '') ||
                            '. A Sra. tem outro imóvel que queira vender ou alugar?'
           WHEN 'Sr.'  THEN 'Entendi, Sr. ' || coalesce(l.nome, '') ||
                            '. O Sr. tem outro imóvel que queira vender ou alugar?'
           ELSE 'Entendi' || coalesce(', ' || l.nome, '') ||
                '. Você tem outro imóvel que queira vender ou alugar?'
         END
    FROM captacao_leads l WHERE l.id = p_lead;
$$;

-- O ENCERRAMENTO, com a parede dentro.
CREATE OR REPLACE FUNCTION captacao_encerrar(p_telefone text, p_motivo text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  l        captacao_leads;
  v_motivo text := lower(coalesce(nullif(btrim(p_motivo), ''), 'concluido'));
  v_ultima text;
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_telefone);
  IF l.id IS NULL THEN
    RETURN 'não encerrei: número fora da lista.';
  END IF;

  SELECT texto INTO v_ultima FROM captacao_mensagens
   WHERE lead_id = l.id AND direcao = 'recebida' ORDER BY id DESC LIMIT 1;

  -- A PAREDE (Tel, 15/09). Numero errado e quem pediu para sair passam direto;
  -- todo o resto ouve a pergunta dos outros imoveis antes do fim.
  IF v_motivo <> 'numero_errado'
     AND NOT captacao_pediu_para_sair(v_ultima)
     AND NOT captacao_ja_perguntou_outros(l.id) THEN
    UPDATE captacao_leads SET etapa = 'aguardando_outros', atualizado_em = now() WHERE id = l.id;
    RETURN 'ainda NAO encerrei. Antes de terminar, falta perguntar dos outros imoveis. '
        || 'Diga exatamente isto, e nada mais: "' || captacao_frase_outros(l.id) || '"'
        || ' Quando ele responder, ai sim chame encerrar_conversa.';
  END IF;

  UPDATE captacao_leads
     SET status = 'concluido',
         etapa = 'concluido',
         pergunta_pendente = NULL,
         opt_out = CASE WHEN v_motivo IN ('opt_out', 'numero_errado') THEN true ELSE opt_out END,
         motivo_fim = v_motivo,
         fechado_em = now(),
         atualizado_em = now()
   WHERE id = l.id;
  RETURN 'conversa encerrada. despeça-se em uma linha curta e não faça mais perguntas.';
END;
$$;

COMMENT ON FUNCTION captacao_encerrar(text, text) IS
  'Encerra o lead da captacao. RECUSA encerrar enquanto a pergunta dos outros imoveis nao tiver saido (Tel, 15/09), exceto numero errado e quem pediu para sair.';
