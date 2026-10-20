# Xadrez Arcano

Jogo Windows de xadrez 3D com cartas mágicas e servidor autoritativo. Alpha para convidados; Steam, ranking, loja e IA adversária ficam para depois.

![Alpha local com duas facções e cartas](docs/images/alpha.png)

## Desenvolvimento

Godot/GDScript, Python 3.13/FastAPI, motor de xadrez próprio e PostgreSQL. Consulte [o plano](docs/PLANO.md) e [o documento de visão](Xadrez_Arcano_Projeto_Completo.md).

Ferramentas serão portáteis quando possível. Nenhum aplicativo, container ou serviço do projeto deve iniciar com o Windows. Docker Desktop permanece manual; PostgreSQL roda exclusivamente em container.

## Preparação e execução

No PowerShell, dentro desta pasta:

```powershell
./tools/Install-Tools.ps1   # Godot + templates e Blender portáteis, com checksums
./tools/Setup-Dev.ps1       # ambiente Python, dependências e segredos locais
./tools/Play-Local.ps1      # inicia containers e abre duas janelas autenticadas
```

Na primeira vez o Docker pode demorar a abrir. Requer Docker Desktop com WSL2/virtualização já configurados e Python 3.13. As instalações não criam entradas de inicialização do Windows. Não é preciso abrir o Blender para jogar.

Para encerrar, feche as janelas e execute `./tools/Stop-Dev.ps1`. Isso preserva o banco. O Docker Desktop pode ser fechado normalmente depois; o script não encerra outros projetos.

Para apenas iniciar o backend: `./tools/Start-Dev.ps1`. Para abrir um cliente: `./tools/Open-Client.ps1 -Profile A`. Gere um convite com `./tools/New-Invite.ps1`; no jogo, entre com esse convite, crie uma sala e compartilhe o código com outro convidado. Convites de acesso e códigos de sala são coisas diferentes.

## Jogar

- Clique em uma peça sua e depois numa casa destacada.
- Clique numa carta, escolha o alvo no tabuleiro e confirme **Conjurar**. Cartas pessoais usam alvo automático. Dissipação exige escolher qual efeito remover.
- Faça o movimento depois da carta. Existe uma única conjuração por turno.
- Botão direito arrastado gira a câmera; roda do mouse aproxima; há opção de visão superior.
- O tutorial ensina movimento, defesa e armadilha usando cenários do servidor.
- O relógio continua durante animações, escolhas e desconexões individuais. Falha/reinício do servidor anula partidas em andamento.

## Verificação, backup e build

```powershell
./.venv/Scripts/python.exe -m pytest server/tests -q
./.venv/Scripts/python.exe -m ruff check server tools
./.venv/Scripts/python.exe tools/smoke_clients.py --visible
./tools/Backup.ps1
./tools/Export-Windows.ps1
```

O teste de concorrência PostgreSQL usa `TEST_DATABASE_URL`, apontado para um banco isolado; CI já o configura. O executável exportado fica em `exports/windows/XadrezArcano.exe` e precisa do servidor ativo. A build não inclui servidor offline.

Backups são cifrados com `BACKUP_KEY` de `.env`. Guarde essa chave separadamente: sem ela o backup não pode ser aberto. Restauração segura: `./tools/Restore-Backup.ps1 -File backups/arquivo.fernet`, sempre num banco novo `arcano_restore...`.

Nunca versionar credenciais, ambientes virtuais, binários das ferramentas ou dados do banco. Consulte [status e limitações](docs/STATUS.md), [protocolo](docs/PROTOCOL.md) e [implantação Linux](docs/DEPLOY.md).

