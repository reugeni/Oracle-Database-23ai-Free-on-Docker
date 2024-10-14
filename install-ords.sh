#!/bin/bash
set -eu -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR

# load environment variables from .env
if [ -e "$SCRIPT_DIR"/.env ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR"/.env
else
  echo -e '\e[33mEnvironment file .env not found. Therefore, dotenv.sample will be used.\e[0m'
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR"/dotenv.sample
fi

if [[ $(command -v docker) ]]; then
  DOCKER=docker
elif [[ $(command -v podman) ]]; then
  DOCKER=podman
else
  echo -e '\n\e[31mNeither docker nor podman is installed.\e[0m'
  exit 1
fi
readonly DOCKER

# health check
status="$($DOCKER inspect -f '{{.State.Status}}' "$ORACLE_CONTAINER_NAME")"
if [[ $status != "running" ]]; then
  echo -e "\n\e[31mContainer $ORACLE_CONTAINER_NAME is $status\e[0m"
  exit 1
fi
health="$($DOCKER inspect -f '{{.State.Health.Status}}' "$ORACLE_CONTAINER_NAME")"
if [[ $health != "healthy" ]]; then
  echo -e "\n\e[31mContainer $ORACLE_CONTAINER_NAME is $health\e[0m"
  exit 1
fi

$DOCKER container exec -i "$ORACLE_CONTAINER_NAME" bash <<EOT
su - 
dnf install java-11-openjdk
mkdir -p  /etc/ords/config/logs
chmod -R 777 /etc/ords/config
exit
curl -o ords-lates.zip -sSL https://download.oracle.com/otn_software/java/ords/ords-latest.zip
unzip ords-latest.zip
rm ords-latest.zip
./ords/bin/ords --config /etc/ords/config install \
     --log-folder /etc/ords/config/logs \
     --admin-user SYS \
     --db-hostname localhost \
     --db-port 1521 \
     --db-servicename FREEPDB1 \
     --feature-db-api true \
     --feature-rest-enabled-sql true \
     --feature-sdw true \
     --proxy-user \
     --password-stdin <<EOF
${ORACLE_PWD}
${APEX_PWD}
EOF

# swith default page to apex -- http://localhost:8080/ords
sed -i '/<\/properties>/i<entry key="misc.defaultPage">apex</entry>' /etc/ords/config/global/settings.xml
EOT
