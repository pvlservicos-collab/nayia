-- =====================================================================
-- NAI -- 23: comandos do WhatsApp do Tel (Tel, 15/09/2026)
--
-- Ele: "coloca função para o tel poder cancelar uma visita pelo whatsapp, e
-- parar o atendimento da nay geral com um comando especifico" ... "ou remarcar
-- uma visita manualmente pelo whatsapp dele, funções unicas do whatsapp do
-- tel".
--
-- O QUE JA EXISTIA e continua igual: `VISITA <id> CANCELA` -- cancela, avisa o
-- corretor e avisa o Fernando. Nao foi tocado.
--
-- O QUE NASCE AQUI:
--   VISITA <id> REMARCA <quando>   muda a hora DIRETO e avisa todo mundo
--   PARAR ATENDIMENTO              a NAI para de responder qualquer pessoa
--   VOLTAR ATENDIMENTO             volta a atender
--
-- REMARCA nao e a mesma coisa que o HORARIO que ja existia: o HORARIO
-- PERGUNTA ao corretor se o novo horario serve (e a negociacao vinda do
-- proprietario); o REMARCA e decisao do Tel -- muda e comunica.
--
-- PARAR ATENDIMENTO e a chave geral `pausada`, que sempre existiu e so se
-- mexia por UPDATE no banco. Ela nao apaga nem perde nada: as mensagens
-- continuam chegando e ficam gravadas, ela e que nao responde.
-- =====================================================================

-- O texto e um comando de parada?
CREATE OR REPLACE FUNCTION nai_e_comando_parada(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  -- Duas palavras de proposito: "parar" sozinho e palavra comum demais para
  -- desligar o atendimento inteiro sem querer.
  -- Parenteses em volta da concatenacao: `~*` e `||` tem a mesma precedencia,
  -- e sem eles isto vira (p ~* 'A') || 'B' -- que devolve texto, nao boolean.
  SELECT coalesce(p, '') ~* ('^\s*(@?nay[\s,:;.!-]*)?(parar|pausar|parada|voltar|retomar|volta)\s+'
                           || '(o\s+)?(atendimento|atender)\s*[.!]?\s*$');
$$;

-- Comando de parada que MANDA PARAR (o contrario volta a atender).
CREATE OR REPLACE FUNCTION nai_parada_e_para(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(p, '') ~* '^\s*(@?nay[\s,:;.!-]*)?(parar|pausar|parada)\s';
$$;

-- Todo comando que NAO estava na gramatica original do Tel. Fica em uma
-- funcao so para o cabecalho do turno e o roteador perguntarem uma coisa
-- unica -- e para a proxima nao precisar mexer em dois lugares.
CREATE OR REPLACE FUNCTION nai_e_comando_extra(p text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT nai_e_comando_agenda(p) OR nai_e_comando_parada(p);
$$;

COMMENT ON FUNCTION nai_e_comando_extra(text) IS
  'Comandos acrescentados depois da gramatica original: AGENDA DE VISITAS, PARAR/VOLTAR ATENDIMENTO. Tel, 15/09.';
