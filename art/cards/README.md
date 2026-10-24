# Carta 3D compartilhada

Existe **um modelo de carta em produção**: `client-godot/assets/cards/models/card.glb`.
As 12 magias mudam apenas a imagem da face; corpo, moldura e malhas são compartilhados.
Nome, custo e descrição continuam como texto acessível do Godot.

A mão é uma sobreposição transparente ao tabuleiro, com cartas de cerca de 320 px em Full HD. Nome e mana são `Label3D` presos à face; a descrição continua no tooltip. Abertura e fechamento usam zonas fixas com margem de 24 px, atraso de fechamento de 250 ms e amortecimento contínuo, com estabilização visual próxima de 350 ms. Clique pressionado e seleção travam a abertura. A carta selecionada fica em 106% e as demais em 80%, com destaque apenas na moldura dourada original.

As vistas são reconciliadas por `instance_id`; movimentos, mana, turno e relógio não recriam a mão. Arrastar por pelo menos 8 px inicia a captura até a soltura; a prévia usa 220 px e libera a casa sob o cursor. `card_targets.gd` verifica somente dados autorizados; a consulta física e o envio continuam no cliente principal. Cartas pessoais usam alvo `{}` em qualquer casa. Dissipação oferece escolha local se houver dois efeitos.

Os estados de arraste, escolha, confirmação e retorno são distintos. A vista da carta enviada permanece reservada pelo `request_id` até confirmação e snapshot correspondente, em qualquer ordem. Só então encolhe e desaparece uma vez; rejeições restauram a mesma vista. Reconexões preservam o comando existente. Efeitos de posições privadas são produzidos apenas na sessão autorizada. O servidor, protocolo e banco não mudam.

Teste real contra o backend local, usando apenas uma sala nova de teste e dados próprios:

```powershell
.venv\Scripts\python.exe tools/smoke_clients.py --visible --executable exports/windows/XadrezArcano.exe --spell frost_bind --reconnect
.venv\Scripts\python.exe tools/smoke_clients.py --visible --executable exports/windows/XadrezArcano.exe --spell hidden_snare --reconnect
```

Esses testes configuram somente a partida recém-criada, executam pressionar/mover/soltar nas duas janelas e verificam deduplicação e privacidade da armadilha. Não há endpoint público de testes. A CI executa os gestos das 12 cartas, estabilidade dos nós, alvos, cancelamentos e a ordem dos recibos/snapshots.


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
