# Jetson Thor Setup e Avaliacao

## Objetivo

Esta documentacao organiza o uso da Jetson `PDI@10.230.88.175` para:

- clonar este repositorio na Jetson;
- sincronizar os seis modelos do host antigo `pdi-b06@10.228.249.119`;
- preparar uma pasta de avaliacao unica;
- testar a criacao dos Dockerfiles-base para Jetson AGX Thor;
- deixar um caminho repetivel para benchmark e inferencia.

## Ambiente confirmado na Jetson

Coletado por SSH em `2026-05-29`:

- Hardware: `NVIDIA Jetson AGX Thor Developer Kit`
- OS: `Ubuntu 24.04.4 LTS`
- JetPack: `7.1-b112`
- L4T: `R38.4.0`
- Docker: `29.5.2`
- Docker Compose: `v5.1.4`
- Espaco livre aproximado em `/`: `592G`

## Layout recomendado de workspace

Padrao usado pelos scripts:

```text
~/Documents/depth_validation_workspace/
  depth_compare_sorriso/        <- este repositorio
  external_models/              <- copias dos seis modelos
  artifacts/
  docker_logs/
  reports/
    docker/
    metrics/
    tegrastats/
    jetson_environment.txt
```

## Modelos sincronizados

Origem:

- host: `pdi-b06@10.228.249.119`

Pastas mapeadas:

- `da2` -> `/home/pdi-b06/almacen/Depth-Anything-V2/`
- `da3` -> `/mnt/almacen/Sorriso1909/depth-anything-3/`
- `depthpro` -> `/home/pdi-b06/sorriso_07/ml-depth-pro/`
- `marigold` -> `/mnt/HD2/Marigold/`
- `foundation` -> `/home/pdi-b06/f_s_sorriso96/FoundationStereo/`
- `igev` -> `/mnt/HD2/IGEV/`

## Perfis de sincronizacao

O script `scripts/jetson/sync_models_from_popos.sh` suporta tres perfis:

- `full`: copia quase tudo, excluindo apenas `.git`, `venv` e caches Python.
- `code`: copia apenas codigo, excluindo datasets, outputs e pesos.
- `code_weights`: copia codigo + pesos/checkpoints, excluindo datasets e outputs.

Para o primeiro teste na Jetson, recomendo `code_weights`.

Para rodar inferencia real:

- modelos monoculares: use `full` para trazer as pastas inteiras de imagens dos datasets;
- `UWStereo`: rode apenas a parte `val`.

## Passo a passo

### 1. Entrar na Jetson

```bash
ssh PDI@10.230.88.175
```

### 2. Clonar ou atualizar este repositorio

```bash
mkdir -p ~/Documents/depth_validation_workspace
git clone https://github.com/gusanagy/Depth_jetson_embedding_validation.git \
  ~/Documents/depth_validation_workspace/depth_compare_sorriso
```

Se a pasta ja existir:

```bash
bash ~/Documents/depth_validation_workspace/depth_compare_sorriso/scripts/jetson/clone_or_update_repo.sh
```

### 3. Criar a estrutura do workspace e registrar o ambiente

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/bootstrap_eval_workspace.sh
```

Isso gera:

- diretorios `external_models`, `artifacts`, `docker_logs`, `reports`
- relatorio `reports/jetson_environment.txt`

### 4. Sincronizar os modelos do host antigo

Primeiro teste recomendado:

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/sync_models_from_popos.sh --profile code_weights
```

Para validar antes sem copiar:

```bash
bash scripts/jetson/sync_models_from_popos.sh --profile code_weights --dry-run
```

Para copiar apenas um modelo:

```bash
bash scripts/jetson/sync_models_from_popos.sh --profile code_weights --model da2
```

Para preparar os dois primeiros alvos de inferencia com os datasets necessarios:

```bash
bash scripts/jetson/sync_models_from_popos.sh --profile full --model da2
bash scripts/jetson/sync_models_from_popos.sh --profile full --model foundation
```

