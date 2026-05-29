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

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/run_depth_anything_v2.sh --encoder vitb
```

`FoundationStereo`:

- processa apenas `val/left` e `val/right`
- se `FoundationStereo/datasets` nao existir, usa como fallback o `uwstereo/images/val` do `IGEV`

```bash
cd ~/Documents/depth_validation_workspace/depth_compare_sorriso
bash scripts/jetson/run_foundation_stereo.sh
```

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

Rodar benchmark com `tegrastats` por varios modos:

```bash
bash scripts/jetson/run_power_mode_benchmark.sh \
  --label da2_vitb \
  --modes 1,2,3 -- \
  bash scripts/jetson/run_depth_anything_v2.sh --dataset suim --encoder vitb
```

Observacao:

- na Jetson Thor validada aqui, `tegrastats` expõe `VIN`, `VIN_SYS_5V0`, `VDD_GPU` e `VDD_CPU_SOC_MSS`
- o parser foi ajustado para priorizar `VIN`, que representa melhor a potencia total da placa

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
- Marigold

Instala dependencias Python genericas para esse grupo.

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
4. Adaptar o runner de inferencia de cada modelo para gravar:
   - depth `.npy`
   - preview `.png`
   - metadata `.json`
5. Medir latencia e energia usando os scripts de benchmark ja existentes em `scripts/benchmark/`.

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
