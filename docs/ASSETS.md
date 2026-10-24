# Origem dos ativos

- Doze miniaturas `.glb`: fornecidas pelo proprietário em `Models/Xadrez_final.rar`, incorporadas em 20/10/2026. Os arquivos foram copiados sem alterações para `client-godot/assets/models/blue` e `red`; cores, texturas de superfície e mapas normais permanecem nos materiais importados.
- Mapeamento: `Peao → pawn`, `Torre → rook`, `Cavalo → knight`, `Bispo → bishop`, `Rainha → queen`, `Rei → king`. Azul representa Solar/brancas; vermelho representa Lunar/pretas. A ordem inicial continua sendo torre, cavalo, bispo, dama, rei, bispo, cavalo, torre.
- `client-godot/piece_models.gd` ajusta escala, base, centralização e orientação em tempo de execução. As bases ficam sobre o tabuleiro e cada silhueta ocupa no máximo 0,84 de uma casa. Promoções usam o modelo correspondente do mesmo exército.
- Apresentação das peças: `board_pieces_presenter.gd` sincroniza instâncias persistentes pelo ID e conserva casa e tipo anteriores; `piece_move_path.gd` calcula percursos e agrupa casas ocupadas sob um arco; `piece_view.gd` compõe miniatura, efeitos, animador e áudio. `piece_animator.gd` calcula movimento e emite contatos sem dependências de rede, áudio ou regras. `piece_sfx_player.gd` reproduz os contatos. O cliente principal encaminha dados e preferências ao apresentador.
- As miniaturas inteiras balançam até 1°, com fases, direções, amplitudes e períodos de três a cinco segundos próprios por ID. Cada casa tem 0,22 segundo de salto e 0,04 segundo de acomodação; o cavalo segue o L e sobrevoa casas ocupadas sem pousar nelas. No roque, o rei completa o percurso antes da torre. Congelamento, desconexão e fim de partida suavizam a volta ao repouso; a reconexão posiciona diretamente e sem som. Os GLBs originais não possuem esqueletos nem animações e permanecem intactos.
- Sons de peças: quatro WAVs originais em `client-godot/assets/audio/pieces`, gerados por `tools/generate_piece_sounds.py` com síntese de ruído percussivo e ressonâncias amortecidas; PCM mono de 16 bits a 44,1 kHz, sem gravações ou amostras externas. Impulso de 45 ms e três pousos de 130 ms, compartilhados entre as peças e com pequenas variações de afinação e volume. Gerador e seeds preservados; importação sem compressão. A preferência **Efeitos sonoros** é independente das animações e salva por perfil.
- O arquivo compactado original permanece em `Models` e não é versionado nem incluído no executável. A folha de apresentação não é necessária ao jogo. Não há arquivos externos de textura: os mapas estão embutidos nos GLBs.
- As configurações `.glb.import` usam `gltf/embedded_image_handling=2`: [texturas embutidas em Basis Universal](https://docs.godotengine.org/en/4.6/classes/class_gltfstate.html#enum-gltfstate-handlebinaryimagemode), compactadas para memória gráfica. Isso evita cópias extraídas ao lado dos GLBs; os arquivos de origem permanecem intactos.
- Miniaturas procedurais anteriores: gerador preservado em `tools/generate_models.py`, agora com saída em `.runtime/prototype-models`, fora dos recursos do jogo.
- Doze símbolos de cartas `.svg`: desenhos vetoriais originais de `tools/generate_card_icons.py`.
- Cartas da mão: um único GLB compartilhado, preparado a partir do modelador oficial `C:\Projetos\Modelador3d`, com 12 imagens intercambiáveis geradas por `imagegen`/`image_gen`. Original, parâmetros e prompts preservados em `art/cards/`; detalhes em `art/cards/README.md`. Os SVGs anteriores permanecem como fontes de referência dos símbolos.
- Engrenagem de configurações: desenho vetorial original em `client-godot/assets/ui/gear.svg`.
- Ícone de três riscos da barra lateral: desenho vetorial original em `client-godot/assets/ui/menu.svg`.
- Moldura do tabuleiro: geometria original com bordas arredondadas e incrustações de latão, gerada por `tools/generate_board.py` em `client-godot/assets/board/frame.glb` com Blender 4.5.3 LTS.
- Casas do tabuleiro: geometria interativa Godot com acabamento procedural de pedra em `client-godot/assets/board/stone.gdshader`. Materiais, interface e efeitos: código do projeto.
- `Xadrez mágico em estilo anime.png`: referência fornecida pelo proprietário; não incorporada ao executável.
- Godot e avisos de terceiros: diretório `licenses/Godot`; incluir na distribuição Windows.

O pacote fornecido não contém fontes `.blend`. Ao incorporar `.blend`, configurar Git LFS antes do primeiro commit desses arquivos.

Validação dos modelos e do tabuleiro, sem servidor:

```powershell
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path client-godot --script res://tests/models.gd
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path client-godot --script res://tests/pieces.gd
```