Observacao:

- o script usa `rsync` por `ssh`
- a Jetson vai pedir a senha do host antigo durante a sincronizacao

### 5. Testar a criacao dos Dockerfiles

Build completo:

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/build_docker_images.sh
```

Build de apenas uma imagem:

```bash
bash scripts/jetson/build_docker_images.sh --only base
```

Sem cache:

```bash
bash scripts/jetson/build_docker_images.sh --no-cache
```

Logs:

- `~/Documents/depth_validation_workspace/docker_logs/`

Observacao:

- se o usuario atual nao estiver no grupo `docker`, os scripts tentam usar `sudo -n docker` automaticamente
- na Jetson Thor validada aqui, o smoke test usa `--runtime=nvidia` em vez de `--gpus all`

### 6. Rodar smoke tests nas imagens

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/smoke_test_images.sh
```

Ou apenas:

```bash
bash scripts/jetson/smoke_test_images.sh --only mono
```

### 7. Rodar os primeiros modelos

`Depth Anything V2`:

- processa a pasta inteira de cada dataset encontrado em `datasets/`
- detecta automaticamente subpastas como `rgb/` e `images/`
- `--limit N` ajuda a fazer smoke test rapido antes de rodar a pasta inteira

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/run_depth_anything_v2.sh --encoder vitb
bash scripts/jetson/run_depth_anything_v2.sh --dataset val_suim --encoder vitb --limit 4
```

Saidas geradas:

- `~/Documents/depth_validation_workspace/artifacts/da2/<dataset>/<encoder>/`

`Depth Anything V3`:

- usa a imagem `depth-jetson-mono`
- faz fallback para os datasets do `Depth Anything V2` quando `depth-anything-3/datasets` nao estiver sincronizado
- tenta resolver checkpoint local automaticamente dentro de `external_models/depth-anything-3`
- aceita `--model-ref` para apontar um diretorio local de pesos ou um repo id explicito
- quando nao encontra pesos locais, mapeia aliases como `da3-large` para o repo id correto no Hugging Face, por exemplo `depth-anything/DA3-LARGE`
- salva `raw/.npy`, `grayscale/.png`, `color/.png` e `batch_run_info.json`
- instala shims locais para dependencias opcionais de exportacao 3D, como `open3d`, `pycolmap`, `plyfile`, `moviepy`, `trimesh` e `gsplat`, para nao bloquear a inferencia 2D

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/run_depth_anything_v3.sh --limit 4
bash scripts/jetson/run_depth_anything_v3.sh --dataset val_suim --model-name da3-large --limit 4
bash scripts/jetson/run_depth_anything_v3.sh --dataset val_suim --model-name da3-large --model-ref ~/Documents/depth_validation_workspace/external_models/depth-anything-3/checkpoints/da3-large --limit 4
```

Saidas geradas:

- `~/Documents/depth_validation_workspace/artifacts/da3/<dataset>/<variant>/`

FLOPs do `Depth Anything V3`:

```bash
bash scripts/jetson/run_depth_anything_v3_flops.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --dataset val_suim \
  --output-json ~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v4/depth_anything_v3/flops.json
```

FLOPs do `Depth Anything V2`:

```bash
bash scripts/jetson/run_depth_anything_v2_flops.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --dataset val_suim \
  --encoder vitb \
  --output-json ~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v5/depth_anything_v2/flops.json
```

`Depth Pro`:

- usa a imagem `depth-jetson-mono`
- faz fallback para os datasets do `Depth Anything V2` quando `ml-depth-pro/datasets` nao estiver sincronizado
- salva `raw/.npy`, `grayscale/.png`, `color/.png` e `batch_run_info.json`

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/run_depth_pro.sh --limit 4
bash scripts/jetson/run_depth_pro.sh --dataset val_suim --limit 4
```

Saidas geradas:

- `~/Documents/depth_validation_workspace/artifacts/depth_pro/<dataset>/`

FLOPs do `Depth Pro`:

```bash
bash scripts/jetson/run_depth_pro_flops.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --dataset val_suim \
  --output-json ~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v5/depth_pro/flops.json
