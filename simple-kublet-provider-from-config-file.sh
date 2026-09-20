#!/usr/bin/env bash
set -euo pipefail

# Путь к файлу с docker config (можно переопределить через ENV)
DOCKER_CONFIG_FILE="${DOCKER_CONFIG_FILE:-/var/lib/kubelet/config.json}"

# Читаем запрос от kubelet из stdin
REQUEST=$(cat)

# Извлекаем имя образа из запроса
# Ожидаем JSON вида:
# {
#   "apiVersion": "credentialprovider.kubelet.k8s.io/v1",
#   "kind": "CredentialProviderRequest",
#   "image": "registry.example.com/ns/repo:tag"
# }
IMAGE=$(echo "$REQUEST" | jq -r '.image')

if [[ -z "$IMAGE" || "$IMAGE" == "null" ]]; then
  echo '{"apiVersion":"credentialprovider.kubelet.k8s.io/v1","kind":"CredentialProviderResponse","auth":{}}' >&2
  exit 1
fi

# Проверяем наличие файла
if [[ ! -f "$DOCKER_CONFIG_FILE" ]]; then
  # Нет файла — возвращаем пустой ответ
  echo '{"apiVersion":"credentialprovider.kubelet.k8s.io/v1","kind":"CredentialProviderResponse","auth":{}}'
  exit 0
fi

# Извлекаем список registry из образа
# registry.example.com из registry.example.com/ns/repo:tag
REGISTRY=$(echo "$IMAGE" | cut -d'/' -f1)

# Если в образе нет явного registry (например, "nginx:latest"),
# по умолчанию это Docker Hub: index.docker.io/v1/
if [[ "$REGISTRY" != *"."* && "$REGISTRY" != *":"* ]]; then
  REGISTRY="https://index.docker.io/v1/"
else
  # Пробуем найти в config.json ключ, совпадающий с registry
  # Поддерживаем варианты: registry.example.com, https://registry.example.com, https://registry.example.com/v1/
  REGISTRY_KEYS=$(jq -r '.auths | keys[]' "$DOCKER_CONFIG_FILE" 2>/dev/null || true)
  MATCHED_REGISTRY=""
  for key in $REGISTRY_KEYS; do
    # Нормализуем ключ: убираем схему и путь
    normalized=$(echo "$key" | sed -E 's|^https?://||; s|/.*||')
    if [[ "$normalized" == "$REGISTRY" ]]; then
      MATCHED_REGISTRY="$key"
      break
    fi
  done

  if [[ -n "$MATCHED_REGISTRY" ]]; then
    REGISTRY="$MATCHED_REGISTRY"
  else
    # Не нашли точного совпадения — пробуем по префиксу
    for key in $REGISTRY_KEYS; do
      normalized=$(echo "$key" | sed -E 's|^https?://||; s|/.*||')
      if [[ "$REGISTRY" == "$normalized" || "$REGISTRY" == *"$normalized"* ]]; then
        MATCHED_REGISTRY="$key"
        break
      fi
    done

    if [[ -n "$MATCHED_REGISTRY" ]]; then
      REGISTRY="$MATCHED_REGISTRY"
    else
      # Совпадений нет — возвращаем пустой ответ
      echo '{"apiVersion":"credentialprovider.kubelet.k8s.io/v1","kind":"CredentialProviderResponse","auth":{}}'
      exit 0
    fi
  fi
fi

# Читаем auth для найденного registry
AUTH=$(jq -r --arg reg "$REGISTRY" '.auths[$reg].auth // empty' "$DOCKER_CONFIG_FILE")
AUTH_USERNAME=$(echo $AUTH | base64 -d | awk -F':' '{print $1}')
AUTH_PASSWORD=$(echo $AUTH | base64 -d | awk -F':' '{print $2}')


if [[ -z "$AUTH" ]]; then
  # Нет credentials для этого registry
  echo '{"apiVersion":"credentialprovider.kubelet.k8s.io/v1","kind":"CredentialProviderResponse","auth":{}}'
  exit 0
fi

# Возвращаем ответ в формате v1
# https://kubernetes.io/docs/reference/config-api/kubelet-credentialprovider.v1/
jq -n \
  --arg registry "$REGISTRY" \
  --arg auth_username "$AUTH_USERNAME" \
  --arg auth_password "$AUTH_PASSWORD" \
  '{
    "apiVersion": "credentialprovider.kubelet.k8s.io/v1",
    "kind": "CredentialProviderResponse",
    "auth": {
      ($registry): {
        "username": ($auth_username),
        "password": ($auth_password)
      }
    }
  }'