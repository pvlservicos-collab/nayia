"""A faixa tem que valer de UM LADO SÓ -- a prova com o imóvel real que
passaria pela regra antiga (piso pela venda, teto pela locação)."""
from db import conectar
from pedido_de_imoveis import imoveis_do_pedido

conn = conectar()
with conn.cursor() as cur:
    cur.execute(
        "SELECT codigo::text c, tipo, bairro, valor_aluguel al, valor_venda vd "
        "  FROM imoveis WHERE coalesce(valor_aluguel,0) BETWEEN 250000/1000 AND 600000 "
        "   AND coalesce(valor_venda,0) > 600000 "
        "   AND nay_esta_no_mercado(disponivel,bloqueado,publicado_no_site) "
        " ORDER BY valor_venda")
    perigo = cur.fetchall()
print("imóveis que a regra ANTIGA deixaria passar numa faixa de 250k a 600k")
print("(venda acima do teto, aluguel dentro do teto):")
for l in perigo[:12]:
    print(f"   {l['c']:>5} {l['tipo'][:18]:<18} {(l['bairro'] or '')[:20]:<20} al={l['al'] or 0:>8.0f} vd={l['vd'] or 0:>10.0f}")
print(f"   ... {len(perigo)} no total\n")

for frase in ["Nay envia casa em condomínio de 250 mil a 600 mil no ponta negra",
              "Nay envia de 250 mil a 600 mil no ponta negra",
              "Nay envia imóvel comercial para venda de 200 mil a 900 mil",
              "Nay envia imóvel comercial para venda até 3 milhões"]:
    r = imoveis_do_pedido(conn, frase)
    cods = r.get("codigos") or []
    print(f">>> {frase}\n    {r['tipo']}: {', '.join(cods) or '-'}")
    intrusos = [l['c'] for l in perigo if l['c'] in cods]
    if intrusos:
        print(f"    !!! PASSOU imóvel fora da faixa: {intrusos}")

with conn.cursor() as cur:
    cur.execute(
        "SELECT codigo::text c, tipo, bairro, valor_venda vd FROM imoveis "
        " WHERE tipo ~* 'sala|loja|ponto|galp|dep|predio|andar' AND coalesce(valor_venda,0) > 0 "
        "   AND nay_esta_no_mercado(disponivel,bloqueado,publicado_no_site) ORDER BY valor_venda")
    print("\ncomerciais à venda no ar:")
    for l in cur.fetchall():
        print(f"   {l['c']:>5} {l['tipo'][:18]:<18} {(l['bairro'] or '')[:20]:<20} vd={l['vd']:>12.0f}")
