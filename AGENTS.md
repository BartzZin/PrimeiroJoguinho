# Xadrez Arcano

Alpha Windows de xadrez 3D entre convidados, com 12 cartas mágicas e servidor autoritativo.

## Arquitetura e tecnologias

- `client-godot/`: Godot 4.7.2 e GDScript; tabuleiro, modelos, interface e conexão HTTP/WebSocket.
- `server/app/domain/`: motor próprio de xadrez e magia, independente da interface, API e banco.
- `server/`: Python 3.13, FastAPI, SQLAlchemy/Alembic e PostgreSQL; sessões, salas, partidas e histórico.
- `tools/` e `ops/`: PowerShell/Python, Docker Compose, exportação Windows e implantação futura.

## Trabalhar e validar

- Jogar localmente: `Jogar.cmd`. Encerrar o ambiente: `Parar.cmd`.
- Servidor: `.venv\Scripts\pytest.exe server/tests -q`; lint: `.venv\Scripts\ruff.exe check server tools`.
- Cliente: Godot portátil em `.tools/godot/`; testes em `client-godot/tests/`, também executados pela CI.
- Build: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Export-Windows.ps1`.
- Preservar alterações locais alheias à tarefa, dados do banco e segredos; não versionar `.env`, caches ou ferramentas.

## Modelagem e imagens

- **Modelador 3D oficial: `C:\Projetos\Modelador3d` (TRELLIS.2).** Consultar seu README e reutilizar o ambiente congelado; não alterar seus fontes como parte de tarefas do jogo.
- Fluxo: referência visual → Modelador3d → GLB → preparação/otimização → Godot. Usar a skill `imagegen` quando forem necessárias novas imagens de referência.
- **Todas as referências de modelagem devem ter fundo preto sólido**, objeto inteiro, centralizado, sem cortes, bem iluminado e com silhueta legível.
- **Personagens sempre de frente, braços e pernas bem afastados, mãos separadas do corpo e espaços claros entre os membros**, para evitar partes grudadas.
- Preservar referências, parâmetros, procedência e modelos originais. Textos de cartas permanecem no Godot; não gerar letras na malha.
- Cartas usam **um único modelo 3D compartilhado**; cada magia altera somente a imagem da face, sem gerar uma malha por carta.
- Iniciar ferramentas e containers somente manualmente. Não criar inicialização automática no Windows, serviços automáticos ou alterar permanentemente a política do PowerShell.
