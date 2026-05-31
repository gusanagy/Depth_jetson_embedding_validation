# Analise Da `initial_table_120w_full`

## Resumo

A rodada `initial_table_120w_full` em `120W`, coletada na Jetson Thor em `2026-05-29`, nao executou todos os modelos previstos.

Status observado:

- concluidos:
  - `Depth Anything V2`
  - `FoundationStereo`
- pendentes de runner Jetson:
  - `Depth Anything V3`
  - `Depth Pro`
  - `Marigold`
  - `IGEV`

Atualizacao de repositorio em `2026-05-30`:

- os quatro runners pendentes foram implementados no repositório
- a rodada historica `initial_table_120w_full` continua parcial
- ainda falta executar uma nova rodada `120W` para preencher essa mesma tabela com os quatro modelos restantes

Os resultados brutos da Jetson foram espelhados localmente em:

- `reports/initial_table/initial_table_120w_full/summary.json`
- `reports/initial_table/initial_table_120w_full/summary.csv`

Observacao de organizacao:

- essa pasta em `reports/initial_table/initial_table_120w_full/` e um baseline historico versionado
- resultados novos puxados da Jetson devem ir para `reports/pulled_from_jetson/initial_table/<label>/`

## Correcao Importante Na Leitura Da Tabela

O `summary.csv` original da tabela inicial nao deve ser usado diretamente para throughput.

Motivo:

- o campo `samples` nessa versao do pipeline veio do `tegrastats`
- portanto ele representa amostras de telemetria, nao imagens ou pares realmente processados

Para a analise corrigida, foi feito backfill com contagem real dos artefatos:

- `Depth Anything V2`: contagem real nas pastas `grayscale/`
- `FoundationStereo`: leitura de `processed_pairs` em `batch_run_info.json`

## Metricas Corrigidas

### `Depth Anything V2`

- itens processados: `4225` imagens
- duracao: `696.21 s`
- throughput real: `6.07 imagens/s`
- energia total: `37.16 kJ`
- energia por item: `8.80 J/img`
- potencia media: `53.37 W`
- pico de potencia: `86.08 W`

### `FoundationStereo`

- itens processados: `276` pares
- duracao: `1147.62 s`
- throughput real: `0.24 pares/s`
- energia total: `87.54 kJ`
- energia por item: `317.19 J/par`
- potencia media: `76.28 W`
- pico de potencia: `144.04 W`

## FLOPs

Nesta rodada, nenhuma medicao de `FLOPs` foi encontrada no workspace da Jetson para os modelos concluidos.

Consequencias:

- o grafico comparativo marca `FLOPs` como `N/D`
- a tabela final ainda precisa de probes dedicados para calcular `FLOPs` e `J/GFLOP`

## Artefatos De Analise Gerados

- tabela enriquecida:
  - `reports/initial_table/initial_table_120w_full/summary_enriched.csv`
- plot consolidado:
  - `reports/initial_table/initial_table_120w_full/initial_table_120w_full_plot.png`
- script reprodutivel:
  - `scripts/analysis/plot_initial_table.py`

## Decisao Sobre Rerun

Nao ha necessidade imediata de rerodar `Depth Anything V2` e `FoundationStereo` apenas para recuperar tempo e energia.

Os dados validos ja existentes permitem:

- corrigir throughput
- completar `J/item`
- fazer backfill da tabela
- adicionar `FLOPs` offline depois

Um rerun completo so passa a valer a pena quando:

- os quatro runners faltantes estiverem prontos
- o pipeline da tabela ja registrar `processed_items` corretamente
- houver interesse em uma tabela final regenerada de ponta a ponta em uma mesma janela termica
