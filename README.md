# Depth Jetson Embedding Validation

Este repositório organiza a avaliação de modelos de depth na `Jetson AGX Thor`,
com foco em:

- inferência reproduzível em Docker;
- medição de energia com `tegrastats`;
- cálculo de throughput real por item processado;
- medição de FLOPs por modelo;
- geração de tabelas combinadas, monoculares e stereo em `CSV`, `PNG` e `LaTeX`.

O fluxo principal foi construído para seis modelos:

- `Depth Anything V2`
- `Depth Anything V3`
- `Depth Pro`
- `Marigold`
- `FoundationStereo`
- `IGEV`

## Estado atual

O estado operacional mais importante hoje é a rodada:

- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/`

Essa rodada contém:

- os 6 modelos com `status=completed`;
- `flops.json` para os 6 modelos;
- tabela combinada;
- tabela monocular;
- tabela stereo;
- `PNG` e `LaTeX` para os três quadros.

Arquivos principais:

- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_enriched.csv`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication.tex`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_monocular_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication_monocular.tex`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_stereo_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication_stereo.tex`

## Estrutura do repositório

```text
docker/                  Dockerfiles Jetson
docs/                    documentação do fluxo e histórico
reports/                 resultados versionados e relatórios puxados da Jetson
scripts/analysis/        geração de plots e tabelas LaTeX
scripts/benchmark/       wrappers de tegrastats e benchmark
scripts/jetson/          runners, probes de FLOPs e automação da Jetson
```

Referências internas mais importantes:

- `docs/jetson_thor_setup.md`
- `docs/planejamento_completar_tabela_120w.md`
- `reports/README.md`

## Modelos e referências

Os modelos avaliados aqui são integrações Jetson de projetos externos. Os nomes
dos projetos originais usados no workspace e nos scripts são:

- `Depth-Anything-V2`
- `depth-anything-3`
- `ml-depth-pro`
- `Marigold`
- `FoundationStereo`
- `IGEV-Stereo`

No workspace da Jetson, eles ficam em:

- `~/Documents/depth_validation_workspace/external_models/Depth-Anything-V2`
- `~/Documents/depth_validation_workspace/external_models/depth-anything-3`
- `~/Documents/depth_validation_workspace/external_models/ml-depth-pro`
- `~/Documents/depth_validation_workspace/external_models/Marigold`
- `~/Documents/depth_validation_workspace/external_models/FoundationStereo`
- `~/Documents/depth_validation_workspace/external_models/IGEV/IGEV-Stereo`

## Como verificar os resultados disponíveis

No terminal, a forma mais rápida é:

```bash
cd /home/pdi_4/Documents/Documentos/depth_compare_sorriso

ls -lah reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5
sed -n '1,12p' reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_enriched.csv
find reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5 -maxdepth 2 -name flops.json | sort
```

Para ver os artefatos por modelo:

```bash
find reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5 -maxdepth 2 \
  \( -name run_meta.json -o -name tegrastats_summary.json -o -name flops.json \) | sort
```

## Como visualizar os resultados

Os arquivos `PNG` podem ser abertos com o visualizador da sua interface gráfica
preferida. Os caminhos mais úteis são:

- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_monocular_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_stereo_plot.png`

Se quiser só confirmar no terminal:

```bash
ls -lah \
  reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_plot.png \
  reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_monocular_plot.png \
  reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_stereo_plot.png
```

## Como regenerar os plots

Plot combinado:

```bash
cd /home/pdi_4/Documents/Documentos/depth_compare_sorriso

MPLCONFIGDIR=/tmp/mpl python3 scripts/analysis/plot_initial_table.py \
  --summary-json reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_enriched.json \
  --output reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_plot.png \
  --enriched-csv reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_enriched.csv \
  --title "Initial Table 120W Full V5 - Jetson Thor"
```

Plot monocular:

```bash
MPLCONFIGDIR=/tmp/mpl python3 scripts/analysis/plot_initial_table.py \
  --summary-json reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_monocular_enriched.json \
  --output reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_monocular_plot.png \
  --enriched-csv reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_monocular_enriched.csv \
  --task-filter monocular \
  --title "Initial Table 120W Full V5 - Monocular"
```

Plot stereo:

```bash
MPLCONFIGDIR=/tmp/mpl python3 scripts/analysis/plot_initial_table.py \
  --summary-json reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_stereo_enriched.json \
  --output reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_stereo_plot.png \
  --enriched-csv reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_stereo_enriched.csv \
  --task-filter stereo \
  --title "Initial Table 120W Full V5 - Stereo"
```

## Como regenerar o LaTeX

Tabela combinada:

```bash
python3 scripts/analysis/generate_initial_table_latex.py \
  --input-csv reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_enriched.csv \
  --output-tex reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication.tex \
  --caption "Energy, throughput and FLOPs results on Jetson AGX Thor in 120W mode." \
  --label tab:jetson_v5
```

Tabela monocular:

```bash
python3 scripts/analysis/generate_initial_table_latex.py \
  --input-csv reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_monocular_enriched.csv \
  --output-tex reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication_monocular.tex \
  --task-filter monocular \
  --caption "Monocular models on Jetson AGX Thor in 120W mode." \
  --label tab:jetson_v5_mono
```

Tabela stereo:

```bash
python3 scripts/analysis/generate_initial_table_latex.py \
  --input-csv reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_stereo_enriched.csv \
  --output-tex reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication_stereo.tex \
  --task-filter stereo \
  --caption "Stereo models on Jetson AGX Thor in 120W mode." \
  --label tab:jetson_v5_stereo
```

## Fluxo Jetson

Documentação completa:

- `docs/jetson_thor_setup.md`

Comandos mais importantes:

```bash
ssh PDI@10.230.88.175
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
git pull --ff-only origin main
```

Rodada segura com proteção térmica:

```bash
bash scripts/jetson/run_initial_table_safe.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --label initial_table_full_safe \
  --profile full \
  --thermal-max-temp-c 82 \
  --cooldown-sec 120
```

Finalização na Jetson:

```bash
bash scripts/jetson/finalize_initial_table_report.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --label initial_table_120w_full_v5
```

Pull automático para esta máquina:

```bash
bash scripts/jetson/run_initial_table_remote_and_pull.sh \
  --label initial_table_120w_full_v5 \
  --skip-run
```

## Observações importantes

- `reports/initial_table/...` contém artefatos históricos versionados do repositório.
- `reports/pulled_from_jetson/...` contém resultados novos trazidos da Jetson.
- Se um label novo for criado copiando outro relatório, apague `summary.csv`, `summary.json`, `summary.jsonl` e `summary_enriched*` antes de refinalizar.
- Os probes de FLOPs hoje cobrem os 6 modelos:
  - `run_depth_anything_v2_flops.sh`
  - `run_depth_anything_v3_flops.sh`
  - `run_depth_pro_flops.sh`
  - `run_marigold_flops.sh`
  - `run_foundation_stereo_flops.sh`
  - `run_igev_flops.sh`
