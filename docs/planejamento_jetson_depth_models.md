# Planejamento de Docker e Inferencia na Jetson

## Objetivo

Organizar a execucao de inferencia dos modelos `Depth Anything V2`, `Depth Anything 3`, `Depth Pro`, `Marigold`, `FoundationStereo` e `IGEV` em Jetson, com:

- containers reproduziveis;
- execucao padronizada de inferencia;
- metricas numericas de depth;
- metricas de custo computacional e energetico;
- logs suficientes para comparacao entre modelos.

Assumicao usada neste documento:

- interpretei `jflops` como eficiencia energetica normalizada por FLOPs, isto e, `J/GFLOP`;
- se voce estiver usando uma ferramenta especifica com esse nome, vale alinhar antes da implementacao final.

## Inventario inspecionado

### 1. Depth Anything V2

- Pasta: `/home/pdi-b06/almacen/Depth-Anything-V2`
- Checkpoints encontrados: `depth_anything_v2_vits.pth`, `depth_anything_v2_vitb.pth`, `depth_anything_v2_vitl.pth`
- Script principal de inferencia: `run.py`
- Script de video: `run_video.py`
- Dataset local identificado: `datasets/suim`
- Metricas existentes:
  - `metrics_no_gt.py`
  - `metric_depth/run.py`
  - `metric_depth/util/metric.py`
- Saida atual:
  - colorida em `outputs/.../color`
  - grayscale em `outputs/.../grayscale`

Observacoes:

- O `run.py` ja salva depth em grayscale, o que facilita comparacao automatica.
- O script tambem gera log de ambiente com Python, CUDA e `pip freeze`.
- Dependencias sao enxutas e esse e um dos candidatos mais simples para portar.

### 2. Depth Anything 3

- Pasta: `/mnt/almacen/Sorriso1909/depth-anything-3`
- Scripts de inferencia e avaliacao encontrados:
  - `src/depth_anything_3/infer_run.py`
  - `src/depth_anything_3/infer_metric.py`
  - `src/depth_anything_3/eval_no_gt_underwater.py`
  - `src/depth_anything_3/bench/batch_eval_models.py`
- Datasets locais identificados:
  - `datasets/train_uieb/{rgb,depth}`
  - `datasets/val_uieb/{rgb,depth}`
  - `datasets/val_suim/rgb`
  - `datasets/val_usis10k/rgb`
  - geracoes grayscale em `datasets/gray_images/...`
- Metricas existentes:
  - `compare_no_gt_metrics.py`
  - `eval_no_gt_underwater.py`
  - bench interno em `src/depth_anything_3/bench`

Observacoes:

- O `infer_run.py` esta hardcoded para `device = "cuda"`, `model_name = "da3-large"` e `batch_size = 8`.
- As dependencias sao bem pesadas para Jetson: `torch>=2`, `xformers`, `open3d`, `pycolmap`, `fastapi`, `uvicorn`.
- O caminho hardcoded dentro de `eval_no_gt_underwater.py` usa `/home/pdi5060ti/...`, diferente da pasta real atual.

### 3. Depth Pro

- Pasta: `/home/pdi-b06/sorriso_07/ml-depth-pro`
- Script principal de inferencia: `src/depth_pro/cli/run.py`
- Script de metricas sem ground truth: `src/depth_pro/metrics_no_gt.py`
- Datasets locais identificados:
  - `datasets/suim`
  - provavelmente tambem `datasets/uieb` e `datasets/usis10k`, pois sao referenciados no script de metricas
- Saidas identificadas:
  - `outputs/depth-pro/...`
  - `outputs/depth-pro/metrics_results/depthpro_metrics.csv`

Observacoes:

- O `run.py` salva depth colorido em `Spectral_r`, nao depth numerico bruto.
- O script de metricas espera pastas `_bw`, entao hoje existe uma dependencia implicita de uma etapa de conversao para grayscale.
- A inferencia usa `precision=torch.half`, o que e bom para Jetson, mas precisa validacao por modelo e JetPack.

### 4. Marigold

- Pasta: `/mnt/HD2/Marigold`
- Script de inferencia depth: `script/depth/infer.py`
- Scripts de avaliacao:
  - `script/depth/eval.py`
  - `script/depth/metrics.py`
  - varios shells em `script/depth/eval/*.sh`
- Configs de dataset:
  - `config/dataset_depth/*.yaml`
- Metrica sem ground truth customizada: `no_gt_metrica.py`

