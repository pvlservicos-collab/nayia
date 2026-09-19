-- =====================================================================
-- NAI -- 41: o acompanhante das visitas vem do CADASTRO (Tel, 16/09/2026)
--
-- Ele: "o Fernando saiu da equipe, agora entrou o André; troque todas as etapas
-- do fluxo que iriam para o Fernando para o motoboy André +55 92 8144-5964".
--
-- O NOME ESTAVA ESCRITO A MAO em 19 funcoes e ~45 lugares -- em recado ao
-- corretor ("O Fernando te encontra lá"), ao proprietario ("a senha fica só com
-- o Fernando"), ao proprio acompanhante ("Fernando, a visita do...") e nos
-- cards ao Tel. Trocar tudo por "André" resolveria HOJE e deixaria a mesma
-- armadilha montada para a proxima troca.
--
-- Aqui o nome passa a vir do cadastro: `nai_acompanhante()` devolve o primeiro
-- nome de quem esta ativo em `equipe`. Trocar de acompanhante volta a ser o que
-- devia ser desde sempre -- duas linhas de UPDATE, sem tocar em funcao nenhuma.
-- =====================================================================

-- ------------------------------------------------- o cadastro: quem acompanha
-- O Fernando sai (fica no historico, nao e apagado) e o André entra.
UPDATE equipe SET ativo = false
 WHERE papel = 'acompanhante' AND nome ILIKE '%Fernando%';

INSERT INTO equipe (telefone, nome, papel, ativo)
VALUES ('5592981445964', 'André', 'acompanhante', true)
ON CONFLICT (telefone) DO UPDATE
   SET nome = EXCLUDED.nome, papel = EXCLUDED.papel, ativo = true;

-- --------------------------------------------------------- o nome, do cadastro
-- Primeiro nome, que e como ela fala com ele e como fala DELE ao corretor.
-- Sem acompanhante ativo devolve 'a nossa equipe', que e uma frase que continua
-- fazendo sentido na mensagem: "quem acompanha a visita é a nossa equipe".
CREATE OR REPLACE FUNCTION nai_acompanhante()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    (SELECT split_part(btrim(e.nome), ' ', 1)
       FROM equipe e
      WHERE e.papel = 'acompanhante' AND e.ativo
      ORDER BY e.criado_em DESC LIMIT 1),
    'a nossa equipe');
$$;

COMMENT ON FUNCTION nai_acompanhante() IS
  'Primeiro nome de quem acompanha as visitas hoje, lido de `equipe`. Trocar de pessoa e um UPDATE. Tel, 16/09.';

-- E o mesmo em MAIUSCULA, para as etiquetas do modo teste.
CREATE OR REPLACE FUNCTION nai_acompanhante_maiusculo()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT upper(nai_acompanhante());
$$;
