
# context-lab42

A collaborative playground for experimenting with:
- Model Context Protocol (MCP)
- Junos automation
- Context-driven network workflows

This repo exists so we can test ideas, break things safely,
and avoid editing the CLI on a Friday.

> Friends don’t let friends edit the CLI.

# Step 1: install docker and load cRPD image

This lab is based on cRDP containers running on docker on an Ubutu server 22.04-LTS.

Install older Docker release :
sudo apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker
sudo apt update
sudo apt install ca-certificates curl gnupg -y

sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  jammy stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

apt-cache madison docker-ce

sudo apt install \
docker-ce=5:24.0.9-1~ubuntu.22.04~jammy \
docker-ce-cli=5:24.0.9-1~ubuntu.22.04~jammy \
containerd.io

sudo apt-mark hold docker-ce docker-ce-cli containerd.io

sudo usermod -aG docker $USER

newgrp docker

exit

Load cRPD image: 
docker load -i junos-routing-crpd-docker-amd64-24.4R2-S3.5.tgz

# Step 2: deploy cRPD topology

R1, R2 and R3 are backbone routers, R11 and R12 are CEs.

   +------R1-----+           
   |      |      |           
R11       |      R3-------R12
   |      |      |           
   +------R2-----+   

   
