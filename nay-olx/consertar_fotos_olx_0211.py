"""02/11/2026 (o 9115 com as fotos quebradas): uma vez só. As fotos que ficaram com o link da OLX (img.olx.com.br) no
imovel_fotos são baixadas para fotos-captacao/olx/<código>/ e o cadastro passa a apontar para o nosso endereço. A que não
baixar fica como está e sai na lista. Rodar no servidor: cd /root/nay-olx && .venv/bin/python consertar_fotos_olx_0211.py"""
from olx import banco, fotos_olx

conn = banco.conectar()
fotos = banco.linhas(conn, "SELECT codigo, ordem, url FROM imovel_fotos WHERE url LIKE 'https://img.olx.com.br/%%' ORDER BY codigo, ordem")
trocadas, ficaram = 0, []
for f in fotos:
    nova = fotos_olx.guardar(f["codigo"], f["ordem"], f["url"])
    if nova == f["url"]:
        ficaram.append(f"#{f['codigo']} foto {f['ordem']}")
        continue
    banco.um(conn, "UPDATE imovel_fotos SET url = %s WHERE codigo = %s AND ordem = %s AND url = %s",
             (nova, f["codigo"], f["ordem"], f["url"]))
    conn.commit()
    trocadas += 1
print(f"{len(fotos)} fotos da OLX; {trocadas} agora no nosso site; ficaram com o link da OLX: {', '.join(ficaram) or 'nenhuma'}")
