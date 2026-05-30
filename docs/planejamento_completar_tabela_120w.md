# Planejamento Para Completar a Tabela 120W

## Estado Atual

A rodada `initial_table_120w_full` em `120W` nao cobriu todos os modelos.

Atualizacao de execucao em `2026-05-30`:

- a fase de correcao e backfill da tabela foi concluida
- `summary_enriched.{json,csv,jsonl}` foram gerados
- o plot consolidado foi regenerado
- a exportacao LaTeX foi regenerada
- os artefatos locais e o workspace da Jetson foram sincronizados com esse estado

Concluidos:

- `Depth Anything V2`
- `FoundationStereo`

Pendentes de runner Jetson:

- `Depth Anything V3`
- `Depth Pro`
- `Marigold`
- `IGEV`

Atualizacao de implementacao em `2026-05-30`:

- `scripts/jetson/run_depth_anything_v3.sh`
- `scripts/jetson/run_depth_pro.sh`
- `scripts/jetson/run_marigold.sh`
- `scripts/jetson/run_igev.sh`
- `scripts/jetson/run_initial_table_current_mode.sh` agora ja pode incluir esses quatro modelos nas novas rodadas

Ou seja:

- a pendencia deixou de ser "falta runner"
- a pendencia passou a ser "falta validar/buildar/medir os quatro no ambiente Jetson e regenerar a tabela 120W"

## Decisao Sobre Rerun Dos Modelos Ja Concluidos

### `Depth Anything V2`

Nao precisa rerodar agora para energia e tempo total.

Motivo:

- `run_meta.json` e `tegrastats_summary.json` estao validos
- a contagem real de imagens pode ser recuperada dos artefatos gerados
- o que faltou foi registrar melhor `processed_items`, nao refazer a execucao

Acao necessaria:

- corrigir o pipeline da tabela para salvar `processed_items=4225` e `processed_unit=images`
- adicionar `FLOPs` offline e recalcular `J/item` e `J/GFLOP`

### `FoundationStereo`

Nao precisa rerodar agora para energia e tempo total.

Motivo:

- `run_meta.json` e `tegrastats_summary.json` estao validos
- `batch_run_info.json` ja registra `processed_pairs=276`
- o runner em lote atual ja e o runner bom, com barra de progresso e menor ruido

Acao necessaria:

- corrigir o pipeline da tabela para salvar `processed_items=276` e `processed_unit=stereo_pairs`
- adicionar `FLOPs` offline e recalcular `J/item` e `J/GFLOP`

### Quando rerodar os dois

Vale rerodar `DA2` e `FoundationStereo` apenas uma vez, no fim, se voce quiser:

- uma tabela final inteiramente regenerada com o pipeline corrigido
- todos os modelos medidos em uma mesma janela termica e operacional
- um CSV final limpo, sem backfill manual

## Fase 1: Corrigir o Pipeline da Tabela

Objetivo:

- parar de usar `samples` do `tegrastats` como se fossem imagens processadas

Mudancas necessarias:

- `scripts/jetson/run_initial_table_current_mode.sh`
  - adicionar campos `processed_items`
  - adicionar `processed_unit`
  - manter `telemetry_samples` separado
  - suportar leitura opcional de `flops.json`
  - calcular `throughput_items_s`, `joules_per_item` e `jgflops`

- `Depth Anything V2`
  - criar helper para contar outputs reais nas pastas `grayscale/`

- `FoundationStereo`
  - ler `processed_pairs` de `batch_run_info.json`

Saida esperada:

- `summary.csv` e `summary.json` passam a refletir throughput real

Status:

- concluido em `2026-05-30` com `scripts/jetson/backfill_initial_table_report.py`
- a geracao visual e a exportacao em LaTeX agora fazem parte do fluxo documentado

## Fase 2: Matriz de Containers

### Manter

- `depth-jetson-base`
- `depth-jetson-mono`
- `depth-jetson-stereo`

### Adicionar

- `depth-jetson-marigold`

Motivo:

