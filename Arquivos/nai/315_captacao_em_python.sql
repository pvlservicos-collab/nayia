-- 315 (08/10/2026): A NAY DE CAPTAÇÃO COMEÇA A RODAR EM PYTHON, SÓ NO NÚMERO DO PEDRO.
-- Pedro: "prepara a nay captação para rodar no numero de api oficial, mas já
-- sabendo a resposta do modelo situacao_imovel_cadastrado_1 ... pode recriar a
-- nay de captação em python sem perder nada e testa para meu numero mandando o
-- modelo ... e quero mais uma pergunta no fluxo dela, se [ele] tem alguém que
-- esteja vendendo um imóvel para indicar, prepara isso mas por enquanto roda só
-- no meu numero".
--
-- COMO AS DUAS CONVIVEM, sem mexer no fluxo do n8n (que continua atendendo todo
-- mundo): a mensagem que chega continua entrando pelo fluxo antigo (webhook,
-- transcrição de áudio, foto na ficha, "Gravar na fila"). Um gatilho aqui troca o
-- status de entrada de 'Recebido' para 'Recebido py' quando o telefone está na
-- lista do Python (`captacao_config.python_telefones`). O fluxo antigo só reserva
-- 'Recebido', então ele não vê essas mensagens; quem as reserva é o serviço novo
-- (nay-captacao, no srv1894338). Tirar um número da lista devolve o número ao
-- fluxo antigo na mensagem seguinte.
--
-- O QUE NÃO MUDA: as regras continuam no banco. O serviço novo chama as MESMAS
-- ferramentas do fluxo (guardar_situacao, guardar_ficha, encerrar_conversa...),
-- lê o MESMO prompt (nai_prompt 'captacao') e passa pela mesma conferência
-- (captacao_ainda_e_da_ia) antes de cada balão.
--
-- A PERGUNTA NOVA: a indicação. Antes de encerrar, ela pergunta se a pessoa
-- conhece alguém que esteja vendendo um imóvel. É PAREDE, como a pergunta dos
-- outros imóveis: `captacao_indicacao_pendente` devolve a frase enquanto a
-- pergunta não saiu, e o serviço novo não encerra antes disso (menos opt_out e
-- número errado). Quem ele indicar fica em privado.captacao_indicacao (nome e
-- telefone de terceiro: schema privado).
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 1. QUEM É DO PYTHON --------------------------------------------------------
INSERT INTO captacao_config (chave, valor, nota)
VALUES ('python_telefones', '5596991712835',
        '315: telefones (separados por vírgula) que a Nay de captação em PYTHON atende no lugar do fluxo do n8n. Vazio = ninguém. "todos" = todos.')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.captacao_e_do_python(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((
    SELECT btrim(c.valor) = 'todos'
        OR nay_fone_chave(p_telefone) IN (SELECT nay_fone_chave(btrim(x)) FROM regexp_split_to_table(c.valor, '[,;\s]+') x WHERE btrim(x) <> '')
      FROM captacao_config c WHERE c.chave = 'python_telefones'), false);
$function$;

CREATE OR REPLACE FUNCTION public.captacao_mensagem_do_python()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.direcao = 'recebida' AND NEW.status = 'Recebido' AND captacao_e_do_python(NEW.telefone) THEN
    NEW.status := 'Recebido py';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS captacao_mensagem_do_python ON captacao_mensagens;
CREATE TRIGGER captacao_mensagem_do_python BEFORE INSERT ON captacao_mensagens
  FOR EACH ROW EXECUTE FUNCTION captacao_mensagem_do_python();

-- 2. A INDICAÇÃO -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS privado.captacao_indicacao (
  id        bigserial PRIMARY KEY,
  lead_id   bigint,
  telefone  text NOT NULL,          -- de quem indicou
  nome      text,                   -- o indicado
  contato   text,                   -- telefone do indicado, como a pessoa escreveu
  detalhe   text,                   -- o que ela disse do imóvel
  criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS captacao_indicacao_lead ON privado.captacao_indicacao (lead_id, criado_em DESC);
COMMENT ON TABLE privado.captacao_indicacao IS '315: quem o proprietário indicou na captação (alguém que está vendendo um imóvel)';

-- A frase da pergunta, enquanto ela não saiu nesta conversa. NULL = já perguntou.
CREATE OR REPLACE FUNCTION public.captacao_indicacao_pendente(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN EXISTS (
           SELECT 1 FROM captacao_mensagens m
            WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_telefone) AND m.direcao = 'enviada'
              AND m.texto ~* '\mindic(ar|a|ou|ando|a[cç][aã]o)\M' AND m.texto ~ '\?'
              -- desde o último disparo (campanha nova pergunta de novo). Pela ORDEM das mensagens, não pela
              -- hora: duas gravadas na mesma transação têm a mesma hora.
              AND m.id > coalesce((SELECT max(d.id) FROM captacao_mensagens d
                                    WHERE nay_fone_chave(d.telefone) = nay_fone_chave(p_telefone)
                                      AND d.direcao = 'enviada' AND d.origem = 'disparo'), 0))
         THEN NULL
         ELSE 'Para finalizar: conhece alguém que esteja vendendo um imóvel e que possa nos indicar?' END;
$function$;

-- A ferramenta `guardar_indicacao` do serviço novo.
CREATE OR REPLACE FUNCTION public.captacao_indicacao_guardar(p_telefone text, p_nome text, p_contato text, p_detalhe text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lead bigint;
BEGIN
  SELECT l.id INTO v_lead FROM captacao_leads l WHERE l.telefone_chave = nay_fone_chave(p_telefone);
  IF coalesce(btrim(p_nome), '') = '' AND coalesce(btrim(p_contato), '') = '' AND coalesce(btrim(p_detalhe), '') = '' THEN
    RETURN 'Nao gravei: faltou dizer quem e o indicado. Pergunte o nome e o telefone dele.';
  END IF;
  INSERT INTO privado.captacao_indicacao (lead_id, telefone, nome, contato, detalhe)
  VALUES (v_lead, p_telefone, left(nullif(btrim(p_nome), ''), 160), left(nullif(btrim(p_contato), ''), 80), left(nullif(btrim(p_detalhe), ''), 600));
  IF coalesce(regexp_replace(coalesce(p_contato, ''), '\D', '', 'g'), '') !~ '^\d{8,}' THEN
    RETURN 'Indicacao anotada, mas SEM telefone. Peca, em uma linha, o telefone do indicado. Se ele nao tiver ou nao quiser passar, agradeca e encerre.';
  END IF;
  RETURN 'Indicacao gravada. Agradeca em uma linha e encerre a conversa (encerrar_conversa, motivo concluido).';
END
$function$;
REVOKE ALL ON FUNCTION captacao_indicacao_guardar(text, text, text, text) FROM PUBLIC;
COMMIT;
