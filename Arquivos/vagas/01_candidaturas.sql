-- =====================================================================
-- VAGAS -- 01: candidaturas da página /vagas-manaus (Tel, 21/09/2026)
--
-- Ele: "uma página com um video do que precisamos e uma descrição do que é
-- a vaga com um formulário, a vaga é de SDR ... e cria no painel uma nova
-- página no menu Vagas com uma tabela com os dados dessa pessoa, acrescente
-- um campo de subir currículo".
--
-- POR QUE UM SCHEMA PRÓPRIO, E NÃO O `public` COMO O RESTO:
-- a API do site não tem senha, e existe a rota /api/tabelas/<nome>, que
-- lista TODA tabela do schema public e faz SELECT * nela pela role
-- nay_leitura. E o banco dá a nay_leitura leitura AUTOMÁTICA em toda tabela
-- nova do public (ALTER DEFAULT PRIVILEGES). Uma tabela de candidatos criada
-- no public estaria aberta para qualquer um na internet no minuto seguinte,
-- com nome, WhatsApp, e-mail e o currículo.
-- No schema `vagas` ela não aparece nessa lista, não herda aquela permissão,
-- e só as duas roles abaixo enxergam alguma coisa.
--
-- QUEM PODE O QUÊ:
--   nay_site_escrita  -> só INSERE (o formulário público). Lê só ip e data,
--                        para frear quem mandar a mesma coisa em rajada.
--   nay_site_leitura  -> só LÊ (o painel, atrás da senha do admin).
-- Ninguém edita nem apaga pela API. Apagar candidato é à mão, no banco.
--
-- O currículo fica no próprio banco (bytea), não numa pasta do servidor:
-- assim ele só sai pela rota que confere a senha, e entra no backup do banco
-- junto com o resto. Teto de 5 MB por arquivo.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS vagas AUTHORIZATION nay;
REVOKE ALL ON SCHEMA vagas FROM PUBLIC;

CREATE TABLE IF NOT EXISTS vagas.candidaturas (
  id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vaga                    text NOT NULL DEFAULT 'sdr-manaus'
                            CHECK (vaga ~ '^[a-z0-9-]{3,40}$'),
  nome                    text NOT NULL CHECK (length(btrim(nome)) BETWEEN 3 AND 120),
  whatsapp                text NOT NULL CHECK (whatsapp ~ '^[0-9]{10,13}$'),
  email                   text NOT NULL CHECK (length(email) <= 160
                                              AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  bairro                  text CHECK (length(bairro) <= 80),
  experiencia_vendas      text NOT NULL CHECK (experiencia_vendas IN
                            ('nenhuma', 'menos_de_1_ano', '1_a_3_anos', 'mais_de_3_anos')),
  experiencia_imobiliaria text NOT NULL CHECK (experiencia_imobiliaria IN ('sim', 'nao')),
  disponibilidade         text NOT NULL CHECK (disponibilidade IN ('imediata', '15_dias', '30_dias')),
  pretensao_salarial      text CHECK (length(pretensao_salarial) <= 40),
  linkedin                text CHECK (length(linkedin) <= 200),
  por_que                 text CHECK (length(por_que) <= 2000),
  curriculo_nome          text NOT NULL CHECK (length(curriculo_nome) BETWEEN 1 AND 160),
  curriculo_tipo          text NOT NULL CHECK (curriculo_tipo IN (
                            'application/pdf',
                            'application/msword',
                            'application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  curriculo               bytea NOT NULL CHECK (octet_length(curriculo) BETWEEN 1 AND 5242880),
  consentimento_em        timestamptz NOT NULL,
  ip                      text CHECK (length(ip) <= 64),
  criada_em               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS candidaturas_criada_idx ON vagas.candidaturas (criada_em DESC);
CREATE INDEX IF NOT EXISTS candidaturas_ip_idx ON vagas.candidaturas (ip, criada_em DESC);

-- Nada herdado: começa fechado e abre só o necessário.
REVOKE ALL ON vagas.candidaturas FROM PUBLIC;
REVOKE ALL ON vagas.candidaturas FROM nay_leitura, nay_site_conteudo, nay_site_listas, nay_site_nai;

-- O formulário: insere, e enxerga só o que precisa para o freio de rajada.
GRANT USAGE ON SCHEMA vagas TO nay_site_escrita;
GRANT INSERT (vaga, nome, whatsapp, email, bairro, experiencia_vendas,
              experiencia_imobiliaria, disponibilidade, pretensao_salarial,
              linkedin, por_que, curriculo_nome, curriculo_tipo, curriculo,
              consentimento_em, ip)
  ON vagas.candidaturas TO nay_site_escrita;
GRANT SELECT (ip, criada_em) ON vagas.candidaturas TO nay_site_escrita;

-- O painel: só lê.
GRANT USAGE ON SCHEMA vagas TO nay_site_leitura;
GRANT SELECT ON vagas.candidaturas TO nay_site_leitura;

COMMIT;

-- Prova das paredes: quem enxerga o quê.
SELECT r.rolname,
       has_table_privilege(r.rolname, 'vagas.candidaturas', 'SELECT') AS le_tudo,
       has_table_privilege(r.rolname, 'vagas.candidaturas', 'INSERT') AS insere,
       has_table_privilege(r.rolname, 'vagas.candidaturas', 'UPDATE') AS edita,
       has_table_privilege(r.rolname, 'vagas.candidaturas', 'DELETE') AS apaga
  FROM pg_roles r
 WHERE r.rolname IN ('nay_leitura', 'nay_site_leitura', 'nay_site_escrita',
                     'nay_site_conteudo', 'nay_site_listas', 'nay_site_nai')
 ORDER BY 1;