```

`Marigold`:

- usa a imagem dedicada `depth-jetson-marigold`
- faz fallback para os datasets do `Depth Anything V2` quando `Marigold/datasets` nao estiver sincronizado
- salva apenas o depth bruto em `raw/.npy` e o `batch_run_info.json`

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/build_docker_images.sh --only marigold
bash scripts/jetson/run_marigold.sh --limit 2 --fp16
```

Saidas geradas:

- `~/Documents/depth_validation_workspace/artifacts/marigold/<dataset>/`

FLOPs do `Marigold`:

```bash
bash scripts/jetson/run_marigold_flops.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --dataset val_suim \
  --output-json ~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v5/marigold/flops.json
```

`FoundationStereo`:

- processa apenas `val/left` e `val/right`
- se `FoundationStereo/datasets` nao existir, usa como fallback o `uwstereo/images/val` do `IGEV`
- usa cache persistente para Hugging Face e `torch.hub` em `~/Documents/depth_validation_workspace/cache/foundation_stereo/`
- usa um shim de `open3d` apenas para inferencia 2D na Jetson; exportacao de nuvem de pontos continua fora desse wrapper
- carrega o modelo uma vez por lote, em vez de abrir um `docker run` por amostra
- mostra barra de progresso com `tqdm` por padrao; use `--no-progress` se quiser log puro
- usa `--ipc=host`, `--ulimit memlock=-1` e `--ulimit stack=67108864` para evitar o warning de SHMEM insuficiente do PyTorch
- reduz warnings repetitivos de `autocast` deprecado, `xFormers` ausente e logs verbosos do Hugging Face Hub

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/run_foundation_stereo.sh
bash scripts/jetson/run_foundation_stereo.sh --limit 4
bash scripts/jetson/run_foundation_stereo.sh --limit 4 --no-progress
```

Saidas geradas:

- `~/Documents/depth_validation_workspace/artifacts/foundation_stereo/val/<sample_id>/`
- `~/Documents/depth_validation_workspace/artifacts/foundation_stereo/val/batch_run_info.json`

FLOPs do `FoundationStereo`:

```bash
bash scripts/jetson/run_foundation_stereo_flops.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --output-json ~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v5/foundation_stereo/flops.json
```

`IGEV`:

- usa a imagem `depth-jetson-stereo`
- roda apenas `uwstereo/images/val`
- salva `raw_disparity/.npy`, `raw_depth/.npy`, `grayscale/.png`, `color/.png` e `batch_run_info.json`

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/run_igev.sh --limit 4
```

Saidas geradas:

- `~/Documents/depth_validation_workspace/artifacts/igev/val/`

FLOPs do `IGEV`:

```bash
bash scripts/jetson/run_igev_flops.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --output-json ~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v4/igev/flops.json
```

Observacoes para execucoes longas:

- `FutureWarning` de `torch.cuda.amp.autocast` indica API antiga no codigo do modelo, mas nao invalida a inferencia
- `xFormers is not available` indica perda de otimizacao, nao erro funcional
- aviso de `HF_TOKEN` so afeta limite de download; depois que o cache aquece ele tende a sumir
- `WARNING: CUDA Minor Version Compatibility mode ENABLED` indica desalinhamento entre driver e imagem CUDA, mas se o log mostrar `Device: cuda` e as imagens `_depth.png` estiverem sendo salvas, a execucao esta ativa
- os runners monoculares agora usam `--ipc=host`, `--ulimit memlock=-1` e `--ulimit stack=67108864`, para reduzir o warning de SHMEM do PyTorch
- se a execucao for interrompida com `Ctrl+C`, o wrapper pode registrar codigo `141`; isso nao significa falha do modelo, apenas termino interrompido com resultados parciais em disco

