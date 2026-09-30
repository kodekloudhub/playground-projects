terraform version
aws --version

sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

# Refresh the shell's group membership for this session.
newgrp docker <<'DOCKER_CHECK'
docker version
docker run --rm hello-world
DOCKER_CHECK

aws sts get-caller-identity
aws configure get region
