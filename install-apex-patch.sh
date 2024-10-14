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
if [[ ! -f addons/patch/p36695709_2410_Generic.zip ]]; then
  echo -e "\n\e[31mMissing patch file\e[0m"
  exit 1
fi

$DOCKER container cp addons/patch/p36695709_2410_Generic.zip "$ORACLE_CONTAINER_NAME":/home/oracle
$DOCKER container exec -i "$ORACLE_CONTAINER_NAME" bash <<EOT
[ ! -d apex_patch ] && mkdir apex_patch
cd apex_patch
unzip ../p36695709_2410_Generic.zip -
rm ../p36695709_2410_Generic.zip
cd 36695709
/opt/oracle/product/23ai/dbhomeFree/sqlcl/bin/sql sys/"$ORACLE_PWD"@FREEPDB1 as sysdba @catpatch.sql
EOT
