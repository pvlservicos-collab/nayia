-- =====================================================================
-- NAI -- 99e: a mente gruda na conversa (Tel, 22/09/2026)
--
-- ACHADO NO PRIMEIRO TESTE DE PONTA A PONTA, e e o MESMO bug do Luiz
-- Bastos entrando por outra porta:
--
--   ele:  "Oi Nay, tenho um apartamento no Living Comfort, se quiser te envio"
--   ela:  "Pode mandar sim! Me conta o que e: apartamento, casa ou outra
--          coisa?"                                    <- secretaria, certo
--   ele:  "E um apartamento"
--   ela:  "Certo! Qual a faixa de preco que seu cliente busca?"
--                                                     <- LOCACAO, errado
--   ele:  "E no Living Comfort, em Adrianopolis"
--   ela:  card do NOSSO 5664 + 11 fotos               <- o bug de novo
--
-- POR QUE: a mente decide mensagem a mensagem, sem saber o que ja estava
-- acontecendo. "E um apartamento", lido sozinho, e assunto de locacao -- e a
-- mente acertaria de novo se fosse so isso que ela visse.
--
-- A CORRECAO NAO E PEDIR PARA O MODELO LEMBRAR. E uma parede: enquanto houver
-- uma ficha de imovel ABERTA com essa pessoa, a conversa e da secretaria,
-- diga o modelo o que disser. A ficha so fecha quando o imovel sobe -- e ai a
-- mente volta a escolher livremente.
--
-- Mesma licao das outras paredes deste sistema (97, 92, 74): quando a
-- situacao esta gravada no banco, ela nao depende de o modelo lembrar.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_mente_registrar(p_turno bigint, p_atendente text,
                                                      p_motivo text, p_por text)
 RETURNS text LANGUAGE plpgsql
AS $function$
DECLARE v_at text; v_motivo text; v_contato bigint; v_ficha bigint;
BEGIN
  v_at := CASE WHEN lower(coalesce(p_atendente, '')) = 'secretaria' THEN 'secretaria' ELSE 'locacao' END;
  v_motivo := left(coalesce(p_motivo, ''), 300);

  SELECT contato_id INTO v_contato FROM nai_turno WHERE id = p_turno;

  -- A COLA: cadastro comecado e cadastro terminado.
  SELECT n.id INTO v_ficha
    FROM nai_imovel_novo n
   WHERE n.contato_id = v_contato AND n.situacao = 'colhendo'
     AND n.criado_em > now() - interval '24 hours'
   ORDER BY n.id DESC LIMIT 1;

  IF v_ficha IS NOT NULL AND nai_secretaria_ligada() THEN
    v_at := 'secretaria';
    v_motivo := 'cadastro em andamento (ficha ' || v_ficha || ')';
  END IF;

  -- Com a secretaria desligada, tudo continua indo para a locacao.
  IF v_at = 'secretaria' AND NOT nai_secretaria_ligada() THEN
    v_at := 'locacao';
    v_motivo := 'secretaria desligada';
  END IF;

  UPDATE nai_turno SET atendente = v_at WHERE id = p_turno;
  INSERT INTO nai_mente (turno_id, atendente, motivo, por)
       VALUES (p_turno, v_at, v_motivo,
               CASE WHEN v_ficha IS NOT NULL THEN 'cola' ELSE coalesce(p_por, 'mente') END);
  PERFORM nai_anotar(p_turno, 4, 'mente_mestra', 'mudou',
                     'quem responde: ' || v_at || coalesce(' (' || v_motivo || ')', ''));
  RETURN v_at;
END;
$function$;

-- A TELA PRECISA LER O QUE ELA DECIDIU. Só leitura: a página da Estrutura
-- mostra números, não muda nada. (Ver `tela-nao-chama-funcao-que-escreve`:
-- se um dia precisar de GRANT de escrita aqui, o desenho está errado.)
GRANT SELECT ON nai_mente, nai_saber, nai_imovel_novo, nai_imovel_novo_foto,
                pendencias TO nay_site_nai;
GRANT EXECUTE ON FUNCTION nai_imovel_novo_falta(bigint) TO nay_site_nai;

COMMIT;

SELECT 'quem pode ler nai_mente' AS o,
       string_agg(grantee, ', ') AS quem
  FROM information_schema.role_table_grants
 WHERE table_name = 'nai_mente' AND privilege_type = 'SELECT';
