# Contrato HTTP e WebSocket — versão 1

API padrão local `http://127.0.0.1:8000`; em hospedagem usar HTTPS/WSS. Não enviar tokens em URL. Sessões são opacas, aleatórias e armazenadas por hash no servidor.

## HTTP

- `POST /v1/auth/invite`: `{invite, nickname}` → `{access_token, refresh_token, expires_in, account_id}`. Convite de uso único válido por 7 dias. Acesso: 30 minutos; renovação: 7 dias.
- `POST /v1/auth/refresh`: `{refresh_token}` → nova sessão; token de renovação anterior é consumido atomicamente.
- Demais operações privadas exigem `Authorization: Bearer <access_token>`.
- `POST /v1/rooms` → `{code, match_id:null}`. `GET /v1/rooms/{code}` permite ao dono aguardar o oponente.
- `POST /v1/rooms/{code}/join` → `{match_id}`. Sala expira após uma hora; não se pode enfrentar a própria conta.
- `GET /v1/me`, `/v1/matches`, `/v1/matches/{id}`, `/v1/matches/{id}/history` retornam somente dados autorizados.
- `GET /v1/cards` e `/v1/tutorials`: catálogos públicos. `POST /v1/tutorials/{scenario}/start`: cenário predefinido autenticado; não aceita FEN enviada pelo cliente.
- `/health/live` e `/health/ready`: processo e banco. `/admin/status` e `POST /admin/drain`: `ADMIN_TOKEN` separado; bloqueados pelo proxy público.

## WebSocket

`/v1/ws/match/{match_id}` com o mesmo cabeçalho Bearer. Comando:

```json
{"type":"move.request","protocol_version":1,"request_id":"uuid-novo","match_id":"uuid-da-partida","expected_version":0,"payload":{"from":"e2","to":"e4","promotion":null}}
```

Tipos: `move.request`, `spell.request`, `match.resign`, `draw.offer`, `draw.respond`. Para empate, resposta `{accept:true|false}`. Desistência e resposta a empate independem do turno. `match.ping` é consulta sem alteração de versão.

Magia: `{card_instance_id, target}`; alvo `{piece_id}` para peças, `{effect_id}` para Dissipação, `{square:"d4"}` para armadilha/oráculo/desarme e `{}` para cartas pessoais/silêncio. Não usar nomes de definição para consumir uma carta: é obrigatório o ID da instância recebida na mão.

Servidor responde `command.accepted` ou `command.rejected`, com ID, versão e código. Repetir o mesmo comando/ID retorna o recibo original; alterar o conteúdo com ID reaproveitado gera `REQUEST_ID_REUSED`. Autorização vem antes de consultar recibos. Versão antiga gera `STALE_VERSION`; o cliente recebe novo snapshot.

Após commit, cada jogador recebe `match.snapshot`: versão, regra, lado, peças com IDs estáveis, FEN convencional, efeitos públicos, mão e armadilhas próprias, revelações temporárias, contagens do rival, mana, relógios, movimentos disponíveis e resultado. Nunca contém ordem do baralho ou mão adversária. Eventos de armadilha não divulgam o alvo oculto; histórico também é projetado.

Versão cresce uma vez por transição confirmada, mesmo quando existem vários eventos. Sincronização dos relógios não altera versão. O backend mantém snapshots completos por transição; não depende de event sourcing para recuperação. Reinício anula partidas ativas e não reexecuta compras.

Limites: mensagens de 8 KiB, 120 mensagens/minuto por conta no WS, 240 requisições/minuto por IP HTTP e 20 tentativas/minuto/IP para resgate de convite. Sem compensação de latência na alpha.
