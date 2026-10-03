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
# Second compte, sur les deux Synapse à mot de passe : une reconnexion avec ses identifiants doit
# être refusée sur la session de USER_NAME.
OTHER_NAME="mck-other"
OTHER_PASSWORD="mck-other-password"
ADMIN_NAME="mck-admin"
ADMIN_PASSWORD="mck-admin-password"
OAUTH_USER="mck-oauth-user"
OAUTH_PASSWORD="mck-oauth-password"
MAS_URL="http://localhost:8082"
OAUTH_HOMESERVER="http://localhost:8010"

register() { # $1 service, $2 user, $3 password, $4 --admin|--no-admin
  local out
  # Seul « l'utilisateur existe déjà » est toléré (up rejouable) ; toute autre erreur est fatale.
  out=$("${COMPOSE[@]}" exec -T "$1" register_new_matrix_user \
    -u "$2" -p "$3" "$4" -k "mck-harness-registration-secret" http://localhost:8008 2>&1) \
    || grep -qi 'already' <<<"$out" || { echo "register $2 on $1 failed: $out" >&2; return 1; }
}

register_oauth() {
  local out
  # Compte créé dans MAS (le Synapse délégué n'a pas d'enregistrement propre). Seul « existe déjà »
  # est toléré ; toute autre erreur est fatale.
  out=$("${COMPOSE[@]}" exec -T mas mas-cli manage register-user --config /config/config.yaml \
    --yes --ignore-password-complexity -p "$OAUTH_PASSWORD" "$OAUTH_USER" 2>&1) \
    || grep -qi 'already exists' <<<"$out" || { echo "register $OAUTH_USER in MAS failed: $out" >&2; return 1; }
}

oauth_user_exists() {
  local count
  count=$("${COMPOSE[@]}" exec -T postgres psql -U postgres -d mas -tA \
    -c "SELECT count(*) FROM users WHERE username = '$OAUTH_USER'")
  [[ "$count" == "1" ]]
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
      register "$service" "$OTHER_NAME" "$OTHER_PASSWORD" --no-admin
    done
    # MAS n'a pas de healthcheck (compose ne l'attend pas) : sonde bornée, le temps des migrations.
    mas_ready=0
    for _ in $(seq 60); do
      if curl -fsS -o /dev/null "http://127.0.0.1:8082/.well-known/openid-configuration" 2>/dev/null; then
        mas_ready=1
        break
      fi
      sleep 1
    done
    [[ "$mas_ready" == 1 ]] || { echo "MAS injoignable sur $MAS_URL après 60 s" >&2; exit 1; }
    register_oauth
    # Le Synapse délégué annonce MAS (issuer joignable depuis l'hôte), sert le rendez-vous MSC4108
    # (tout sauf 404 : un POST sans corps valide répond 400) et le compte OAuth existe.
    auth_metadata=$(curl -fsS "$OAUTH_HOMESERVER/_matrix/client/v1/auth_metadata")
    grep -q "\"issuer\":\"$MAS_URL/\"" <<<"$auth_metadata" \
      || { echo "auth_metadata de $OAUTH_HOMESERVER n'annonce pas l'issuer $MAS_URL/" >&2; exit 1; }
    rendezvous=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
      "$OAUTH_HOMESERVER/_matrix/client/unstable/org.matrix.msc4108/rendezvous")
    [[ "$rendezvous" != "404" ]] \
      || { echo "rendez-vous MSC4108 non servi par $OAUTH_HOMESERVER (404)" >&2; exit 1; }
    oauth_user_exists || { echo "compte $OAUTH_USER absent de MAS" >&2; exit 1; }
    # Vérifie que les comptes existent vraiment sur les deux serveurs.
    for port in 8008 8009; do
      login_token "$port" "$ADMIN_NAME" "$ADMIN_PASSWORD" >/dev/null
      login_token "$port" "$USER_NAME" "$USER_PASSWORD" >/dev/null
      login_token "$port" "$OTHER_NAME" "$OTHER_PASSWORD" >/dev/null
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
    echo "export MCK_HARNESS_OAUTH_HOMESERVER=$OAUTH_HOMESERVER"
    echo "export MCK_HARNESS_MAS=$MAS_URL"
    echo "export MCK_HARNESS_OAUTH_USER=$OAUTH_USER"
    echo "export MCK_HARNESS_OAUTH_PASSWORD=$OAUTH_PASSWORD"
    echo "export MCK_HARNESS_USER=$USER_NAME"
    echo "export MCK_HARNESS_PASSWORD=$USER_PASSWORD"
    echo "export MCK_HARNESS_EMAIL=$USER_EMAIL"
    echo "export MCK_HARNESS_OTHER_USER=$OTHER_NAME"
    echo "export MCK_HARNESS_OTHER_PASSWORD=$OTHER_PASSWORD"
    echo "export MCK_HARNESS_ADMIN_TOKEN_PASSWORD=$token_password"
    echo "export MCK_HARNESS_ADMIN_TOKEN_EXPIRING=$token_expiring"
    ;;
  *)
    echo "usage: $0 up|down|env" >&2
    exit 64
    ;;
esac
