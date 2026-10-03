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
