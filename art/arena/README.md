# Arena celestial

Ambiente original inspirado na referência do proprietário `exemplo/Arena Celestial entre Reinos Flutuantes.png`. Plataforma de 24 unidades com oito grupos de ornamentos, dois palácios e seis ilhas secundárias, além de fragmentos, pontes, bandeiras e cachoeiras. Os reinos ocupam posições fixas no mundo.

## Procedência e geração

- Referências `references/*.png`: `imagegen`, ferramenta integrada `image_gen`; prompts completos em `prompts.json`. Todos os objetos de modelagem têm fundo preto sólido e enquadramento inteiro.
- Modelador oficial: `C:\Projetos\Modelador3d`, TRELLIS.2, ambiente congelado `trellis2-env:20261021`, serviço `trellis2-rtx5060:isolated-v1`. Nenhum fonte, peso ou pacote do modelador foi alterado.
- Geração em container descartável, `--restart no`, sem servidor adicional nem inicialização com o Windows. Resolução 512, seed 42, processamento sequencial, preservação ISAIA desativada; textos e emblemas arquitetônicos são construídos no jogo/Blender.
- Comparação do pilar em 12 e 24 passos: 24 escolhido pelo cristal mais definido e topologia inicialmente fechada; 12 teve seis arestas de contorno e não foi usado no jogo. Folhas de 12 vistas e relatórios preservados. Demais módulos usam 24 passos. Textura gerada: pilar/cristal 4096, castelo/ilha 2048.
- Metadados, pedidos de geração e versões detalhadas ficam em `originals/`. Pesos, caches, latentes e logs completos ficam fora do versionamento, em `.runtime/arena-generation/` e no modelador.

## Preparação e arquitetura

`tools/prepare_arena_asset.py`, executado no Blender portátil, normaliza origem/escala, remove componentes isolados de ruído com até oito faces junto a bordas defeituosas, verifica a topologia, cria uma cópia reduzida e transfere detalhes para mapa normal tangente. Salva doze renders com vistas traseiras, superiores e inferiores. Defeitos remanescentes impedem a publicação do recurso. No castelo, uma face isolada de ruído causou a rejeição no modelador; a cópia preparada remove esse fragmento, preservando o original.

`tools/generate_arena.py` constrói a plataforma, suas faces inferiores, molduras, balaustradas, pontes e kit de torres com medidas precisas. Materiais compartilhados e junção por material reduzem chamadas de desenho. A pedra usa acabamento procedural no espaço do mundo, mantendo detalhes ao aproximar a câmera.

Recursos preparados em `client-godot/assets/arena/`, com texturas embutidas e importação em Basis Universal. O shader de reino varia áreas azuis para vermelho e escurece a pedra do reino Lunar, conservando os dourados. O reino Solar mantém a pedra clara. As geometrias originais geradas não são substituídas pelas cópias de execução.

O cristal isolado foi interpretado pelo gerador com a gema neutra/escura. O shader restaura o material safira/rubi somente na região facetada, mantendo a base e a armação douradas. Os arquivos originais preservam a interpretação recebida do modelador. Na ilha, a redução deixou pequenos componentes fechados sem volume que o exportador convertia em faces isoladas; a preparação remove esse ruído e a auditoria reimporta o GLB final para verificar o resultado efetivamente entregue.

## Integração

`arena_environment.gd` cria o ambiente uma única vez, sem dados privados da partida. O cenário não possui colisores na camada física 1, exclusiva das casas. O céu fotográfico tem iluminação em cache; nuvens inferiores, água e bandeiras usam tempo manual que pausa com a preferência de animações. Não há streaming de recursos durante a órbita. O protótipo de céu procedural e os kits geométricos intermediários ficam em `.runtime/arena-prototypes/`.

Desempenho mantém a composição principal e sombras próximas, com escala 67%, MSAA 2× e sem capturas locais ou volumes. Equilibrado usa escala 85%, SSAO e um reflexo local; Alto usa resolução nativa, MSAA 4×, SSAO/SSIL e nuvens volumétricas. Os resultados medidos ficam em `performance.json`; referências, limitações e reprodução em `docs/GRAPHICS.md`.

As fontes `originals/*-source.glb` usam Git LFS e não entram no executável. Para baixar as fontes detalhadas em outra máquina, usar `git lfs pull`. Os GLBs de execução permanecem disponíveis no checkout comum, inclusive na CI.

Nos perfis com reflexo local, os testes Vulkan registram um aviso de sete RIDs de textura no encerramento do Godot. Esse aviso permanece documentado em `docs/STATUS.md`; não ocorre no processo novo com perfil Desempenho e não foi escondido nos logs.

## Reprodução

```powershell
& .tools/blender-4.5.3-windows-x64/blender.exe --background --python tools/generate_arena.py
& .tools/blender-4.5.3-windows-x64/blender.exe --background --python tools/prepare_arena_asset.py -- CAMINHO_GLB NOME ALTURA
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path client-godot --script res://tests/arena.gd
```

No segundo comando, substituir `CAMINHO_GLB` pelo caminho de um GLB e `NOME` pelo módulo; tamanho negativo indica ilha com origem no topo e largura igual ao valor absoluto. Não é necessário gerar modelos para jogar.