Suite inicial:

```bash
bash scripts/jetson/run_first_models_suite.sh
```

### 8. Benchmark por modo de potencia

Listar modos:

```bash
bash scripts/jetson/list_power_modes.sh
```

Trocar modo:

```bash
bash scripts/jetson/set_power_mode.sh 1
bash scripts/jetson/set_power_mode.sh 120W
```

Rodar benchmark com `tegrastats` por varios modos de uma vez:

```bash
bash scripts/jetson/run_power_mode_benchmark.sh \
  --label foundation_limit1 \
  --modes 0,1,2,3 -- \
  bash scripts/jetson/run_foundation_stereo.sh --limit 1
```

Esse wrapper agora:

- cria `plan.json`
- roda todos os modos que conseguem trocar em runtime
- para no primeiro modo que exigir reboot

### 9. Fluxo modular para continuar apos reboot

Preparar o plano:

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/prepare_power_mode_plan.sh \
  --label foundation_limit1_modular \
  --modes 0,1,2,3 -- \
  bash scripts/jetson/run_foundation_stereo.sh --limit 1
```

Rodar ate o proximo reboot obrigatorio:

```bash
bash scripts/jetson/resume_power_mode_plan.sh --label foundation_limit1_modular
```

Se o script parar dizendo que o proximo modo exige reboot:

1. reinicie a Jetson no modo desejado
2. confirme o modo atual:

```bash
bash scripts/jetson/get_current_power_mode.sh
```

3. continue o plano sem tentar trocar o modo de novo:

```bash
bash scripts/jetson/resume_power_mode_plan.sh \
  --label foundation_limit1_modular \
  --skip-set-mode
```

Se quiser rodar apenas um unico modo manualmente:

```bash
bash scripts/jetson/run_power_mode_once.sh \
  --label foundation_limit1_modular \
  --mode 2 \
  --skip-set-mode
```

Consolidar os resultados do plano:

```bash
python3 scripts/jetson/summarize_power_mode_results.py \
  --label foundation_limit1_modular
```

Observacao:

- na Jetson Thor validada aqui, `tegrastats` expõe `VIN`, `VIN_SYS_5V0`, `VDD_GPU` e `VDD_CPU_SOC_MSS`
- o parser foi ajustado para priorizar `VIN`, que representa melhor a potencia total da placa
- nos testes reais desta Thor, `MAXN` e `120W` trocaram em runtime; `90W` e `70W` pediram reboot
- o wrapper agora grava `energy_j`, `energy_joules`, `avg_power_w`, `peak_power_w` e marca como `skipped_reboot_required` os modos que nao podem trocar online
- `jgflops` so aparece quando houver um `flops.json` associado ao benchmark do modelo

### 10. Onde ficam os resultados

Saidas de inferencia:

- `Depth Anything V2`: `~/Documents/depth_validation_workspace/artifacts/da2/`
- `FoundationStereo`: `~/Documents/depth_validation_workspace/artifacts/foundation_stereo/`

Relatorios de benchmark por modo:

- raiz: `~/Documents/depth_validation_workspace/reports/tegrastats/<label>/`
- um diretorio por modo:
  - `0_MAXN_`
  - `1_120W_`
  - `2_90W_`
  - `3_70W_`

Arquivos principais por modo:

- `tegrastats.log`
- `run_meta.json`
- `command.stdout.log`
- `command.stderr.log`
- `tegrastats_summary.json`
- `flops.json` quando fornecido no plano
- `skipped.json` quando o modo exige reboot e ainda nao foi medido

Arquivos consolidados do plano:

- `plan.json`
- `summary.json`
- `summary.csv`

Resultados ja gerados nos testes desta maquina:

- `~/Documents/depth_validation_workspace/reports/tegrastats/foundation_limit1/`
- `~/Documents/depth_validation_workspace/reports/tegrastats/foundation_limit1_v2/`

### 11. Tabela inicial no modo de energia atual

Conferir o modo atual:

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/get_current_power_mode.sh
```

