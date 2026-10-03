-- 285 (03/10/2026): A LISTA DA AGENDA PODE TER O TEXTO EDITADO À MÃO (a coluna).
--
-- Pedro, 03/10: "quero também lá na página de agenda que crie, no criar mensagem, lista de imóveis, e editar essa
-- mensagem fisicamente: hoje tu só edita horários". As funções estão na 286; aqui fica só a coluna, sozinha, para
-- a troca de esquema não esperar o ensaio das funções (o disparo da grade lê `vagas` todo minuto).
-- Vazio = a lista é montada na hora do envio, como sempre. Preenchido = sai o texto escrito no site; o publicador só
-- tira, na hora, a linha de imóvel que saiu do mercado e a que o grupo não aceita.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE vagas ADD COLUMN IF NOT EXISTS texto_fixo text;
COMMENT ON COLUMN vagas.texto_fixo IS
  'Vaga de LISTA com o texto editado à mão no site (285). NULL = a lista é montada na hora do envio (nay_lista_de_imoveis).';
ALTER TABLE vagas DROP CONSTRAINT IF EXISTS vagas_texto_fixo_so_de_lista;
ALTER TABLE vagas ADD CONSTRAINT vagas_texto_fixo_so_de_lista
  CHECK (texto_fixo IS NULL OR (categoria IS NOT NULL AND length(texto_fixo) <= 20000));

COMMIT;
