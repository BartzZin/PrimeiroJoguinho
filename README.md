# Xadrez Arcano

Jogo Windows de xadrez 3D com cartas mágicas e servidor autoritativo. Alpha para convidados; Steam, ranking, loja e IA adversária ficam para depois.

## Desenvolvimento

Godot/GDScript, Python 3.13/FastAPI, motor de xadrez próprio e PostgreSQL. Consulte [o plano](docs/PLANO.md) e [o documento de visão](Xadrez_Arcano_Projeto_Completo.md).

Ferramentas serão portáteis quando possível. Nenhum aplicativo, container ou serviço do projeto deve iniciar com o Windows. Docker Desktop permanece manual; PostgreSQL roda exclusivamente em container.

## Preparação e execução

Os scripts de instalação, inicialização e parada serão adicionados nas entregas técnicas. Nunca versionar credenciais, ambientes virtuais, binários das ferramentas ou dados do banco. O status verificável da implementação será mantido em `docs/STATUS.md`.

