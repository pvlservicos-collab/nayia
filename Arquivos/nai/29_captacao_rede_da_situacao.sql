-- =====================================================================
-- CAPTACAO -- 29: a rede que grava a situacao quando a IA nao grava
--                 (Tel, 15/09/2026)
--
-- O Sr. Helio escreveu "Ele foi vendido" e o lead ficou em
-- `aguardando_situacao` com `situacao` VAZIA: o modelo respondeu, mas nao
-- chamou `guardar_situacao`. Medido em todo o historico: de 36 pessoas que
-- disseram vendido ou alugado, 2 ficaram sem registro. Nao e sistematico --
-- e por isso mesmo passa despercebido, e o imovel segue no cadastro como se
-- ninguem tivesse falado nada.
--
-- A rede e um gatilho na mensagem RECEBIDA, e nao depende do modelo. Ela e
-- deliberadamente ESTREITA:
--   * so age quando a frase e clara ("foi vendido", "esta alugado");
--   * NAO age se houver negacao perto ("nao foi vendido", "ainda nao aluguei");
--   * NAO sobrescreve situacao ja gravada -- se a IA gravou, a dela vale;
--   * so avanca a etapa se ela ainda estiver em `aguardando_situacao`, que e
--     exatamente o caso em que a IA nao gravou.
--
-- `situacao_por` guarda quem gravou, para dar para medir depois quantas vezes
-- a rede precisou entrar.
-- =====================================================================

ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS situacao_por text;
COMMENT ON COLUMN captacao_leads.situacao_por IS
  'Quem gravou a situacao: NULL/ia = a ferramenta do agente; rede = o gatilho de 15/09, quando a IA nao gravou.';

-- O que a frase diz, ou NULL quando nao da para ter certeza.
CREATE OR REPLACE FUNCTION captacao_situacao_dita(p_texto text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE s text := lower(unaccent(coalesce(p_texto, '')));
BEGIN
  -- NEGACAO perto da palavra derruba tudo: "nao foi vendido", "ainda nao
  -- aluguei", "nao esta alugado". Preferimos nao gravar a gravar errado.
  IF s ~ ('\m(nao|ainda nao|nunca)\M[^.!?]{0,24}\m(vendid|vendi|alugad|locad|aluguei)') THEN
    RETURN NULL;
  END IF;
  IF s ~ ('\m(vendid[oa]|ja vendi|vendi (a|o|esse|este|meu)\M)') THEN
    RETURN 'vendido';
  END IF;
  IF s ~ ('\m(alugad[oa]|locad[oa]|ja aluguei|esta locado|esta alugado)\M') THEN
    RETURN 'alugado';
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION captacao_rede_da_situacao()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_sit text;
BEGIN
  IF NEW.direcao <> 'recebida' OR NEW.lead_id IS NULL THEN RETURN NEW; END IF;
  v_sit := captacao_situacao_dita(NEW.texto);
  IF v_sit IS NULL THEN RETURN NEW; END IF;

  UPDATE captacao_leads l
     SET situacao = v_sit,
         situacao_por = 'rede',
         -- A etapa so anda quando ela estava PARADA esperando isto. Se a
         -- conversa ja passou desse ponto, a rede grava o dado e nao mexe no
         -- rumo da conversa.
         etapa = CASE WHEN l.etapa = 'aguardando_situacao' AND v_sit = 'vendido'
                        THEN 'aguardando_outros'
                      WHEN l.etapa = 'aguardando_situacao' AND v_sit = 'alugado'
                        THEN 'aguardando_prazo'
                      ELSE l.etapa END,
         atualizado_em = now()
   WHERE l.id = NEW.lead_id
     AND l.situacao IS NULL;   -- o que a IA gravou nunca e sobrescrito
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS captacao_rede_da_situacao_tg ON captacao_mensagens;
CREATE TRIGGER captacao_rede_da_situacao_tg
AFTER INSERT ON captacao_mensagens
FOR EACH ROW EXECUTE FUNCTION captacao_rede_da_situacao();
