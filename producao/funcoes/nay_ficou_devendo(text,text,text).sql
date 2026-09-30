CREATE OR REPLACE FUNCTION public.nay_ficou_devendo(p_telefone text, p_codigo text, p_motivo text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_tel text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_cod text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
BEGIN
  IF v_cod IS NULL OR v_tel = '' THEN
    RETURN 'sem codigo ou telefone, nao registrei nada.';
  END IF;

  -- O CODIGO TEM QUE TER VINDO DO CORRETOR. Sem isto, o modelo inventa um
  -- codigo (foi o que fez em 01/09, passando 5717 numa pergunta sobre o
  -- 4946), a divida nasce do imovel errado e o cron entrega o card errado
  -- sozinho, de madrugada, sem ninguem revisar. Ver codigo_confirmado.sql.
  IF nay_codigo_confirmado(p_telefone, v_cod) = 'nao' THEN
    RETURN 'esse corretor nao pediu o imovel ' || v_cod || ' e voce nao mandou '
        || 'esse card para ele. NAO registrei divida nenhuma: pergunte a ele de '
        || 'qual imovel esta falando antes de anotar.';
  END IF;

  -- Imovel que saiu do mercado nao vira divida.
  IF NOT EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo::text = v_cod AND coalesce(i.disponivel, true)) THEN
    RETURN 'o imovel ' || v_cod || ' nao esta disponivel, nao registrei divida.';
  END IF;

  -- IMOVEL DE PARCEIRO NAO VAI PELO CRON. `imovel_por_codigo` mostra so o
  -- nome do condominio e avisa que e de parceria -- sem bairro, sem valor,
  -- sem foto. O cron nao passa por ali: ele le o site AO VIVO e manda card
  -- cheio com todas as fotos, furando a reducao inteira. E sao 909 dos
  -- 1.208 disponiveis, 75% do catalogo. Achado na auditoria de 01/09.
  IF EXISTS (SELECT 1 FROM imoveis i
              WHERE i.codigo::text = v_cod AND coalesce(i.e_parceiro, false)) THEN
    RETURN 'o imovel ' || v_cod || ' e de parceria: nao registrei divida porque '
        || 'a entrega automatica mandaria o card completo. Responda agora na '
        || 'conversa com imovel_por_codigo, que mostra o que pode ser mostrado '
        || 'de imovel de parceiro.';
  END IF;

  -- Já mandou nas últimas 12h: não é dívida.
  IF EXISTS (SELECT 1 FROM envios e
              WHERE e.codigo = v_cod AND e.destino = 'corretor'
                AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = right(v_tel,8)
                AND e.enviado_em > now() - interval '12 hours') THEN
    RETURN 'esse imovel ja foi para ele hoje, nao registrei.';
  END IF;

  INSERT INTO entrega_pendente (telefone, codigo, motivo)
  VALUES (v_tel, v_cod, left(coalesce(p_motivo,''), 200))
  ON CONFLICT (telefone, codigo) WHERE estado = 'devendo' DO NOTHING;

  RETURN 'anotei que devo o imovel ' || v_cod || ' a esse corretor.';
END;
$function$;
