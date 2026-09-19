-- Fluxos de mensagem editados no admin (pagina "Fluxo de mensagens").
--
-- O editor e um canvas de cards e ligacoes. Antes vivia so no navegador:
-- a unica forma de guardar era baixar uma copia do HTML. Agora a versao
-- oficial fica aqui, e todo aparelho que abre a pagina ve a mesma.
--
-- `versao` e a trava contra sobrescrita: quem salva manda a versao que
-- carregou, e se outro aparelho salvou no meio o PUT volta 409 em vez de
-- apagar o trabalho do outro em silencio.

BEGIN;

CREATE TABLE IF NOT EXISTS site_fluxos (
  nome            text PRIMARY KEY,
  conteudo        jsonb NOT NULL,
  versao          integer NOT NULL DEFAULT 1,
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  atualizado_por  text,
  CONSTRAINT site_fluxos_nome_ok CHECK (nome ~ '^[a-z0-9_-]{1,40}$')
);

-- Uma linha por salvamento. E o que permite desfazer um "Atualizar fluxo"
-- feito por cima -- sem isto, apagar os cards e salvar seria definitivo.
-- Sem tela de restauracao por enquanto: volta por SQL.
CREATE TABLE IF NOT EXISTS site_fluxos_historico (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nome       text NOT NULL,
  versao     integer NOT NULL,
  conteudo   jsonb NOT NULL,
  salvo_em   timestamptz NOT NULL DEFAULT now(),
  salvo_por  text
);
CREATE INDEX IF NOT EXISTS site_fluxos_historico_idx
  ON site_fluxos_historico (nome, versao DESC);

-- Mesma role do quadro "Proximos passos": conteudo do proprio site, nao
-- dado de negocio. Nenhum outro grant alem destas duas tabelas.
GRANT SELECT, INSERT, UPDATE ON site_fluxos TO nay_site_conteudo;
GRANT SELECT, INSERT, DELETE ON site_fluxos_historico TO nay_site_conteudo;
GRANT USAGE ON SEQUENCE site_fluxos_historico_id_seq TO nay_site_conteudo;

COMMIT;
