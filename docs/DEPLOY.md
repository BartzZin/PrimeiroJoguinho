# Implantação da alpha — pendente de hospedagem

O proprietário informou que ainda não possui hospedagem. Nenhum servidor externo foi contratado ou publicado. Este pacote é reproduzível localmente; a validação entre PCs externos fica pendente.

## Servidor

Linux x86_64, Docker Engine/Compose, Git, domínio apontado ao servidor, portas 80/443 e administração SSH restrita. Banco e API ficam ligados apenas a localhost no host; o Caddy é a entrada pública. Backend é um único worker. Não subir duas réplicas sobre o mesmo banco: inicializações anulam partidas ativas.

```sh
git clone https://github.com/BartzZin/PrimeiroJoguinho.git
cd PrimeiroJoguinho
umask 077
cp .env.example .env
# Preencher POSTGRES_PASSWORD, DATABASE_URL, ADMIN_TOKEN, BACKUP_KEY e DOMAIN.
docker compose --env-file .env -f ops/compose.yaml -f ops/compose.production.yaml up -d --build --wait
```

O endereço local de DATABASE_URL serve a ferramentas administrativas no host. O container recebe a URL interna correta pelo Compose. Gere segredos aleatórios distintos; não usar os valores de exemplo. A chave de backup é uma chave Fernet de 32 bytes em base64, não uma senha arbitrária.

Caddy emite/renova o certificado para DOMAIN quando DNS e portas estiverem corretos. Distribua a pasta `exports/windows` com os avisos de licença. No jogo configure `https://seu-dominio`. Crie convites via `docker compose --env-file .env -f ops/compose.yaml exec -T api python -m app.cli invite`.

## Atualizações e falhas

Ative drenagem antes de atualizar: POST local `/admin/drain` com ADMIN_TOKEN; consulte `/admin/status` e aguarde partidas ativas terminarem, consultando o banco. Não interromper partidas planejadamente sem anunciar aos convidados. Após backup, atualizar Git e reconstruir a API. Reinício inesperado é registrado como `server_failure`, sem vencedor.

Não realizar downgrade destrutivo: revisar migração, restaurar backup em banco isolado e decidir a recuperação antes de trocar dados de produção. A primeira migração contém SQL fixo do esquema inicial; futuras alterações exigem novas revisões explícitas, preservando essa revisão histórica.

## Backup e observabilidade

`tools/backup.py` usa pg_dump e Fernet (cifragem autenticada). Requer Python com dependências do projeto no host. `create` grava backup cifrado; `restore caminho --database arcano_restore_teste` cria novo banco, sem sobrescrever `arcano`. Guardar chave e cópias dos backups em locais separados. Antes do beta, configurar retenção e cópia externa; atualmente a execução é manual.

Healthchecks verificam API e banco. Métricas administrativas contam comandos aceitos/recusados e timeouts no processo atual; reiniciam com ele. Usar `docker stats` e `docker compose logs` para CPU/memória e erros. Não registrar tickets, tokens, payloads completos ou snapshots em ferramentas externas.

Teste de carga disponível em `tools/load_test.py`: 20 partidas, 40 conexões e 120 movimentos. Resultados locais não constituem uma estimativa de capacidade da VPS.

## Windows pessoal

O arquivo base usa `restart: no`; somente o override Linux utiliza `unless-stopped`. Instalação portátil e scripts locais não criam serviços automáticos, tarefas agendadas ou entradas de login. Não usar o override de produção no computador pessoal.
