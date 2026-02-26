
# context-lab42

A collaborative playground for experimenting with:
- Model Context Protocol (MCP)
- Junos automation
- Context-driven network workflows

This repo exists so we can test ideas, break things safely,
and avoid editing the CLI on a Friday.

> Friends don’t let friends edit the CLI.

# Step 1: install cRPD topology 

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

Load cRPD image: 
sudo docker load -i junos-routing-crpd-docker-amd64-24.4R2-S3.5.tgz


