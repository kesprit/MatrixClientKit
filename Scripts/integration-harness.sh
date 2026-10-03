#!/usr/bin/env bash
# Démarre, arrête et décrit le harnais d'intégration Docker de MatrixClientKit.
#   up    démarre les conteneurs, attend leur santé, crée les comptes de test
#   down  arrête et efface tout (volumes compris)
#   env   affiche les variables d'environnement à exporter pour `swift test`
set -euo pipefail

cd "$(dirname "$0")/../Tests/IntegrationHarness"
COMPOSE=(docker compose -p mck-harness)

USER_NAME="mck-user"
USER_PASSWORD="mck-user-password"
USER_EMAIL="mck-user@example.test"
ADMIN_NAME="mck-admin"
ADMIN_PASSWORD="mck-admin-password"

register() { # $1 service, $2 user, $3 password, $4 --admin|--no-admin
  local out
  # Seul « l'utilisateur existe déjà » est toléré (up rejouable) ; toute autre erreur est fatale.
  out=$("${COMPOSE[@]}" exec -T "$1" register_new_matrix_user \
    -u "$2" -p "$3" "$4" -k "mck-harness-registration-secret" http://localhost:8008 2>&1) \
    || grep -qi 'already' <<<"$out" || { echo "register $2 on $1 failed: $out" >&2; return 1; }
}

login_token() { # $1 port, $2 user, $3 password
  curl -fsS -X POST "http://localhost:$1/_matrix/client/v3/login" \
    -H 'Content-Type: application/json' \
    -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$2\"},\"password\":\"$3\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}

bind_email() { # $1 port, $2 admin token
  curl -fsS -X PUT "http://localhost:$1/_synapse/admin/v2/users/@$USER_NAME:localhost" \
    -H "Authorization: Bearer $2" -H 'Content-Type: application/json' \
    -d "{\"threepids\":[{\"medium\":\"email\",\"address\":\"$USER_EMAIL\"}]}" >/dev/null
}

case "${1:-}" in
  up)
    "${COMPOSE[@]}" up -d --wait
    for service in synapse-password synapse-expiring; do
      register "$service" "$ADMIN_NAME" "$ADMIN_PASSWORD" --admin
      register "$service" "$USER_NAME" "$USER_PASSWORD" --no-admin
    done
    # Vérifie que les comptes existent vraiment sur les deux serveurs.
    for port in 8008 8009; do
      login_token "$port" "$ADMIN_NAME" "$ADMIN_PASSWORD" >/dev/null
      login_token "$port" "$USER_NAME" "$USER_PASSWORD" >/dev/null
    done
    admin_token=$(login_token 8008 "$ADMIN_NAME" "$ADMIN_PASSWORD")
    bind_email 8008 "$admin_token"
    echo "Harness up. Run: eval \"\$(Scripts/integration-harness.sh env)\""
    ;;
  down)
    "${COMPOSE[@]}" down -v
    ;;
  env)
    token_password=$(login_token 8008 "$ADMIN_NAME" "$ADMIN_PASSWORD")
    token_expiring=$(login_token 8009 "$ADMIN_NAME" "$ADMIN_PASSWORD")
    echo "export MCK_HARNESS_PASSWORD_HOMESERVER=http://localhost:8008"
    echo "export MCK_HARNESS_EXPIRING_HOMESERVER=http://localhost:8009"
    echo "export MCK_HARNESS_USER=$USER_NAME"
    echo "export MCK_HARNESS_PASSWORD=$USER_PASSWORD"
    echo "export MCK_HARNESS_EMAIL=$USER_EMAIL"
    echo "export MCK_HARNESS_ADMIN_TOKEN_PASSWORD=$token_password"
    echo "export MCK_HARNESS_ADMIN_TOKEN_EXPIRING=$token_expiring"
    ;;
  *)
    echo "usage: $0 up|down|env" >&2
    exit 64
    ;;
esac