Gerar uma tabela inicial rapida no modo atual:

```bash
bash scripts/jetson/run_initial_table_current_mode.sh \
  --label initial_table_quick \
  --profile quick
```

Perfil `quick`:

- `Depth Anything V2`: roda `all` com `--limit 8` por dataset encontrado
- `Depth Anything V3`: roda `all` com `--limit 8` por dataset encontrado
- `Depth Pro`: roda `all` com `--limit 8` por dataset encontrado
- `Marigold`: roda `all` com `--limit 4` por dataset encontrado
- `FoundationStereo`: roda `uwstereo val` com `--limit 8`
- `IGEV`: roda `uwstereo val` com `--limit 8`

Gerar uma tabela inicial completa no modo atual:

```bash
bash scripts/jetson/run_initial_table_current_mode.sh \
  --label initial_table_full \
  --profile full
```

Perfil `full`:

- `Depth Anything V2`: roda todos os datasets encontrados sem `limit`
- `Depth Anything V3`: roda todos os datasets encontrados sem `limit`
- `Depth Pro`: roda todos os datasets encontrados sem `limit`
- `Marigold`: roda todos os datasets encontrados sem `limit`
- `FoundationStereo`: roda toda a validacao do `uwstereo`
- `IGEV`: roda toda a validacao do `uwstereo`

Comportamento atual do runner consolidado:

- se um modelo falhar, a tabela nao para imediatamente
- o status desse modelo entra como `failed`
- os modelos seguintes continuam
- quando um modelo conclui com sucesso, o runner tenta gerar `flops.json` automaticamente na pasta desse modelo
- se o probe de FLOPs falhar, a medicao de energia e preservada e o relatorio continua
- no fim, ainda e possivel gerar `summary_enriched`, `png` e `tex` do relatorio parcial

Arquivos da tabela inicial:

- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/context.json`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/summary.csv`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/summary.json`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/summary_enriched.csv`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/<label>_plot.png`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/table_publication.tex`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/report_manifest.json`

Relatorios detalhados por modelo:

- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/depth_anything_v2/`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/foundation_stereo/`

Cada pasta de modelo inclui:

- `tegrastats.log`
- `run_meta.json`
- `command.stdout.log`
- `command.stderr.log`
- `tegrastats_summary.json`
- `flops.json` quando o probe automatico estiver disponivel para o modelo

Se quiser desabilitar essa etapa automatica:

```bash
bash scripts/jetson/run_initial_table_current_mode.sh \
  --label initial_table_full \
  --profile full \
  --skip-flops
```

Se a placa estiver aquecendo demais, use protecao termica e cooldown:

```bash
bash scripts/jetson/run_initial_table_current_mode.sh \
  --label initial_table_full_safe_try \
  --profile full \
  --skip-flops \
  --thermal-max-temp-c 82 \
  --cooldown-sec 120
```

Esse modo:

- corta cada comando medido quando algum sensor do `tegrastats` atingir o limite configurado;
- registra `thermal_event.json` na pasta do modelo;
- espera entre uma etapa e outra para reduzir o pico termico acumulado.

Para a rodada longa mais segura, prefira o wrapper dedicado:

```bash
bash scripts/jetson/run_initial_table_safe.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --label initial_table_full_safe \
  --profile full \
  --thermal-max-temp-c 82 \
  --cooldown-sec 120
