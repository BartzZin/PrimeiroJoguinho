# Plano aprovado — Xadrez Arcano

## Entrega

Alpha Windows: partidas na internet entre convidados, 12 cartas, motor próprio, tutorial, histórico e visual 3D estilizado simples. Fora desta entrega: Steam, ranking, loja, IA adversária, espectadores e repetição/50/75 lances.

## Ambiente e Git

Reutilizar Python 3.13, Git e Docker. Instalar Godot portátil com templates correspondentes e Blender portátil estável. Dependências Python isoladas e travadas. Não criar inicialização automática, tarefas agendadas ou PostgreSQL nativo. Containers locais usam `restart: no`. Scripts manuais iniciam/param somente o projeto, sem apagar volumes.

Inicializar `main`, configurar `origin` em https://github.com/BartzZin/PrimeiroJoguinho.git e publicar documentação e referência antes do código. Não usar push forçado. Ignorar segredos, ferramentas, caches, builds e dados. Usar Git LFS para fontes Blender quando forem incorporadas.

## Etapas e aceite

1. Fundação: estrutura, CI, contratos e duas janelas Godot sincronizadas.
2. Motor: movimentos, ataques, xeque, roque, en passant, promoção; perft 20/400/8902/197281.
3. Online persistente: PostgreSQL, sessões, salas, relógios, recibos, reconexão e anulação após reinício.
4. Núcleo mágico: mana, baralho, mão, escudo, armadilha e ruptura com projeções privadas.
5. Doze cartas, tutorial compartilhando o motor, peças estilizadas, UI e efeitos.
6. Alpha externa: convites, TLS/WSS, build Windows, backups, métricas e teste de dois PCs externos.

## Regras consolidadas

- Mapa de ataques independente de movimentos legais; peças imobilizadas e cravadas continuam atacando.
- Mate/afogamento consideram movimento direto ou uma carta seguida de movimento; preparar início do turno antes de avaliar.
- Uma carta antes do movimento; 10 minutos + 5 segundos por movimento confirmado. Sem compensação de latência.
- Armadilha disparada durante B imobiliza até o fim do próximo turno de B. Armadilhas persistem até disparo/desarme e podem compartilhar casa com uma adversária.
- Torre imobilizada impede roque; as casas finais de rei e torre disparam armadilhas. Promoção mantém ID e efeitos.
- Fôlego Temporal: uma vez por jogador/partida. Oráculo recortado nas bordas. Desarmar pode falhar, consumindo carta sem revelar resultado a terceiros.
- Empate por acordo, afogamento e rei contra rei; repetição/50/75 desativadas e informadas.
- Desconexão individual não pausa. Reinício inesperado anula partidas ativas uma única vez, preservando histórico. Manutenção planejada drena partidas.

## Arquitetura

Domínio independente de framework/banco/cliente. Um processo de backend; fila/lock por partida e bloqueio transacional PostgreSQL. Confirmar snapshot, eventos, recibo e resultado atomicamente; publicar depois do commit. Recibos independentes dos eventos, múltiplos eventos por comando e uma versão por transição lógica. Projeções separadas por jogador com IDs de peças e sem segredos adversários.

HTTP para convites/sessões/salas/consultas/tutorial; WebSocket para ações e snapshots. Contas não exigem SteamID. Tutorial com posições e respostas predefinidas no mesmo motor.

## Validação

Movimentos especiais, perft, combinações mágicas, invariantes, privacidade, concorrência, reenvios, queda depois do commit, timeout, reconexão e reinício. Verificar exportação Windows e restauração de backup; carga inicial de 20 partidas, registrando hardware e latência. Confirmar que nada novo inicia com o Windows e que o commit local está no remoto.

Estimativa original: 21–30 semanas de dedicação integral; reavaliar após motor e primeira partida persistente. Código entregue não equivale a balanceamento e validação externa concluídos.

