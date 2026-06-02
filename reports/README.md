# Reports

## Pastas versionadas

Os arquivos em:

- `reports/initial_table/initial_table_120w_full/`

sao artefatos historicos versionados no repositório. Eles servem como baseline
documental da rodada inicial analisada localmente.

## Pastas puxadas da Jetson

Os resultados novos puxados automaticamente da Jetson devem ficar em:

- `reports/pulled_from_jetson/initial_table/<label>/`

Essa pasta e a copia local dos relatórios gerados em:

- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/`

na Jetson.

## Regra pratica

- `reports/initial_table/...`:
  use para artefatos historicos que fazem parte da documentacao do repositório.
- `reports/pulled_from_jetson/...`:
  use para resultados novos, experimentais e regenerados da Jetson.

## Caminhos canônicos atuais

Na Jetson:

- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/`

Nesta maquina:

- `reports/pulled_from_jetson/initial_table/<label>/`

Arquivos principais esperados em ambos:

- `summary_enriched.csv`
- `<label>_plot.png`
- `table_publication.tex`
- `summary_monocular_enriched.csv`
- `<label>_monocular_plot.png`
- `table_publication_monocular.tex`
- `summary_stereo_enriched.csv`
- `<label>_stereo_plot.png`
- `table_publication_stereo.tex`
- `report_manifest.json`

## Rodada de referencia atual

Em `2026-06-02`, a rodada local de referencia passou a ser:

- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/`

Essa pasta ja contem:

- os 6 modelos com `status=completed`;
- `flops.json` em cada subpasta de modelo;
- tabela combinada;
- tabela monocular;
- tabela stereo;
- PNG e LaTeX para os tres quadros.

Arquivos principais:

- `summary_enriched.csv`
- `initial_table_120w_full_v5_plot.png`
- `table_publication.tex`
- `summary_monocular_enriched.csv`
- `initial_table_120w_full_v5_monocular_plot.png`
- `table_publication_monocular.tex`
- `summary_stereo_enriched.csv`
- `initial_table_120w_full_v5_stereo_plot.png`
- `table_publication_stereo.tex`

## Observacao sobre copia de labels

Se voce criar um novo label copiando a pasta de outro relatorio:

- apague `summary.csv`, `summary.json`, `summary.jsonl` e `summary_enriched*` antes de refinalizar;
- mantenha apenas as subpastas dos modelos e seus artefatos.

Isso evita que `report_dir` herdado do label antigo faça o backfill ler `flops.json`
ou logs de outra rodada.