```

Esse wrapper separa o processo em tres fases:

1. energia e inferencia com protecao termica e sem auto-FLOPs;
2. probes de FLOPs um a um, tambem protegidos por `tegrastats`;
3. finalizacao do `summary_enriched`, PNG e LaTeX.

### 11.1 Estado pratico da `v5`

Em `2026-06-02`, a rodada `initial_table_120w_full_v5` foi fechada com:

- os 6 modelos completos em `120W`;
- `flops.json` presente para todos os 6 modelos;
- tabela combinada, monocular e stereo regeneradas;
- PNG e LaTeX gerados na Jetson e puxados para este repositório local.

Artefatos locais puxados da Jetson:

- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/summary_enriched.csv`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication.tex`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_monocular_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication_monocular.tex`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/initial_table_120w_full_v5_stereo_plot.png`
- `reports/pulled_from_jetson/initial_table/initial_table_120w_full_v5/table_publication_stereo.tex`

Observacao metodologica importante:

- se um novo label for criado por copia de outro relatorio antigo, remova `summary.csv`, `summary.json`, `summary.jsonl` e os arquivos `summary_enriched*` antes de refinalizar;
- isso evita carregar `report_dir` herdado do label antigo e garante que o backfill leia os `flops.json` corretos do novo label.

Observacao importante sobre a versao atual do pipeline:

- o campo `samples` do `summary.csv` original vem do `tegrastats`
- ele nao representa diretamente imagens ou pares processados
- para throughput real, use a analise corrigida e o CSV enriquecido citados abaixo

### 12. Analise local da `initial_table_120w_full`

Arquivos locais gerados a partir da rodada coletada na Jetson:

- `reports/initial_table/initial_table_120w_full/summary.json`
- `reports/initial_table/initial_table_120w_full/summary.csv`
- `reports/initial_table/initial_table_120w_full/summary_enriched.csv`
- `reports/initial_table/initial_table_120w_full/initial_table_120w_full_plot.png`

Documentos relacionados:

- `docs/analise_initial_table_120w_full.md`
- `docs/planejamento_completar_tabela_120w.md`

Scripts relacionados:

- `scripts/jetson/backfill_initial_table_report.py`
- `scripts/jetson/finalize_initial_table_report.sh`
- `scripts/jetson/run_initial_table_remote_and_pull.sh`
- `scripts/analysis/plot_initial_table.py`
- `scripts/analysis/generate_initial_table_latex.py`
- `scripts/analysis/split_initial_table_summary.py`

Para gerar `summary_enriched`, `png` e `tex` diretamente na Jetson depois do teste:

```bash
bash scripts/jetson/finalize_initial_table_report.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --label initial_table_120w_full_v2
```

Isso grava:

- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/summary_enriched.csv`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/initial_table_120w_full_v2_plot.png`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/table_publication.tex`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/summary_monocular_enriched.csv`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/initial_table_120w_full_v2_monocular_plot.png`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/table_publication_monocular.tex`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/summary_stereo_enriched.csv`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/initial_table_120w_full_v2_stereo_plot.png`
- `~/Documents/depth_validation_workspace/reports/initial_table/initial_table_120w_full_v2/table_publication_stereo.tex`

Se voce adicionar `flops.json` em qualquer pasta de modelo, por exemplo:

- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/depth_anything_v3/flops.json`
- `~/Documents/depth_validation_workspace/reports/initial_table/<label>/igev/flops.json`

basta rerodar:

```bash
bash scripts/jetson/finalize_initial_table_report.sh \
  --workspace-root ~/Documents/depth_validation_workspace \
  --label <label>
```

Isso atualiza os campos:

- `flops_g_per_item`
- `jgflops`

sem precisar repetir a medicao de energia.

Os probes atualmente disponiveis neste repositório cobrem os 6 modelos:

- `run_depth_anything_v2_flops.sh`
- `run_depth_anything_v3_flops.sh`
- `run_depth_pro_flops.sh`
- `run_marigold_flops.sh`
- `run_foundation_stereo_flops.sh`
- `run_igev_flops.sh`

Para rodar a partir desta maquina local e puxar automaticamente os resultados da Jetson:

```bash
bash scripts/jetson/run_initial_table_remote_and_pull.sh \
  --label initial_table_120w_full_v2 \
  --profile full
```

Esse wrapper:

- executa a tabela na Jetson
- finaliza o relatorio la
- copia o diretorio final para `reports/pulled_from_jetson/initial_table/<label>/` neste repositório local