Observacoes:

- O script de inferencia usa `diffusers` e pipeline diffusion, entao deve ser o modelo mais caro em Jetson.
- O script atual pergunta interativamente se o diretorio de saida ja existe, o que nao serve para pipeline automatizado.
- O `BASE_PATH` de `no_gt_metrica.py` aponta para `/home/pdi-b06/Marigold`, mas a pasta real esta em `/mnt/HD2/Marigold`.
- A saida numerica e `.npy`, o que e excelente para metricas sem perda por colormap.

### 5. FoundationStereo

- Pasta: `/home/pdi-b06/f_s_sorriso96/FoundationStereo`
- Scripts identificados:
  - `scripts/infer_run.py`
  - `scripts/run_demo.py`
  - `scripts/run_demo_batch.py`
  - `scripts/run_demo_tensorrt.py`
  - `scripts/stereo_run.py`
- Dataset local identificado:
  - `datasets/uwstereo/images`
  - `datasets/uwstereo/disparity`
- Material Jetson ja existente:
  - `readme_jetson.md`
  - `docker/dockerfile`
  - `docker/run_container.sh`

Observacoes:

- Este projeto ja tem caminho claro para Jetson e para TensorRT.
- O `readme_jetson.md` sugere fluxo baseado em `isaac_ros_dev-aarch64`.
- O `docker/dockerfile` atual nao e Jetson-ready: usa imagem `nvidia/cuda` x86, instalador `Miniconda3-latest-Linux-x86_64.sh` e pacotes pensados para desktop.
- Para Jetson, esse Dockerfile precisa ser refeito, nao apenas ajustado.

### 6. IGEV Stereo

- Pasta: `/mnt/HD2/IGEV/IGEV-Stereo`
- Scripts identificados:
  - `infer_run_depth.py`
  - `demo_imgs.py`
  - `demo_video.py`
  - `evaluate_stereo.py`
  - `metrics_no_gt.py`
- Dataset local identificado:
  - `uwstereo/images/val/left`
  - `uwstereo/images/val/right`
- Dependencias congeladas em `requirements_instaladas.txt`

Observacoes:

- O projeto esta preso a stack antiga `torch==1.12.1+cu113`.
- Isso aumenta o risco de incompatibilidade com JetPack 6.
- O modelo salva depth tanto em imagem quanto opcionalmente em `.npy`, o que ajuda na avaliacao.

## Metricas de depth ja existentes

Ha uma padronizacao boa nos scripts customizados de voces. Os modelos monoculares compartilham tres metricas sem ground truth:

- `Edge Align (↑)`: alinhamento entre bordas RGB e gradiente do mapa de depth;
- `Smoothness (↓)`: suavidade local por diferencas espaciais;
- `EdgeAwareSmooth (↓)`: suavidade ponderada por bordas da imagem RGB.

Isso aparece em:

- `Depth Anything V2`
- `Depth Anything 3`
- `Depth Pro`
- `Marigold`
- `IGEV`

Conclusao pratica:

- vale transformar essas tres metricas num modulo unico, para evitar divergencia de implementacao;
- `FoundationStereo` deve entrar no mesmo pipeline de metricas se a saida final for depth/disparity convertida para formato comum;
- `Marigold` e `IGEV` ja sao bons candidatos para analise numerica usando `.npy`.

## Riscos e inconsistencias encontradas antes de dockerizar

### Riscos tecnicos

- `FoundationStereo/docker/dockerfile` e x86, nao aarch64.
- `IGEV` depende de PyTorch/CUDA antigos.
- `Marigold` tende a ser pesado demais para inferencia confortavel sem tuning de resolucao, precision e batch.
- `Depth Anything 3` tem dependencias grandes que podem inviabilizar uma imagem unica para todos os modelos.

### Pontos que quebram automacao hoje

- caminhos hardcoded para maquinas antigas em scripts de metricas;
- prompts interativos no `Marigold`;
- mistura de saida colorida e saida numerica em alguns modelos;
- ausencia de interface CLI unica para todos os modelos;
- logs de ambiente heterogeneos.

## Estrategia recomendada de Docker

### Diretriz principal

Nao recomendo uma unica imagem gigante para os seis modelos.

Recomendo:

1. uma imagem base Jetson comum;
2. tres familias de imagens derivadas;
3. uma CLI de benchmark comum por fora.

### Familia de imagens

#### Imagem base

