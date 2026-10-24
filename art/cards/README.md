# Carta 3D compartilhada

Existe **um modelo de carta em produção**: `client-godot/assets/cards/models/card.glb`.
As 12 magias mudam apenas a imagem da face; corpo, moldura e malhas são compartilhados.
Nome, custo e descrição continuam como texto acessível do Godot.

A mão é uma sobreposição transparente ao tabuleiro, sem faixa de fundo ou espaço reservado no layout. As cartas ficam em leque, com cerca de 320 px em Full HD; nome e mana são `Label3D` presos à face e a ilustração deixa espaço inferior para texto futuro. A descrição permanece no tooltip. O mouse sobre o tabuleiro recolhe a mão a 72 px visíveis; passar nas bordas reabre. Transições de 180 ms respeitam a opção de animações. As áreas clicáveis seguem os polígonos projetados, permitindo clicar no jogo entre cartas; menus e rodapé permanecem acima/fora da mão.

## Origem e preparação

- Modelador oficial: `C:\Projetos\Modelador3d`, imagem congelada `trellis2-rtx5060:isolated-v1`.
- Referência-base: `references/arcane_shield.png`, criada com a skill `imagegen` e ferramenta integrada `image_gen`.
- Fundo preto sólido, carta inteira centralizada, iluminação clara; sem letras na imagem.
- TRELLIS: 512, seed 42, 12 passos, textura 1024, preservação de rosto/logo desativada.
- O modelador exige ao menos 20.000 triângulos; o original foi preservado em `source/card-original.glb`.
- A preparação extrai a silhueta desse original, normaliza a carta, remove o relevo específico de magia e constrói corpo com espessura, borda comum elevada e face UV substituível. Resultado: 1.528 triângulos, uma única cena GLB, 0,98 × 1,55 de frente e aproximadamente 0,09 de espessura/relevo.
- `preparation.json` registra o resultado; `provenance.json` registra parâmetros, hashes e medidas do gerador. Intermediários, latentes e logs ficam em `.runtime/card-generation/`, ignorada pelo Git.

As 12 imagens originais de face estão em `client-godot/assets/cards/faces/`. Foram geradas individualmente, usando a carta piloto como referência de estilo, sempre sobre preto. `prompts.json` preserva os prompts. O shader ajusta o enquadramento na face sem modificar os PNGs; a importação limita a resolução a 1024 com mipmaps. Os símbolos seguem as magias existentes. Não há geração de uma malha por símbolo.

## Reproduzir manualmente

Reutilize o ambiente congelado e os pesos locais do modelador, sem atualizar CUDA, baixar pesos ou alterar seus fontes. Verifique que não há outro trabalho de modelagem usando a GPU. O comando abaixo cria um container exclusivo e descartável; não inicia interface nem serviços automaticamente.

```powershell
docker run --rm --name arcano-card-modeler --gpus all --restart no `
  --mount type=bind,source=C:\Projetos\Modelador3d\weights,target=/root/.cache/huggingface,readonly `
  --mount type=bind,source=C:\Projetos\XadrezMagico\art\cards\references,target=/references,readonly `
  --mount type=bind,source=C:\Projetos\XadrezMagico\.runtime\card-generation,target=/app/outputs `
  --mount type=bind,source=C:\Projetos\XadrezMagico\tools\generate_card_base.py,target=/app/service/generate_card_base.py,readonly `
  trellis2-rtx5060:isolated-v1 python /app/service/generate_card_base.py
```

Esse comando considera somente a referência-base e reutiliza o resultado existente se seu hash continuar igual. A preparação do original preservado é independente da geração:

```powershell
& .\.tools\blender-4.5.3-windows-x64\blender.exe --background --factory-startup --python-exit-code 1 --python tools/prepare_card_model.py -- C:/Projetos/XadrezMagico/art/cards/source/card-original.glb
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path client-godot --editor --import --quit
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path client-godot --script res://tests/cards.gd
```

O executável final não depende do modelador, Blender, imagens geradas fora do projeto ou do serviço de geração.