Importante:

- esse comando deve ser executado nesta maquina local, dentro deste repositório
- ele nao deve ser executado de dentro da Jetson
- dentro da Jetson, o comando correto para fechar o relatorio e `finalize_initial_table_report.sh`

Ou seja, depois do pull automatico, nesta maquina os caminhos ficam:

- `reports/pulled_from_jetson/initial_table/<label>/summary_enriched.csv`
- `reports/pulled_from_jetson/initial_table/<label>/<label>_plot.png`
- `reports/pulled_from_jetson/initial_table/<label>/table_publication.tex`
- `reports/pulled_from_jetson/initial_table/<label>/summary_monocular_enriched.csv`
- `reports/pulled_from_jetson/initial_table/<label>/<label>_monocular_plot.png`
- `reports/pulled_from_jetson/initial_table/<label>/table_publication_monocular.tex`
- `reports/pulled_from_jetson/initial_table/<label>/summary_stereo_enriched.csv`
- `reports/pulled_from_jetson/initial_table/<label>/<label>_stereo_plot.png`
- `reports/pulled_from_jetson/initial_table/<label>/table_publication_stereo.tex`
- `reports/pulled_from_jetson/initial_table/<label>/report_manifest.json`

Organizacao recomendada:

- na Jetson, o local canonico dos relatórios gerados em runtime e sempre:
  - `~/Documents/depth_validation_workspace/reports/initial_table/<label>/`
- neste repositório local, artefatos historicos versionados ficam em:
  - `reports/initial_table/...`
- neste repositório local, resultados novos puxados automaticamente da Jetson ficam em:
  - `reports/pulled_from_jetson/initial_table/<label>/`

Isso evita misturar:

- baseline historico que faz parte da documentacao do repositório
- resultados experimentais novos puxados da Jetson

Regenerar o plot localmente:

```bash
python3 scripts/jetson/backfill_initial_table_report.py \
  --report-root reports/initial_table/initial_table_120w_full \
  --write-enriched-summary

MPLCONFIGDIR=/tmp/mpl python3 scripts/analysis/plot_initial_table.py \
  --summary-json reports/initial_table/initial_table_120w_full/summary_enriched.json \
  --output reports/initial_table/initial_table_120w_full/initial_table_120w_full_plot.png \
  --enriched-csv reports/initial_table/initial_table_120w_full/summary_enriched.csv \
  --title "Initial Table 120W Full - Jetson Thor"

python3 scripts/analysis/generate_initial_table_latex.py \
  --input-csv reports/initial_table/initial_table_120w_full/summary_enriched.csv \
  --output-tex reports/initial_table/initial_table_120w_full/table_publication.tex \
  --caption "Preliminary energy and throughput results on the Jetson AGX Thor in 120W mode." \
  --label tab:jetson_initial_120w
```

Separacao mono/stereo na finalizacao:

- a finalizacao preserva a tabela combinada antiga
- alem dela, agora tambem gera uma tabela monocular e outra stereo
- isso evita misturar tarefas diferentes no mesmo quadro principal do texto cientifico

Arquivos adicionais gerados por rodada:

- `summary_monocular_enriched.json/csv/jsonl`
- `summary_stereo_enriched.json/csv/jsonl`
- `<label>_monocular_plot.png`
- `<label>_stereo_plot.png`
- `table_publication_monocular.tex`
- `table_publication_stereo.tex`

Leitura atual dessa rodada:

- `Depth Anything V2` e `FoundationStereo` concluíram com dados energeticos validos
- a rodada historica `initial_table_120w_full` ainda mostra `Depth Anything V3`, `Depth Pro`, `Marigold` e `IGEV` como `runner_pending`
- a partir de `2026-05-30`, o repositorio passou a incluir runners para esses quatro modelos; falta executar uma nova rodada `120W` para preencher a tabela com eles
- `DA2` e `FoundationStereo` nao precisam de rerun imediato; a prioridade e completar os runners faltantes e corrigir o pipeline da tabela