- `Marigold` usa `diffusers` e pipeline diffusion
- merece isolamento de dependencias e tuning proprio

### Reavaliar

- `IGEV`

Motivo:

- o codigo original esta preso a stack antiga de `torch==1.12.1+cu113`
- isso pode colidir com a base atual da Jetson Thor

Estrategia recomendada:

1. primeiro tentar portar o runner para a imagem `stereo` atual com pequenos patches de compatibilidade
2. se falhar em import ou inferencia, criar uma imagem dedicada `depth-jetson-igev`
3. evitar contaminar `FoundationStereo` com hacks legados de `IGEV`

## Fase 3: Runners Implementados E Validacao Pendente

### `Depth Anything V3`

Runner alvo:

- `scripts/jetson/run_depth_anything_v3.sh`

Escopo:

- usar a imagem `depth-jetson-mono`
- remover hardcodes de device, batch e nome de modelo
- aceitar `--dataset all|nome`
- aceitar `--limit`
- salvar saida padronizada em `artifacts/da3/<dataset>/<variant>/`
- preferir salvar depth numerico ou grayscale, nao apenas colormap

Risco principal:

- dependencias extras do repo; talvez o `mono` precise mais alguns pacotes

### `Depth Pro`

Runner alvo:

- `scripts/jetson/run_depth_pro.sh`

Escopo:

- usar a imagem `depth-jetson-mono`
- transformar a saida atual em formato padronizado para a tabela
- salvar depth bruto ou grayscale alem da visualizacao colorida
- aceitar `--dataset all|nome`
- aceitar `--limit`

Risco principal:

- o runner atual enfatiza depth colorido; precisamos garantir saida numerica consistente

### `Marigold`

Runner alvo:

- `scripts/jetson/run_marigold.sh`

Container alvo:

- `docker/jetson/Dockerfile.marigold`

Escopo:

- remover prompts interativos
- aceitar `--dataset all|nome`
- aceitar `--limit`
- preservar `.npy` como saida canonica
- opcionalmente gerar visualizacao `.png`

Risco principal:

- alto custo computacional e de memoria na Jetson

Mitigacoes:

- limitar resolucao
- controlar precision
- controlar numero de diffusion steps

### `IGEV`

Runner alvo:

- `scripts/jetson/run_igev.sh`

Escopo:

- rodar somente `uwstereo val`
- aceitar `--limit`
- salvar depth/disparity em formato reutilizavel
- gerar um `batch_run_info.json` equivalente ao do `FoundationStereo`

Risco principal:

- compatibilidade PyTorch/JetPack

## Fase 4: FLOPs

Objetivo:

- completar a tabela com custo computacional sem rerodar energia onde nao for preciso

Acao:

- criar um probe dedicado por modelo, usando `scripts/benchmark/flops_probe_template.py` como base

Arquivos esperados:

- `scripts/analysis/flops_probe_da2.py`
- `scripts/analysis/flops_probe_foundation.py`
- `scripts/analysis/flops_probe_da3.py`
- `scripts/analysis/flops_probe_depth_pro.py`
- `scripts/analysis/flops_probe_marigold.py`
- `scripts/analysis/flops_probe_igev.py`

Observacao:

- para `Marigold`, o FLOP por amostra deve explicitar resolucao e numero de diffusion steps

## Ordem Recomendada De Execucao

1. implementar `Depth Pro`
2. implementar `Depth Anything V3`
3. adicionar container e runner de `Marigold`
4. tentar `IGEV` na imagem `stereo`; se falhar, separar container
5. calcular `FLOPs` offline para todos
6. gerar uma tabela consolidada
7. somente se necessario, fazer um rerun final completo de todos os modelos em `120W`

## Resultado Esperado

Ao fim dessas etapas, a tabela final deve conter para todos os modelos:

- status
- modo de potencia
- dataset avaliado
- tempo total
- throughput real
- energia total
- energia por item
- potencia media
- potencia de pico
- FLOPs por item
- `J/GFLOP`
