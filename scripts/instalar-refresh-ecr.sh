#!/usr/bin/env bash
# Roda NO SERVER k3s (via SSM, a cada deploy). Instala um timer que recria o
# Secret docker-registry "ecr-creds" do namespace da Execucao a cada 6h.
#
# O token do ECR expira em 12h: sem o timer, um pod recriado depois disso (HPA,
# no substituido) nao conseguiria baixar a imagem. O timer do user_data do
# InfraKubernete so cobre o namespace do monolito, e mudar aquele user_data
# recriaria o server - por isso a Execucao instala o proprio, idempotente.
#
# Uso: instalar-refresh-ecr.sh <regiao> <registry> <namespace>
set -euo pipefail

REGIAO="${1:?informe a regiao}"
REGISTRY="${2:?informe o registry do ECR}"
NAMESPACE="${3:?informe o namespace}"
NOME="refresh-ecr-creds-${NAMESPACE}"

cat > "/opt/${NOME}.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SENHA="\$(aws ecr get-login-password --region "${REGIAO}")"
/usr/local/bin/kubectl create secret docker-registry ecr-creds \\
  --namespace "${NAMESPACE}" \\
  --docker-server="${REGISTRY}" \\
  --docker-username=AWS \\
  --docker-password="\$SENHA" \\
  --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -
SCRIPT
chmod 700 "/opt/${NOME}.sh"

cat > "/etc/systemd/system/${NOME}.service" <<UNIT
[Unit]
Description=Atualiza o Secret docker-registry do ECR no namespace ${NAMESPACE}
After=k3s.service

[Service]
Type=oneshot
ExecStart=/opt/${NOME}.sh
UNIT

cat > "/etc/systemd/system/${NOME}.timer" <<TIMER
[Unit]
Description=Roda ${NOME}.service a cada 6 horas

[Timer]
OnBootSec=2min
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now "${NOME}.timer"
echo "Timer ${NOME} instalado."
