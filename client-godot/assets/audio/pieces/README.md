# Sons originais de contato

Gerados por `tools/generate_piece_sounds.py`, sem gravações ou amostras externas.
O gerador combina ruído percussivo com ressonâncias senoidais amortecidas e usa
seeds fixas: 2410 para o impulso e 2411–2413 para os três pousos.

- Formato: PCM mono, 16 bits, 44.100 Hz, importado sem compressão ou normalização.
- `impulse.wav`: 45 ms, contato leve de saída.
- `landing-1.wav`, `landing-2.wav`, `landing-3.wav`: 130 ms, contatos de chegada.
- Reprodução: `piece_sfx_player.gd`, com variação discreta de afinação e volume.

Para regenerar, execute na raiz do projeto:

```powershell
& .\.venv\Scripts\python.exe tools/generate_piece_sounds.py
```

As atualizações de relógio, carregamento, reconexão e repouso não geram sons.
Com animações desligadas, cada lance confirmado produz um único contato.