Estado dessa analise em `2026-05-30`:

- `summary_enriched.json`
- `summary_enriched.csv`
- `summary_enriched.jsonl`
- `initial_table_120w_full_plot.png`
- `table_publication.tex`

ja foram regenerados tanto localmente quanto no workspace da Jetson

## Dockerfiles incluidos

### `docker/jetson/Dockerfile.base`

Base para Jetson/Thor usando:

- `nvcr.io/nvidia/pytorch:26.04-py3`

Esse valor foi escolhido por compatibilidade com JetPack `7.1`, seguindo a documentacao oficial da NVIDIA sobre PyTorch para Jetson e os containers NGC para iGPU/Jetson.

### `docker/jetson/Dockerfile.mono`

Camada inicial para modelos monoculares:

- Depth Anything V2
- Depth Anything 3
- Depth Pro

Instala dependencias Python genericas para esse grupo.

### `docker/jetson/Dockerfile.marigold`

Camada dedicada para:

- Marigold

Instala dependencias do stack `diffusers` separadas da imagem `mono`.

### `docker/jetson/Dockerfile.stereo`

Camada inicial para modelos estereo:

- FoundationStereo
- IGEV

Instala dependencias Python genericas para esse grupo.

## O que estes Dockerfiles fazem hoje

Eles sao uma base de validacao, nao a imagem final de producao dos modelos.

Objetivo deles:

- comprovar que a base NVIDIA escolhida sobe na Jetson Thor;
- validar `docker build`;
- validar imports essenciais (`torch`, `cv2`, `timm`, etc.);
- separar uma base `mono` e outra `stereo`.

## Proximo passo recomendado depois do smoke test

1. Sincronizar `code_weights` dos seis modelos.
2. Rodar build `base`, `mono` e `stereo`.
3. Escolher um primeiro alvo de inferencia:
   - `Depth Anything V2` para monocular
   - `FoundationStereo` para estereo
4. Rodar uma nova tabela `120W` com os seis modelos agora suportados.
5. Medir `FLOPs` offline por modelo e recalcular `J/GFLOP`.
6. Se necessario, rerodar a tabela final completa apos validar caches e warm-up.

Atualizacao de `2026-05-30`:

- `Depth Anything V2` e `FoundationStereo` ja tem runners funcionais e medicao em `120W`
- `Depth Anything V3`, `Depth Pro`, `Marigold` e `IGEV` agora tambem possuem runners Jetson no repositorio
- `Marigold` passou a usar container dedicado `depth-jetson-marigold`
- `IGEV` continua sendo o maior risco de compatibilidade por causa da stack PyTorch/CUDA antiga e merece smoke test separado na Thor
- a consolidacao da tabela precisa ser corrigida para separar `telemetry_samples` de `processed_items`

Atualizacao de `2026-06-01`:

- `DA3` passou a usar um shim local de `depth_anything_3.utils.export` para evitar que a stack de exportacao 3D bloqueie a inferencia 2D
- `IGEV` passou a aplicar um patch local e conservador em `timm.create_model` para tentar restaurar a interface esperada pelo backbone `mobilenetv2_100`
- os relatórios finalizados agora geram saidas separadas para `monocular` e `stereo`, em `CSV`, `JSON`, `PNG` e `LaTeX`

## Riscos conhecidos

- `Marigold` deve ser o mais pesado para a Jetson.
- `IGEV` provavelmente exigira mais cuidado por depender de stack PyTorch mais antiga.
- alguns repos antigos usam caminhos absolutos hardcoded e vao precisar pequenos ajustes depois da copia.

## Referencias oficiais

- PyTorch for Jetson Platform:
  - https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform-release-notes/pytorch-jetson-rel.html
- Installing PyTorch for Jetson Platform:
  - https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform/index.html
- NVIDIA PyTorch container:
  - https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch
