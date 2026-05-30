# Initial Table 120W Full

Fonte: `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full` na Jetson Thor, consultado em `2026-05-30`.

## Cobertura

- Modelos previstos na tabela: 6
- Modelos concluídos: 2
- Modelos ainda sem runner Jetson: 4

Concluídos:

- `Depth Anything V2`
- `FoundationStereo`

Pendentes:

- `Depth Anything V3`
- `Depth Pro`
- `Marigold`
- `IGEV`

## Leitura Inicial

- `Depth Anything V2` completou `4225` imagens reais em `696.21 s`, com throughput corrigido de `6.07 imagens/s`.
- `FoundationStereo` completou `276` pares reais em `1147.62 s`, com throughput corrigido de `0.24 pares/s`.
- `FoundationStereo` consumiu mais energia por item e teve potência média/pico mais altos do que `Depth Anything V2`.
- Não há medição de `FLOPs` registrada nesta rodada; por isso o comparativo de eficiência computacional ainda está incompleto.

## Métricas Derivadas

Observacao importante:

- o campo `samples` no `summary.csv` original corresponde a amostras do `tegrastats`, nao a imagens processadas
- para esta analise, o throughput foi recalculado com contagem real dos artefatos gerados

- `Depth Anything V2`: `4225` imagens reais, `6.07 imagens/s`, `8.79 J/img`, `37.16 kJ` totais, `53.37 W` médios, `86.08 W` de pico.
- `FoundationStereo`: `276` pares reais, `0.24 pares/s`, `317.19 J/par`, `87.54 kJ` totais, `76.28 W` médios, `144.04 W` de pico.

## Integridade da Execução

- `Depth Anything V2`: `run_meta.json` com `exit_code = 0`
- `FoundationStereo`: `run_meta.json` com `exit_code = 0`
- Os quatro modelos restantes não falharam nessa rodada; eles simplesmente não foram executados porque ainda constam como `runner_pending`.
