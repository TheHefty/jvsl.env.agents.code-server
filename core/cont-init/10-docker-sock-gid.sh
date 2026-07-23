#!/usr/bin/env bash
# custom-cont-init.d script: roda como root, antes do s6-overlay derrubar
# privilégios pro usuário 'abc'. Necessário porque o --group-add do `docker
# run` só afeta o processo PID 1 (root); ao aplicar PUID/PGID e trocar pra
# 'abc', o s6-overlay recalcula os grupos suplementares a partir do
# /etc/group da imagem, descartando o gid injetado via --group-add. Alinhar
# o gid do grupo 'docker' aqui garante que ele sobreviva ao drop.
set -euo pipefail

if [ -z "${DOCKER_SOCK_GID:-}" ]; then
    exit 0
fi

CURRENT_GID="$(getent group docker | cut -d: -f3)"

if [ "$CURRENT_GID" = "$DOCKER_SOCK_GID" ]; then
    exit 0
fi

if getent group "$DOCKER_SOCK_GID" >/dev/null; then
    # já existe um grupo com esse gid na imagem (colisão) — só adiciona
    # 'abc' a ele em vez de tentar renomear o gid do grupo 'docker'
    EXISTING_GROUP="$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1)"
    usermod -aG "$EXISTING_GROUP" abc
else
    groupmod -g "$DOCKER_SOCK_GID" docker
fi
