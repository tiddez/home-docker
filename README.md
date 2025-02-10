# Docker Compose Scripts for my Home Server
This is my personal config. You will need to tweak it to your needs.

Example of usage:

```sh
scp * bbsa@docker:/mnt/docker/
ssh bbsa@docker
cd /mnt/docker
docker compose -f infra-docker-compose.yml up -d
