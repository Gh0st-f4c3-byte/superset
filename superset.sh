#!/bin/bash
set -e

echo "=== Apache Superset NO Docker | Instalación Completa ==="

# -------------------------------------------------
# 1. Hostname aleatorio
# -------------------------------------------------
RAND_NUM=$((RANDOM % 10 + 1))
HOSTNAME="superset-app-${RAND_NUM}"
hostnamectl set-hostname "$HOSTNAME"
echo "Hostname: $HOSTNAME"

# -------------------------------------------------
# 2. Detectar Ubuntu / Python
# -------------------------------------------------
UBUNTU_MAJOR=$(lsb_release -rs | cut -d. -f1)

if [ "$UBUNTU_MAJOR" -le 22 ]; then
    PYTHON_VERSION="3.10"
else
    PYTHON_VERSION="3.12"
fi

echo "Ubuntu $UBUNTU_MAJOR → Python $PYTHON_VERSION"

# -------------------------------------------------
# 3. Actualizar sistema
# -------------------------------------------------
apt update && apt upgrade -y

# -------------------------------------------------
# 4. Dependencias
# -------------------------------------------------
apt install -y \
  python${PYTHON_VERSION} \
  python${PYTHON_VERSION}-venv \
  python${PYTHON_VERSION}-dev \
  build-essential \
  libssl-dev \
  libffi-dev \
  pkg-config \
  git \
  curl \
  nodejs \
  npm \
  openssl

# -------------------------------------------------
# 5. Usuario superset
# -------------------------------------------------
if ! id superset &>/dev/null; then
    useradd -m -s /bin/bash superset
fi

# -------------------------------------------------
# 6. sudoers
# -------------------------------------------------
cat <<EOF > /etc/sudoers.d/superset
root ALL=(ALL) ALL
superset ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/superset

# -------------------------------------------------
# 7. SECRET_KEY
# -------------------------------------------------
SECRET_KEY=$(openssl rand -base64 42)

# -------------------------------------------------
# 8. Variables de entorno globales
# -------------------------------------------------
cat <<EOF > /etc/profile.d/superset.sh
export FLASK_APP=superset
export SUPERSET_CONFIG_PATH=/home/superset/.superset/superset_config.py
EOF
chmod 644 /etc/profile.d/superset.sh

# -------------------------------------------------
# 9. Logs
# -------------------------------------------------
mkdir -p /var/log/superset
chown superset:superset /var/log/superset
chmod 750 /var/log/superset

# -------------------------------------------------
# 10. Instalar Superset (usuario superset)
# -------------------------------------------------
su - superset <<EOSUPERSET
set -e

python${PYTHON_VERSION} -m venv ~/superset-venv
source ~/superset-venv/bin/activate

pip install --upgrade pip setuptools wheel
pip install apache-superset

mkdir -p ~/.superset

cat <<EOF > ~/.superset/superset_config.py
SECRET_KEY = "$SECRET_KEY"

ROW_LIMIT = 10000
SQL_MAX_ROW = 10000

WTF_CSRF_ENABLED = True
SQLLAB_ALLOW_DML = False
EOF

export FLASK_APP=superset
export SUPERSET_CONFIG_PATH=/home/superset/.superset/superset_config.py

superset db upgrade

superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname User \
  --email admin@localhost \
  --password 'admin123.!'

superset init
EOSUPERSET

# -------------------------------------------------
# 11. Servicio systemd (CORRECTO)
# -------------------------------------------------
cat <<EOF > /etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target

[Service]
Type=simple
User=superset
Group=superset
WorkingDirectory=/home/superset

Environment=FLASK_APP=superset
Environment=SUPERSET_CONFIG_PATH=/home/superset/.superset/superset_config.py
Environment=PATH=/home/superset/superset-venv/bin:/usr/bin

ExecStart=/home/superset/superset-venv/bin/superset run \
  -h 0.0.0.0 \
  -p 8088

StandardOutput=append:/var/log/superset/superset.log
StandardError=append:/var/log/superset/superset.log

Restart=always
RestartSec=5

# Seguridad
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------------------------
# 12. Activar servicio
# -------------------------------------------------
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable superset
systemctl start superset

echo "======================================="
echo " Superset INSTALADO y CORRIENDO ✅"
echo "======================================="
echo " URL: http://127.0.0.1:8088"
echo " Usuario: admin"
echo " Password: admin123.!"
echo ""
echo " Para controlar el servicio:"
echo "  systemctl status superset"
echo "  systemctl start superset"
echo "  systemctl stop superset"
echo " Logs:"
echo " Para ver logs ejecute # tail -f /var/log/superset/superset.log"