# Status verificável — 20/10/2026

## Implementado e verificado localmente

- Godot 4.7.2, templates correspondentes e Blender 4.5.3 LTS portáteis instalados em `.tools`, com checksums oficiais verificados.
- Python 3.13 isolado em `.venv`; dependências fixadas em `server/requirements.lock`.
- Motor próprio: movimentos, ataques, xeque, roque, promoção, en passant; perft inicial até profundidade 4, Kiwipete e final com en passant.
- Doze cartas, recursos, durações, armadilhas ocultas e resultado considerando defesa mágica.
- Contas por convite, renovação de sessão, salas, WebSocket, projeções privadas, histórico, recibos e PostgreSQL transacional.
- Reconexão individual; timeout automático; anulação idempotente após reinício.
- Cliente Godot 3D com doze modelos texturizados fornecidos pelo proprietário (seis peças, exércitos azul e vermelho), doze símbolos de cartas, alvos, promoção, efeitos, câmeras, configurações, empate, desistência e tutorial guiado.
- Apresentação Full HD, janela maximizada e atalho F11 para tela cheia; tabuleiro ampliado, moldura com bordas arredondadas, acabamento de pedra, renderizador Forward+, reflexos de ambiente, iluminação em dois sentidos, sombras, oclusão ambiente e suavização 4× no modo Alto.
- Validação Godot dos 12 modelos, enquadramento das casas, 32 peças, escala, texturas, orientação, seleção, movimento, promoção, captura, efeitos e modos de qualidade; renderização local conferida na RTX 5060.
- Executável Windows exportado e testado em duas instâncias simultâneas, sem depender do editor ou aceitar override de projeto.
- Scripts manuais de instalação, início, parada, convites, jogo local, exportação e backup/restauração.
- Migração Alembic 001 aplicada num banco PostgreSQL vazio; configuração Caddy validada em container temporário.
- Backup Fernet criado e restaurado em `arcano_restore`: 22 partidas recuperadas sem modificar o banco principal.
- 43 testes do servidor aprovados, incluindo captura segura de logs, sockets reais e dois escritores concorrentes no PostgreSQL. Ruff aprovado.
- Correções de interação: mundo 3D explícito e consultas físicas no processamento de física; regressões por cliques nos dois lados, com rotação de câmera e redimensionamento.
- Indicador de conexão separado das ações, confirmação pelo primeiro snapshot, prazo de 10 segundos e três reconexões automáticas; reenvio mantém o identificador do comando.
- Engrenagem no rodapé com logs detalhados como primeiro checkbox; preferências locais separadas das sessões, qualidade, animações, visão superior e tela cheia.
- Logs estruturados do cliente com captura de erros de scripts, rotação, proteção de dados e escrita concorrente; inicializador e servidor também possuem registros operacionais.

## Medição local

20 partidas, 40 conexões e 120 movimentos: mediana 189,69 ms, p95 244,22 ms, máximo 326,55 ms. Medição entre envio do cliente e snapshot do rival, incluindo rede local, banco e broadcast; duração de 1,579 s. Windows 11, 16 CPUs lógicas. Validação gráfica em RTX 5060. Não são requisitos mínimos nem capacidade estimada de hospedagem.

## Limitações e pendências

- Proprietário ainda não possui hospedagem. HTTPS/WSS configurados para implantação, mas emissão pública de certificado, VPS e teste entre PCs externos não foram executados.
- Versão de alpha para teste; balanceamento das cartas e playtests prolongados ainda são necessários.
- Sem repetição/50/75 lances; empate material automático somente rei contra rei.
- Tutorial usa três cenários e respostas predefinidas; não existe adversário IA nem modo offline.
- Modelos incorporados a partir de `Models/Xadrez_final.rar`; origem e mapeamento documentados em `docs/ASSETS.md`.
- CI adicionada ao repositório; resultados remotos devem ser consultados em GitHub Actions após o envio.
- Backup e monitoramento disponíveis manualmente; retenção externa e alertas operacionais aguardam hospedagem.
- O pacote fornecido contém GLBs com texturas embutidas, sem fontes `.blend`. O gerador Python preserva somente os protótipos anteriores. Adotar Git LFS antes de incorporar `.blend`.

Ferramentas não criam inicialização automática no Windows. Docker Desktop foi mantido com `AutoStart=false`; serviço Docker em modo Manual; containers locais usam `restart: no`.

