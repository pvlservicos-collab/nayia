-- 289 (03/10/2026): MARCAR VENDIDO (OU ALUGADO) NO EDITAR IMÓVEL DAVA ERRO DE PERMISSÃO.
--
-- Pedro, 03/10: "quando coloca o status vendido aparece essa mensagem, dá um erro, de acesso, privilégio".
--
-- A CAUSA. O gatilho `imoveis_aviso_de_saida` (28/09) enfileira em `aviso_de_saida` todo imóvel que sai do
-- mercado, "venha por onde vier", para o cron `avisar_saidas.sh` avisar no grupo IMÓVEIS PARA ANUNCIAR EASY. A
-- função do gatilho roda com o papel de QUEM faz o UPDATE, e o site grava como `nay_site_escrita`, que não tem
-- permissão em `aviso_de_saida`: "permission denied for table aviso_de_saida". O UPDATE inteiro caía -- o imóvel
-- disponível não saía do mercado pelo site de jeito nenhum. A última saída registrada era de 29/09 10:30.
--
-- O QUE MUDA
--   1. SECURITY DEFINER: a anotação da fila não depende da permissão de quem mexeu no imóvel. O papel do site
--      continua sem acesso direto à tabela.
--   2. A PALAVRA CERTA. O motivo ia sempre NULO e o leitor (`nay_saidas_a_avisar`) completava com "alugado": o
--      imóvel VENDIDO pelo site sairia no grupo como "alugado", com o valor da locação. Agora o motivo vem da
--      situação: Vendido -> 'vendido', Alugado -> 'alugado'. `motivo_bloqueio`, quando existe, continua valendo.
--   3. CADASTRO NÃO É SAÍDA DO MERCADO. Rascunho, Em revisão e Excluído são arrumação de cadastro: não vão para a
--      fila (iriam ao grupo como "alugado"). Arquivado, Removido e Indisponível vão, com a palavra 'indisponível'.
--
-- Consequência a saber: marcar Vendido ou Alugado no site passa a AVISAR O GRUPO EASY em até um minuto, que é a
-- regra do Tel de 28/09 e só não acontecia porque o salvar caía antes.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nay_enfileirar_aviso_de_saida()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_motivo text;
BEGIN
  IF coalesce(OLD.disponivel, true) AND NOT coalesce(NEW.disponivel, true) THEN
    -- 289: rascunho, revisão e excluído são cadastro, não mercado: o grupo não precisa saber
    IF NEW.motivo_bloqueio IS NULL AND NEW.status IN ('Rascunho', 'Em revisão', 'Revisão', 'Excluído') THEN
      RETURN NEW;
    END IF;
    -- 289: a palavra do aviso sai da situação (antes ia nulo, e o leitor dizia "alugado" para tudo)
    v_motivo := coalesce(NEW.motivo_bloqueio,
                         CASE NEW.status WHEN 'Vendido' THEN 'vendido'
                                         WHEN 'Alugado' THEN 'alugado'
                                         WHEN 'Arquivado' THEN 'indisponível'
                                         WHEN 'Removido' THEN 'indisponível'
                                         WHEN 'Indisponível' THEN 'indisponível' END);
    INSERT INTO aviso_de_saida (codigo, motivo, marcado_em, avisado_em, erro)
    VALUES (NEW.codigo::text, v_motivo, now(), NULL, NULL)
    ON CONFLICT (codigo) DO UPDATE
       SET motivo = excluded.motivo, marcado_em = now(),
           avisado_em = NULL, erro = NULL;
  END IF;
  RETURN NEW;
END;
$function$;

COMMIT;
