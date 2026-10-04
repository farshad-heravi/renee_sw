# renee_sw

### Cloning and Building the packages
Use the following command to clone the repo and submodules inside your ws folder
```
mkdir src && cd src
git clone --recurse-submodules git@github.com:farshad-heravi/renee_sw.git
```

For the initial building, run
```
cd renee_sw
docker compose up builder
```

### GPU acceleration (optional)
By default, `docker compose up ...` runs everything CPU-only, which is functional 
on any machine but slow. If your host has an NVIDIA GPU, you can opt in to 
hardware-accelerated rendering with the `docker-compose.gpu.yaml` 
override — it's not applied unless you explicitly ask for it, so this is safe to 
skip on machines without a GPU.

**One-time host setup** (with the NVIDIA driver already installed):
```
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify the GPU is reachable from containers:
```
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```
This should print your GPU.

**Usage**: copy `.env.example` to `.env` and uncomment the `COMPOSE_FILE` line:
```
cp .env.example .env
```
Docker Compose reads `.env` automatically, so every plain `docker compose up ...` 
from then on picks up the GPU override — no extra flags needed. `.env` is 
host-specific and gitignored, so each machine (with or without a GPU) 
configures this independently.

Alternatively, without touching `.env`, you can opt in per-command with `-f`:
```
docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml up world-sim spawn-robot-sim
```

### How to use
For spawning the world and the robot
```
docker compose up world-sim spawn-robot-sim
```
you would see the following windows
<img width="1851" height="1174" alt="Screenshot from 2026-04-23 16-06-33" src="https://github.com/user-attachments/assets/c4094aa8-d5e2-498b-89ee-a330c584e47d" />


In the second terminal
```
docker compose up navigate-sim localize-sim
```

In the third terminal
```
docker compose up moveit
```