- Nome sugerido: `depth-jetson-base`
- Base sugerida:
  - `nvcr.io/nvidia/l4t-pytorch:<tag-compativel-com-o-jetpack>`
  - ou `isaac_ros_dev-aarch64` se a Jetson ja estiver padronizada em Isaac ROS
- Conteudo:
  - Python
  - PyTorch compativel com JetPack/L4T
  - OpenCV
  - numpy, scipy, pandas, matplotlib
  - utilitarios de benchmark

#### Imagem 1: modelos monoculares leves

- Nome sugerido: `depth-jetson-mono`
- Modelos:
  - Depth Anything V2
  - Depth Anything 3
  - Depth Pro

Motivo:

- todos sao PyTorch monocular;
- compartilham parte do pipeline de metricas;
- permitem um runner comum de inferencia em imagem unica.

#### Imagem 2: diffusion

- Nome sugerido: `depth-jetson-marigold`
- Modelo:
  - Marigold

Motivo:

- dependencias de `diffusers/transformers/accelerate` merecem isolamento;
- evita contaminar a imagem dos modelos mais simples;
- facilita testes de performance e energia sem ruido de stack extra.

#### Imagem 3: stereo

- Nome sugerido: `depth-jetson-stereo`
- Modelos:
  - FoundationStereo
  - IGEV

Motivo:

- ambos usam pares left/right;
- ambos pedem tratamento proprio de dataset;
- `FoundationStereo` ainda pode ter variante TensorRT separada.

#### Imagem 4 opcional: TensorRT dedicado

- Nome sugerido: `depth-jetson-foundation-trt`
- Modelo:
  - FoundationStereo TensorRT

Motivo:

- benchmarking mais limpo entre PyTorch e TensorRT;
- evita conflito de dependencias de conversao/engine.

## Estrutura recomendada no host Jetson

```text
/workspace/depth-bench/
  docker/
    base/
    mono/
    marigold/
    stereo/
    foundation_trt/
  repos/
    Depth-Anything-V2/
    depth-anything-3/
    ml-depth-pro/
    Marigold/
    FoundationStereo/
    IGEV/
  data/
    suim/
    uieb/
    usis10k/
    uwstereo/
  outputs/
    da2/
    da3/
    depthpro/
    marigold/
    foundation/
    igev/
  benchmarks/
    logs/
    reports/
```

## Interface unica de inferencia

Recomendo criar um runner padrao por modelo com esta interface:

```bash
python tools/run_inference.py \
  --model da2 \
  --input /workspace/depth-bench/data/suim \
  --output /workspace/depth-bench/outputs/da2/suim \
  --variant vitb \
  --device cuda \
  --save-npy \
  --save-png
```

Com a mesma ideia para todos:

- `--model {da2,da3,depthpro,marigold,foundation,igev}`
- `--input`
- `--output`
- `--dataset-name`
- `--save-png`
- `--save-npy`
- `--height/--width` ou `--input-size`
- `--fp16`
- `--batch-size`

## Metricas novas a adicionar

### 1. FLOPs

Objetivo:

- medir custo teorico por inferencia em resolucao fixa.

Recomendacao:

- usar `calflops`, `ptflops` ou `thop` dentro do codigo PyTorch do modelo;
- medir por resolucao fixa e registrar o shape usado;
- guardar:
  - FLOPs
  - MACs
  - numero de parametros

Padrao recomendado por benchmark:

- `input_shape`
- `flops_g`
- `macs_g`
- `params_m`

Observacao importante:

- para `FoundationStereo TensorRT`, os FLOPs devem vir da versao PyTorch ou ONNX de referencia;
- o TensorRT entra como comparacao de latencia e energia, nao como fonte principal do FLOP teorico.

### 2. Runtime

Medir:

- tempo total;
- latencia media por imagem;
- `p50`, `p95`, `p99`;
- FPS;
- numero de warmups;
- numero de imagens validas processadas.

### 3. Memoria e uso de GPU

Medir:

- RAM usada;
- uso de GPU;
- frequencia de GPU;
- frequencia EMC;
- temperatura.

Fonte:

- `tegrastats`

### 4. Energia

Medir:

- potencia media da placa;
- potencia maxima;
- energia total em joules;
- energia por imagem;
- eficiencia `J/GFLOP`.

Fonte:

- `tegrastats`, preferindo `VDD_IN` ou `POM_5V_IN` quando disponivel.

Formula recomendada:

