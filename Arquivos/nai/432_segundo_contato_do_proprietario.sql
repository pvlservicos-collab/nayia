-- 432 (Pedro, 20/10/2026): "coloca uma segunda opção de contato aqui, a gente clica no + e aparece outra opção para
-- cadastro ... lá no editar proprietário do imóvel". Outros contatos do PROPRIETÁRIO (o cônjuge, um filho, o
-- administrador): nome, telefone e quem é. Valem para todos os imóveis dele, como o resto do cadastro do dono.
-- Tabela à parte: o telefone principal continua em proprietarios.telefone (é por ele que a Nay fala com o dono) e
-- nada muda na tabela proprietarios, que a Nay lê a toda hora.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.proprietario_contato (
  id              bigserial PRIMARY KEY,
  proprietario_id integer NOT NULL REFERENCES public.proprietarios (id) ON DELETE CASCADE,
  ordem           integer NOT NULL DEFAULT 1,
  nome            text,
  telefone        text,
  quem_e          text,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  CHECK (nullif(btrim(coalesce(nome, '')), '') IS NOT NULL OR nullif(btrim(coalesce(telefone, '')), '') IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS proprietario_contato_dono ON privado.proprietario_contato (proprietario_id, ordem);
COMMENT ON TABLE privado.proprietario_contato IS
  '432: outros contatos do proprietário (o botão + do cartão Proprietário no Editar imóvel). O principal é proprietarios.telefone.';

GRANT SELECT, INSERT, UPDATE, DELETE ON privado.proprietario_contato TO nay_site_escrita;
GRANT USAGE ON SEQUENCE privado.proprietario_contato_id_seq TO nay_site_escrita;
GRANT SELECT ON privado.proprietario_contato TO nay_leitura;

COMMIT;
