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
echo *** tomcat ***
su - 
dnf install java-11-openjdk
mkdir -p /opt/tomcat
cd /opt/tomcat
curl -sSL https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.96/bin/apache-tomcat-9.0.96.tar.gz | tar zxvf - 
mv apache-tomcat-9.0.96/* .
rmdir apache-tomcat-9.0.96
mkdir /opt/tomcat/webapps/i
[[ -d /home/oracle/apex/images ]] && \
  cp -r /home/oracle/apex/images/* /opt/tomcat/webapps/i/
[[ -d /home/oracle/apex_patch/36695709/images ]] && \
  cp -r /home/oracle/apex_patch/36695709/images/* /opt/tomcat/webapps/i/
[[ -f /home/oracle/ords/ords.war ]] && \
  cp /home/oracle/ords/ords.war /opt/tomcat/webapps/
sed -i '/-Djava.protocol.handler/aJAVA_OPTS="\$JAVA_OPTS -Dconfig.url=/etc/ords/config -Xms1024M -Xmx1024M"' /opt/tomcat/bin/catalina.sh
EOT
$DOCKER container cp addons/tomcat.init "$ORACLE_CONTAINER_NAME":/etc/init.d/tomcat
$DOCKER container exec -i  "$ORACLE_CONTAINER_NAME" bash <<EOT
su -
/etc/init.d/tomcat start
EOT