- `energia_total_j = integral(potencia_w * dt)`
- `energia_por_imagem = energia_total_j / num_imagens`
- `j_por_gflop = energia_total_j / (num_imagens * flops_g)`

## Pipeline de benchmark recomendado

### Etapa 0. Descobrir a stack real da Jetson

Coletar no host:

- modelo da Jetson;
- JetPack;
- L4T;
- CUDA;
- cuDNN;
- TensorRT;
- se `tegrastats` funciona no host;
- se `jetson-stats/jtop` esta instalado no host.

Sem isso, nao vale fechar a tag da imagem base.

### Etapa 1. Padronizar datasets

Criar convencao unica:

- monocular RGB:
  - `data/<dataset>/rgb/*.jpg`
- monocular GT depth opcional:
  - `data/<dataset>/depth/*.png|*.npy`
- stereo:
  - `data/<dataset>/left/*.png`
  - `data/<dataset>/right/*.png`
  - `data/<dataset>/disp/*.png|*.npy`

### Etapa 2. Normalizar saídas

Cada modelo deve exportar:

- preview colorido opcional;
- depth numerico em `.npy`;
- depth em grayscale `.png` quando fizer sentido;
- metadados por execucao em JSON.

Campos minimos por execucao:

- modelo
- variante/checkpoint
- resolucao
- precision
- batch_size
- device
- dataset
- total_imagens
- tempo_total_s

### Etapa 3. Inserir benchmark wrapper

Usar wrapper externo para:

- iniciar `tegrastats`;
- executar inferencia;
- parar `tegrastats`;
- gerar sumario JSON/CSV.

Os scripts base deste workspace foram criados exatamente para isso:

- `scripts/benchmark/run_with_tegrastats.sh`
- `scripts/benchmark/summarize_tegrastats.py`
- `scripts/benchmark/flops_probe_template.py`

### Etapa 4. Comparar modelos

Relatorio final por dataset/modelo deve conter:

- metricas de depth;
- latencia;
- FPS;
- memoria;
- energia total;
- energia por imagem;
- FLOPs;
- `J/GFLOP`.

## Ordem recomendada de implementacao

### Fase 1

- Docker base Jetson
- Wrapper de benchmark
- Portar `Depth Anything V2`

### Fase 2

- Portar `Depth Pro`
- Portar `Depth Anything 3`

### Fase 3

- Portar `FoundationStereo`
- depois criar variante TensorRT

### Fase 4

- Portar `IGEV`
- resolver compatibilidade de stack antiga

### Fase 5

- Portar `Marigold`
- fazer tuning agressivo para resolucao e precision

## Priorizacao pratica

Se o objetivo for provar a pipeline na Jetson rapido, eu seguiria nesta ordem:

1. `Depth Anything V2`
2. `Depth Pro`
3. `FoundationStereo`
4. `Depth Anything 3`
5. `IGEV`
6. `Marigold`

Motivos:

- `DA2` e simples e ja salva grayscale;
- `Depth Pro` e monocular e relativamente controlavel;
- `FoundationStereo` ja tem direcionamento para Jetson e TensorRT;
- `DA3` pode exigir poda de dependencias;
- `IGEV` tem risco de compatibilidade de stack;
- `Marigold` deve ser o mais pesado energeticamente.

## Ajustes necessarios antes de congelar a versao Jetson

- remover caminhos absolutos hardcoded;
- eliminar prompts interativos;
- padronizar exportacao em `.npy` e `.png`;
- unificar as tres metricas no-reference em um unico modulo;
- adicionar um formato unico de sumario JSON por execucao;
- definir resolucoes-alvo para comparacao justa;
- registrar warmup separado da inferencia medida.

## Entregaveis sugeridos

### Entregavel 1

- `docker/base/Dockerfile`
- `docker/mono/Dockerfile`
- `docker/marigold/Dockerfile`
- `docker/stereo/Dockerfile`

### Entregavel 2

- `tools/run_inference.py`
- `tools/run_metrics.py`
- `tools/run_benchmark.py`

### Entregavel 3

- `benchmarks/reports/summary.csv`
- `benchmarks/reports/summary.json`

## Decisao tecnica mais importante

Antes de escrever qualquer Docker final, vale confirmar no host Jetson:

- modelo da placa;
- `JetPack` e `L4T`;
- se a estrategia vai seguir `l4t-pytorch` ou `isaac_ros_dev-aarch64`.

Essa decisao muda completamente a imagem base, principalmente para `FoundationStereo` e `IGEV`.
