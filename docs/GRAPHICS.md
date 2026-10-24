# Gráficos, realismo e PCs mais leves

## Escolher o perfil

Abra a engrenagem e use **Qualidade gráfica**. Novos perfis começam em **Automático**; escolhas manuais já salvas continuam valendo. A detecção sugere Desempenho para GTX 1050/1050 Ti, Equilibrado para GTX 1650 e Alto para RTX 5060. Adaptadores desconhecidos recebem uma escolha conservadora, que pode ser alterada.

| Perfil | Referência de GPU | Escala 3D automática | Sombras | Efeitos |
|---|---|---|---|---|
| Desempenho | GTX 1050, 2 GB | 67%, MSAA 2× | Próximas, 2 cascatas, atlas 2048 | Céu HDRI 1K; sem SSAO, SSIL, volumes ou reflexo local |
| Equilibrado | GTX 1650, 4 GB | 85%, MSAA 2× | 2 cascatas, atlas 2048 | HDRI 1K, SSAO e um reflexo local |
| Alto | RTX 5060 | 100%, MSAA 4× | 4 cascatas, atlas 4096 | HDRI 4K, SSAO, SSIL, nuvens volumétricas e reflexo local |

A resolução da janela continua Full HD. **Resolução interna do cenário** permite substituir a escala automática por 67%, 75%, 85% ou 100%. Cartas, nomes, mana, menus e rodapé ficam em resolução nativa. Forward+ usa FSR 1; o renderizador de compatibilidade usa filtragem bilinear e desliga efeitos indisponíveis. Escala por eixo e separação do 2D seguem o [mecanismo de resolução do Godot](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html).

**Sombras** permite reduzir mais o custo. **Mostrar FPS** adiciona o contador ao rodapé, sem sobrepor o jogo. **Copiar diagnóstico gráfico** copia apenas versão, GPU, renderizador, RAM, perfil, escala e contadores; não inclui sessão, sala, mãos, armadilhas nem snapshot. O intervalo exibido é a média entre quadros, não a latência de rede.

## O que foi otimizado

- Céu fotográfico e iluminação especular calculada uma vez, em vez de recalcular o céu animado e seus mapas de radiância a cada quadro. Nuvens inferiores, água e bandeiras mantêm animação leve, pausável.
- Geometria por nível de detalhe, menos detalhes periféricos no modo Desempenho e sombras distantes removidas nos perfis leves. Não se usa oclusão cara em CPU para uma arena aberta.
- Atlas limitado a quatro reflexos, com uma captura local na cena. O [limite do atlas](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-reflections-reflection-atlas-reflection-count) reserva memória; aumentá-lo sem usar as capturas desperdiça VRAM. O modo Desempenho não cria essa captura nem volumes de neblina.
- Mipmaps, compressão de GPU, anisotropia por perfil e ajuste de mipmap para reduzir cintilação ao renderizar abaixo da resolução nativa.
- Sombras próximas usam mapas de profundidade de 32 bits e duas divisões nos perfis leves, evitando o ruído visual observado com precisão e cobertura menores.
- Peças carregadas por demanda com cache, mantendo os GLBs e materiais fornecidos pelo proprietário. Seleções do tabuleiro reutilizam materiais em vez de alocar dezenas deles por movimento do mouse.
- A captura estática exclui peças, efeitos e casas com informações de seleção/armadilha. As camadas visuais 1/2 são independentes da camada física 1 usada para clicar nas casas.

## Acabamento visual

A plataforma passou a ter placas chanfradas, juntas e balaustradas arqueadas. A pedra usa textura de superfície gerada por `imagegen`, com rugosidade e relevo derivados no shader. Iluminação HDRI, exposição fixa, mapeamento AgX, sombras de contato e iluminação indireta no modo Alto dão volume às superfícies. O cabeçalho compacto libera espaço para o tabuleiro.

O céu utiliza [Kloppenheim 03 (Pure Sky)](https://polyhaven.com/a/kloppenheim_03_puresky), de Greg Zaal/Jarod Guest, sob [CC0](https://polyhaven.com/license). A direção da luz principal foi obtida do ponto mais luminoso do HDRI. As referências usadas no Modelador3d continuam com fundo preto; a textura de pedra é um mapa de superfície aplicado ao jogo.

O próximo salto para realismo fotográfico exige refinar a arte: malhas arquitetônicas com arestas e ornamentos mais limpos, UVs, materiais específicos por superfície e novos materiais/rigs para as miniaturas. Os modelos de peças existentes têm identidade estilizada; esta etapa preserva sua aparência, animações e áudio.

## Medir e verificar

Os resultados em `art/arena/performance.json` foram medidos **na RTX 5060 disponível**, em processos separados, com 32 peças e cinco cartas, sem geração concorrente. Incluem quatro vistas, órbita completa e movimento de peças. O teste desliga VSync e limite de FPS; o jogo normal continua limitado a 60 FPS.

**GTX 1050/1650 e sistemas com 8 GB de RAM não estavam disponíveis para teste.** Os perfis são alvos de otimização, não certificação de 60 FPS nessas máquinas. Contadores de memória do Godot são estimativas do renderizador, não o uso total reportado pelo driver. O teste usa um cliente; `Jogar.cmd` abre duas instâncias e exige mais recursos.

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path client-godot --script res://tests/arena_benchmark.gd -- --quality=0 --capture=C:/Projetos/XadrezMagico/.runtime/performance
```

Usar `--quality=1` ou `2` para os demais perfis. Testes funcionais: `tests/graphics.gd`, `tests/arena.gd`, `tests/cards.gd` e `tests/pieces.gd`. Vulkan e OpenGL Compatibility foram verificados localmente. Nos perfis com reflexo local, permanece um aviso de recursos de textura no encerramento do Godot; ele está registrado em `STATUS.md`.
