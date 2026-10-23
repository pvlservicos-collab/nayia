-- 478 -- Os PERFIS da Nay do número oficial (nay-captacao): cada lista tem a sua Nay, e trocar de lista é trocar o perfil
--
-- Pedro, 23/10/2026: "a nay hoje de atendimento na api oficial está setada para donos, sempre que tô disparando tô pedindo
-- mudanças nessa nay, salva o estado dela como uma nay ligada a lista de proprietários, e eu vou pedir mudanças depois
-- para ela atender corretores, e aí vai ficar salva essa dos corretores, e quando eu for mudar de lista só troca o modelo
-- da nay. Implementa essa gestão de modelos."
--
-- Um perfil = o prompt vivo (nai_prompt, pelo papel) + o roteiro do código (os acréscimos de cada lista no nay-captacao;
-- 'proprietarios' é o de hoje: captacao/modelo.py, com as campanhas alugado/vendido/removido). Fica guardado o RETRATO
-- do prompt no dia em que o perfil foi salvo: mudança pedida para a Nay dos corretores vai para o papel dela e não mexe
-- na dos donos.
-- - captacao_config.nay_perfil_ativo: o perfil que o disparo carimba no lead quando manda o modelo;
-- - captacao_leads.perfil_nay: a Nay daquele lead. Quem já está conversando segue com a Nay com que foi chamado,
--   mesmo depois de trocar o ativo. NULL = proprietarios (todos os leads de antes desta migração são donos).
-- Trocar: SELECT captacao_nay_perfil_trocar('corretores');   Ver: SELECT * FROM captacao_nay_perfis();
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS captacao_nay_perfil (
  nome           text PRIMARY KEY CHECK (nome ~ '^[a-z][a-z0-9_]*$'),
  descricao      text NOT NULL DEFAULT '',
  listas         text NOT NULL DEFAULT '',          -- para quais listas é esta Nay (texto livre, para a tela)
  prompt_papel   text NOT NULL,                     -- nai_prompt.papel do prompt vivo desta Nay
  roteiro        text NOT NULL,                     -- o roteiro do código (nay-captacao/captacao/atender.py, ROTEIROS)
  prompt_retrato text,                              -- o prompt como estava quando o perfil foi salvo
  prompt_versao  integer,
  salvo_em       timestamptz NOT NULL DEFAULT now(),
  salvo_por      text
);
COMMENT ON TABLE captacao_nay_perfil IS '478: os perfis da Nay do número oficial. Um por lista (proprietarios, corretores...). O ativo está em captacao_config.nay_perfil_ativo; o de cada lead em captacao_leads.perfil_nay.';
GRANT SELECT, INSERT, UPDATE ON captacao_nay_perfil TO nay;
GRANT SELECT ON captacao_nay_perfil TO nay_leitura, nay_site_leitura;

ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS perfil_nay text REFERENCES captacao_nay_perfil (nome);
COMMENT ON COLUMN captacao_leads.perfil_nay IS '478: a Nay (perfil) que atende este lead, carimbada pelo disparo com o perfil ativo. NULL = proprietarios.';

INSERT INTO captacao_nay_perfil (nome, descricao, listas, prompt_papel, roteiro, prompt_retrato, prompt_versao, salvo_por)
SELECT 'proprietarios',
       'A Nay dos donos: situação do imóvel cadastrado, contrato, outro imóvel, ficha do imóvel novo, indicação e honorários. Campanhas alugado (lista 5), vendido (lista 4) e removido (lista 3).',
       'Donos de imóvel: listas 3, 4, 5, 6, 7, 8 e a lista de vencimento',
       'captacao', 'proprietarios', p.texto, p.versao, 'Pedro 23/10 (478): o estado de hoje'
  FROM nai_prompt p WHERE p.papel = 'captacao'
ON CONFLICT (nome) DO NOTHING;

INSERT INTO captacao_config (chave, valor) VALUES ('nay_perfil_ativo', 'proprietarios')
ON CONFLICT (chave) DO NOTHING;

