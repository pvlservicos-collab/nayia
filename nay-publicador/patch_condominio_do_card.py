#!/usr/bin/env python3
"""Põe o nome do condomínio de volta no título do card.

O CASO (Tel, 24/09): o 5749 (sala no Soberane, Adrianópolis) foi para 16
grupos como "📍 Sala bairro Adrianópolis". Ele queria "📍 Soberane".

A CAUSA: o card lê a página AO VIVO e a página do 5749 não publica o campo de
condomínio -- devolve `condominio: None`. Quem sabe o nome é a TABELA
(`condominio_nome`), que a varredura preenche lendo a LISTAGEM. Duas fontes
para o mesmo dado, e o título usava só uma.

POR QUE ESTE ARQUIVO EXISTE em vez de um `scp`: o `publicador.py` do servidor
tem 37 linhas que não estão no git (a metadinha). Copiar por cima apagaria
trabalho em produção -- já quase aconteceu em 23/09. O patch é cirúrgico e
delimitado por marcador, então rodar duas vezes não empilha.

    python3 patch_condominio_do_card.py /root/nay-publicador/publicador.py
"""
import re
import shutil
import sys

INICIO = "# >>> condominio do banco (patch 24/09)"
FIM = "# <<< condominio do banco"

BLOCO = f'''{INICIO}
def _com_condominio_do_banco(imovel, conn=None):
    """O nome do condomínio quando a PÁGINA não publica e a TABELA sabe.

    MEDIDO em 24/09: de 14 imóveis sorteados cuja tabela tem
    `condominio_nome`, dois não tinham o campo na página -- e nos dois o
    valor da tabela era "Casa", o TIPO, não um condomínio. No catálogo
    inteiro são 77 linhas assim. Cair no banco sem filtro trocaria
    "Casa bairro Flores" por "📍 Casa", que identifica MENOS.

    QUEM JULGA É O BANCO, de propósito: `nay_condominio_de_verdade(tipo,
    condominio_nome)` já existia e já é usada pela busca da Nay. Escrever a
    mesma regra em Python seria a sexta cópia de um casamento -- o padrão que
    o HISTORICO registra e o CLAUDE.md manda evitar. Se a lista de rótulos
    mudar, muda num lugar e o card e a busca continuam concordando.

    FALHA FECHADA: qualquer erro deixa o imóvel como estava, que é o
    comportamento de antes deste patch. Título é cosmética; derrubar um
    disparo por causa dele seria pior que o título feio.
    """
    if not imovel or (imovel.get("condominio") or "").strip():
        return imovel
    proprio = conn is None
    try:
        ligacao = conn or db.conectar()
        try:
            with ligacao.cursor() as cur:
                cur.execute(
                    "SELECT nay_condominio_de_verdade(tipo, condominio_nome) "
                    "       AS nome "
                    "  FROM imoveis WHERE codigo::text = %s",
                    (str(imovel.get("codigo") or ""),))
                linha = cur.fetchone() or {{}}
            nome = (linha.get("nome") or "").strip()
            if nome:
                imovel["condominio"] = nome
        finally:
            if proprio:
                ligacao.close()
    except Exception:
        pass
    return imovel
{FIM}
'''

CHAMADAS = [
    # _mandar_os_codigos: o envio privado para um corretor
    ('        texto_msg = montar_mensagem(imovel, {"aceita_venda": True, "aceita_locacao": True})',
     '        imovel = _com_condominio_do_banco(imovel, conn)\n'
     '        texto_msg = montar_mensagem(imovel, {"aceita_venda": True, "aceita_locacao": True})'),
    # _postar_codigo: o disparo nos grupos de parceiro
    ('    imovel = _so_esse_negocio(imovel, negocio)',
     '    imovel = _com_condominio_do_banco(imovel, conn)\n'
     '    imovel = _so_esse_negocio(imovel, negocio)'),
    # _postar_easy: o grupo do Easy, com todas as fotos
    ('    grupos_easy = [g for g in carregar_grupos_db(conn) if g.get("todas_fotos")]',
     '    imovel = _com_condominio_do_banco(imovel, conn)\n'
     '    grupos_easy = [g for g in carregar_grupos_db(conn) if g.get("todas_fotos")]'),
]


def aplicar(caminho):
    with open(caminho, encoding="utf-8") as f:
        c = f.read()

    # Não há import novo: quem julga o nome é a função do BANCO
    # (`nay_condominio_de_verdade`), que já existe e já é usada pela busca.
    #
    # A primeira versão deste patch importava uma cópia em Python e o guarda
    # era `"condominio_de_verdade" not in c` -- que casou com a chamada de
    # `nay_condominio_de_verdade` já presente na linha 1187 e pulou o import
    # em silêncio. O card continuou saindo errado e o `except` engoliu o
    # NameError. Guarda por SUBSTRING de identificador é armadilha: o nome
    # certo estava no arquivo o tempo todo, dizendo que a regra já existia.

    # 2. o bloco, trocado inteiro se já existir
    i = c.find(INICIO)
    if i >= 0:
        j = c.find(FIM, i)
        if j < 0:
            raise SystemExit("marcador de início sem o de fim")
        c = c[:i] + BLOCO.rstrip("\n") + c[j + len(FIM):]
    else:
        # antes da primeira função que vai usá-lo
        anc = "def _mandar_os_codigos("
        if anc not in c:
            raise SystemExit("âncora da função mudou -- não mexi em nada")
        c = c.replace(anc, BLOCO + "\n\n" + anc, 1)

    # 3. as três chamadas
    postas = 0
    for de, para in CHAMADAS:
        if "_com_condominio_do_banco(imovel, conn)\n" + de.lstrip("\n") in c:
            postas += 1
            continue
        if de not in c:
            raise SystemExit(f"âncora não encontrada: {de.strip()[:60]}")
        c = c.replace(de, para, 1)
        postas += 1

    shutil.copy(caminho, caminho + ".antes_condominio")
    with open(caminho, "w", encoding="utf-8") as f:
        f.write(c)
    print(f"  backup: {caminho}.antes_condominio")
    print(f"  {postas} chamada(s) no lugar, bloco e import aplicados")


if __name__ == "__main__":
    aplicar(sys.argv[1])
