## GRAFANA

Grafana roda na porta `:3001`. Login padrão: `admin` / (senha definida em `GF_SECURITY_ADMIN_PASSWORD`).

O datasource Prometheus já é provisionado automaticamente via `monitoring/provisioning/datasources/datasource.yaml` — não é necessário configurar manualmente.

Para adicionar dashboards, importe pelo ID no grafana.com (ex: `1860` para Node Exporter Full, `14282` para cAdvisor).

---

## PROMETHEUS

O arquivo de configuração está em `/home/docker/monitoring/prometheus.yml`. Os targets padrão são:
- `prometheus:9090` — próprio Prometheus
- `node-exporter:9100` — métricas do host
- `cadvisor:8080` — métricas dos containers

Para recarregar a configuração sem reiniciar:
```bash
curl -X POST http://localhost:9090/-/reload
```

---

## PIHOLE

O `systemd-resolved` está ocupando a porta **53**, impedindo que o Pi-hole inicie corretamente. Para resolver isso, você precisa desativar ou reconfigurar o `systemd-resolved`.

### 🔥 **1. Desativar o `systemd-resolved` (Recomendado para uso com Pi-hole)**
Se você quer que **somente o Pi-hole cuide do DNS**, desative o `systemd-resolved`:

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

Agora, remova o link simbólico do `resolv.conf`:
```bash
sudo rm /etc/resolv.conf
```

E crie um novo `resolv.conf` apontando para um DNS externo (exemplo: Cloudflare):
```bash
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

Agora reinicie o Pi-hole:
```bash
docker restart pihole
```

Verifique se está rodando:
```bash
docker logs pihole | tail -20
```

---

### 🛠 **2. Alterar a porta do `systemd-resolved` (Se não quiser desativá-lo)**
Se você precisa do `systemd-resolved`, pode configurá-lo para não usar a porta 53:

Abra o arquivo de configuração:
```bash
sudo nano /etc/systemd/resolved.conf
```
Encontre a linha:
```
#DNSStubListener=yes
```
Mude para:
```
DNSStubListener=no
```
Salve (`CTRL + X`, `Y`, `Enter`) e reinicie o serviço:
```bash
sudo systemctl restart systemd-resolved
```
Agora reinicie o Pi-hole:
```bash
docker restart pihole
```

---

### 🚀 **3. Testar o DNS**
Para verificar se o Pi-hole está funcionando como servidor DNS, use:
```bash
nslookup google.com 127.0.0.1
```
Se o Pi-hole estiver rodando corretamente, ele responderá à consulta.