-- o perfil de um lead: o carimbado, ou proprietarios
CREATE OR REPLACE FUNCTION public.captacao_nay_perfil_do_lead(p_telefone text)
 RETURNS TABLE (nome text, prompt_papel text, roteiro text, prompt text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.nome, p.prompt_papel, p.roteiro, nai_prompt_de(p.prompt_papel)
    FROM captacao_nay_perfil p
   WHERE p.nome = coalesce((SELECT l.perfil_nay FROM captacao_leads l
                             WHERE l.telefone_chave = nay_fone_chave(p_telefone) ORDER BY l.id DESC LIMIT 1),
                           'proprietarios');
$function$;

-- troca o perfil ativo (o que o disparo carimba daqui para frente)
CREATE OR REPLACE FUNCTION public.captacao_nay_perfil_trocar(p_nome text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_antes text := (SELECT valor FROM captacao_config WHERE chave = 'nay_perfil_ativo');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM captacao_nay_perfil WHERE nome = p_nome) THEN
    RETURN 'não existe o perfil ' || coalesce(p_nome, '(vazio)') || '. Os que existem: ' ||
           (SELECT string_agg(nome, ', ' ORDER BY nome) FROM captacao_nay_perfil);
  END IF;
  UPDATE captacao_config SET valor = p_nome WHERE chave = 'nay_perfil_ativo';
  RETURN 'perfil ativo: ' || p_nome || ' (antes: ' || coalesce(v_antes, 'nenhum') ||
         '). Quem já foi chamado segue com a Nay com que foi chamado.';
END $function$;

-- salva (ou atualiza) um perfil, com o retrato do prompt de agora
CREATE OR REPLACE FUNCTION public.captacao_nay_perfil_salvar(p_nome text, p_prompt_papel text, p_roteiro text,
                                                             p_descricao text DEFAULT '', p_listas text DEFAULT '',
                                                             p_por text DEFAULT NULL)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v nai_prompt;
BEGIN
  SELECT * INTO v FROM nai_prompt WHERE papel = p_prompt_papel;
  IF v.papel IS NULL THEN RETURN 'não existe o prompt ' || coalesce(p_prompt_papel, '(vazio)') || ' em nai_prompt'; END IF;
  INSERT INTO captacao_nay_perfil (nome, descricao, listas, prompt_papel, roteiro, prompt_retrato, prompt_versao, salvo_por)
  VALUES (p_nome, coalesce(p_descricao, ''), coalesce(p_listas, ''), p_prompt_papel, p_roteiro, v.texto, v.versao, p_por)
  ON CONFLICT (nome) DO UPDATE SET descricao = EXCLUDED.descricao, listas = EXCLUDED.listas,
         prompt_papel = EXCLUDED.prompt_papel, roteiro = EXCLUDED.roteiro, prompt_retrato = EXCLUDED.prompt_retrato,
         prompt_versao = EXCLUDED.prompt_versao, salvo_em = now(), salvo_por = EXCLUDED.salvo_por;
  RETURN 'perfil ' || p_nome || ' salvo com o prompt ' || p_prompt_papel || ' v' || v.versao;
END $function$;

-- a lista para a tela e para conferir
CREATE OR REPLACE FUNCTION public.captacao_nay_perfis()
 RETURNS TABLE (nome text, ativo boolean, descricao text, listas text, prompt_papel text, prompt_versao_salva integer,
                prompt_versao_viva integer, roteiro text, leads bigint, salvo_em timestamptz)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.nome, p.nome = (SELECT valor FROM captacao_config WHERE chave = 'nay_perfil_ativo'), p.descricao, p.listas,
         p.prompt_papel, p.prompt_versao, (SELECT n.versao FROM nai_prompt n WHERE n.papel = p.prompt_papel), p.roteiro,
         (SELECT count(*) FROM captacao_leads l WHERE coalesce(l.perfil_nay, 'proprietarios') = p.nome), p.salvo_em
    FROM captacao_nay_perfil p ORDER BY p.nome;
$function$;

GRANT EXECUTE ON FUNCTION public.captacao_nay_perfil_do_lead(text), public.captacao_nay_perfis() TO nay, nay_leitura;
GRANT EXECUTE ON FUNCTION public.captacao_nay_perfil_trocar(text),
                          public.captacao_nay_perfil_salvar(text, text, text, text, text, text) TO nay;

COMMIT;
