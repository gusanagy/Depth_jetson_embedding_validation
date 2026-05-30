# Revisao Cientifica Da `initial_table_120w_full`

## Veredito

Os dados atuais sao adequados como:

- relatorio preliminar de viabilidade na Jetson Thor
- evidencia de que os runners `Depth Anything V2` e `FoundationStereo` estao operacionais
- base inicial para discutir energia, duracao e estabilidade da execucao

Os dados atuais **nao** sao suficientes, sozinhos, para sustentar uma comparacao cientifica final entre todos os modelos.

## O Que Esta Coerente

- ambos os modelos concluidos possuem `exit_code = 0`
- tempo total e energia total foram medidos com o mesmo wrapper de `tegrastats`
- a correcao de throughput foi refeita com contagem real dos artefatos
- os valores derivados de `J/item` batem com `energia total / itens processados`
- os resultados locais e os logs da Jetson estao consistentes entre si

## O Que Ainda Impede Uma Tabela Cientifica Final

### 1. Cobertura incompleta

A tabela planejada tem 6 modelos, mas so 2 foram realmente executados:

- `Depth Anything V2`
- `FoundationStereo`

Os demais continuam como `runner_pending`.

Atualizacao de repositorio em `2026-05-30`:

- os runners de `Depth Anything V3`, `Depth Pro`, `Marigold` e `IGEV` ja foram adicionados ao repositório
- esta revisao continua valida para a rodada historica `initial_table_120w_full`, que ainda nao foi regenerada com esses quatro modelos

### 2. Tarefas diferentes

Os dois resultados concluidos nao sao diretamente equivalentes:

- `Depth Anything V2` e monocular
- `FoundationStereo` e estereo

Mesmo quando se usa `J/item`, o item medido nao e o mesmo:

- imagem monocular
- par estereo

Para publicacao, isso pede:

- ou tabelas separadas por familia de tarefa
- ou uma secao metodologica deixando claro que a comparacao e apenas operacional, nao de eficiencia algoritmica direta

### 3. Escopos de dataset diferentes

- `Depth Anything V2`: `all_datasets_full`
- `FoundationStereo`: `uwstereo_val_full`

Isso significa que energia total e duracao total nao devem ser comparadas como se medissem o mesmo workload.

### 4. Sem repeticoes

A rodada atual parece ser uma execucao unica por modelo.

Para publicacao, o ideal e:

- pelo menos 3 repeticoes por modelo
- com warm-up padronizado
- reportando media e desvio padrao, ou media e intervalo

### 5. FLOPs ausentes

Sem `FLOPs`, ainda faltam:

- custo computacional normalizado
- `J/GFLOP`
- comparacao mais robusta de eficiencia energetica

### 6. Significado de `120W` vs pico

O modo de potencia configurado foi `120W`, mas o `FoundationStereo` mostrou pico de `144.04 W`.

Isso nao invalida o dado, mas precisa ser descrito corretamente:

- esse pico vem da telemetria instantanea da rail `VIN`
- ele nao deve ser interpretado como um novo "modo nominal" da placa

## Recomendacao Para O Texto Cientifico

No estado atual, eu trataria esta tabela como:

- `benchmark preliminar de portabilidade e custo energetico em Jetson Thor`

e nao como:

- `comparacao final entre todos os modelos de depth`

## Numeros Que Podem Ser Citados Com Seguranca

### `Depth Anything V2`

- `4225` imagens
- `696.21 s`
- `6.07 imagens/s`
- `37.16 kJ`
- `8.80 J/img`
- `53.37 W` medios
- `86.08 W` de pico

### `FoundationStereo`

- `276` pares
- `1147.62 s`
- `0.24 pares/s`
- `87.54 kJ`
- `317.19 J/par`
- `76.28 W` medios
- `144.04 W` de pico

## Proxima Versao Publicavel

Para ficar adequado a uma tabela principal de artigo, faltam:

1. completar os 4 runners restantes
2. corrigir o pipeline da tabela para salvar `processed_items` nativamente
3. medir `FLOPs`
4. repetir cada experimento
5. separar a apresentacao por familia:
   - monocular
   - estereo
