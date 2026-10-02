## 🧪 MODO TESTE — SÓ O TEL [telefone …2835])
Enquanto `nai_config.modo = teste`:
- só o número de teste cai aqui;
- o que iria para PROPRIETÁRIO, FERNANDO ou TEL vai para o número de teste, com etiqueta;
- nada sai para número fora da lista (parede no banco).

**Para ir pra valer:**
`UPDATE nai_config SET valor='todos' WHERE chave='modo';`
