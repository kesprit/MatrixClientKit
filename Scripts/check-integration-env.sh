#!/bin/bash
# Checks that the test account is ready for the integration suite, before running it.
#
# It verifies the password, the room, whether recovery is set up, and the optional sender account.
# It writes nothing, changes nothing on the account, and signs out the session it opens.
#
# Usage:
#     ./Scripts/check-integration-env.sh
#
# It reads MATRIX_TEST_HOMESERVER, MATRIX_TEST_USERNAME and MATRIX_TEST_ROOM_ID from the
# environment when they are set, and asks for whatever is missing. The password is never echoed,
# never stored, and never passed as a command-line argument.

set -u

failures=0

report() {
    # $1: ok|ko — $2: message
    if [ "$1" = ok ]; then
        printf '  OK    %s\n' "$2"
    else
        printf '  ISSUE %s\n' "$2"
        failures=$((failures + 1))
    fi
}

ask() {
    # $1: prompt — $2: current value, kept when non-empty
    local answer
    if [ -n "$2" ]; then
        printf '%s\n' "$2"
        return
    fi
    printf '%s' "$1" >&2
    read -r answer
    printf '%s\n' "$answer"
}

HOMESERVER=$(ask 'Homeserver (https://…): ' "${MATRIX_TEST_HOMESERVER:-}")
USERNAME=$(ask 'Username (without @ and without :server): ' "${MATRIX_TEST_USERNAME:-}")
ROOM_ID=$(ask "Room ID (starts with '!'): " "${MATRIX_TEST_ROOM_ID:-}")

if [ -n "${MATRIX_TEST_PASSWORD:-}" ]; then
    PASSWORD="$MATRIX_TEST_PASSWORD"
else
    printf 'Password (not echoed): ' >&2
    read -rs PASSWORD
    printf '\n' >&2
fi

HOMESERVER="${HOMESERVER%/}"
export HOMESERVER USERNAME ROOM_ID PASSWORD

printf '\nChecking %s as %s\n\n' "$HOMESERVER" "$USERNAME"

# 1. Password — also yields the token the next checks need.
login_body=$(python3 - <<'PY'
import json, os
print(json.dumps({
    "type": "m.login.password",
    "identifier": {"type": "m.id.user", "user": os.environ["USERNAME"]},
    "password": os.environ["PASSWORD"],
    "initial_device_display_name": "MatrixClientKit env check",
}))
PY
)

login_response=$(curl -s -m 30 "$HOMESERVER/_matrix/client/v3/login" \
    -H 'Content-Type: application/json' -d "$login_body")

login_result=$(RESPONSE="$login_response" python3 - <<'PY'
import json, os, sys

try:
    body = json.loads(os.environ["RESPONSE"])
except ValueError:
    print("|unreadable response from the homeserver")
    sys.exit()

token = body.get("access_token")
if token:
    print(f"{token}|")
else:
    print(f'|{body.get("errcode", "?")}: {body.get("error", "")}')
PY
)

TOKEN="${login_result%%|*}"
if [ -z "$TOKEN" ]; then
    report ko "Sign-in refused — ${login_result#*|}"
    printf '\n  M_FORBIDDEN means the password is refused; M_LIMIT_EXCEEDED means too many\n'
    printf '  attempts, so wait a few minutes and run this again.\n\n'
    exit 1
fi
export TOKEN
report ok 'Password accepted'

# 2. The room the send-a-message case needs, and the account's membership in it.
joined_response=$(curl -s -m 30 -H "Authorization: Bearer $TOKEN" \
    "$HOMESERVER/_matrix/client/v3/joined_rooms")

room_result=$(RESPONSE="$joined_response" python3 - <<'PY'
import json, os, sys

target = os.environ["ROOM_ID"]
try:
    rooms = json.loads(os.environ["RESPONSE"]).get("joined_rooms", [])
except ValueError:
    print("ko|could not read the joined-room list")
    sys.exit()

if not target.startswith("!"):
    print(f"ko|{target} is not a room ID: it must start with ! (an alias starts with #)")
elif target in rooms:
    print("ok|Room joined")
else:
    print(f"ko|The account has not joined {target} ({len(rooms)} room(s) joined)")
PY
)
report "${room_result%%|*}" "${room_result#*|}"

# 3. Optional second account, also expected to be a member of the room.
SENDER_USERNAME="${MATRIX_TEST_SENDER_USERNAME:-}"
if [ -z "$SENDER_USERNAME" ]; then
    printf '  SKIP  sender account (MATRIX_TEST_SENDER_USERNAME not set)\n'
else
    if [ -n "${MATRIX_TEST_SENDER_PASSWORD:-}" ]; then
        SENDER_PASSWORD="$MATRIX_TEST_SENDER_PASSWORD"
    else
        printf 'Sender password (not echoed): ' >&2
        read -rs SENDER_PASSWORD
        printf '\n' >&2
    fi
    export SENDER_USERNAME SENDER_PASSWORD

    sender_login_body=$(python3 - <<'PY'
import json, os
print(json.dumps({
    "type": "m.login.password",
    "identifier": {"type": "m.id.user", "user": os.environ["SENDER_USERNAME"]},
    "password": os.environ["SENDER_PASSWORD"],
    "initial_device_display_name": "MatrixClientKit env check (sender)",
}))
PY
)

    sender_login_response=$(curl -s -m 30 "$HOMESERVER/_matrix/client/v3/login" \
        -H 'Content-Type: application/json' -d "$sender_login_body")

    sender_login_result=$(RESPONSE="$sender_login_response" python3 - <<'PY'
import json, os, sys

try:
    body = json.loads(os.environ["RESPONSE"])
except ValueError:
    print("|unreadable response from the homeserver")
    sys.exit()

token = body.get("access_token")
if token:
    print(f"{token}|")
else:
    print(f'|{body.get("errcode", "?")}: {body.get("error", "")}')
PY
)

    SENDER_TOKEN="${sender_login_result%%|*}"
    if [ -z "$SENDER_TOKEN" ]; then
        report ko "Sender sign-in refused — ${sender_login_result#*|}"
    else
        report ok 'Sender password accepted'

        sender_joined_response=$(curl -s -m 30 -H "Authorization: Bearer $SENDER_TOKEN" \
            "$HOMESERVER/_matrix/client/v3/joined_rooms")

        sender_room_result=$(RESPONSE="$sender_joined_response" python3 - <<'PY'
import json, os, sys

target = os.environ["ROOM_ID"]
try:
    rooms = json.loads(os.environ["RESPONSE"]).get("joined_rooms", [])
except ValueError:
    print("ko|could not read the sender's joined-room list")
    sys.exit()

if target in rooms:
    print("ok|Sender has joined the room")
else:
    print(f"ko|The sender account has not joined {target} ({len(rooms)} room(s) joined)")
PY
)
        report "${sender_room_result%%|*}" "${sender_room_result#*|}"

        curl -s -m 30 -X POST -H "Authorization: Bearer $SENDER_TOKEN" -H 'Content-Type: application/json' \
            -d '{}' "$HOMESERVER/_matrix/client/v3/logout" > /dev/null
    fi
fi

# 4. Recovery, which the encryption cases need set up on the account.
user_id="@$USERNAME:$(printf '%s' "$HOMESERVER" | sed -e 's|^https\{0,1\}://||' -e 's|/.*$||')"
encoded_user=$(USER_ID="$user_id" python3 - <<'PY'
import os, urllib.parse
print(urllib.parse.quote(os.environ["USER_ID"], safe=""))
PY
)

recovery_response=$(curl -s -m 30 -H "Authorization: Bearer $TOKEN" \
    "$HOMESERVER/_matrix/client/v3/user/$encoded_user/account_data/m.secret_storage.default_key")

recovery_result=$(RESPONSE="$recovery_response" python3 - <<'PY'
import json, os, sys

try:
    body = json.loads(os.environ["RESPONSE"])
except ValueError:
    print("ko|could not read the account data")
    sys.exit()

if body.get("key"):
    print("ok|Recovery is set up")
else:
    reason = body.get("errcode", "no key in the account data")
    print(f"ko|Recovery is not set up ({reason}): set it up in Element, then use the key it shows")
PY
)
report "${recovery_result%%|*}" "${recovery_result#*|}"

# Leaves no device behind on the account.
curl -s -m 30 -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d '{}' "$HOMESERVER/_matrix/client/v3/logout" > /dev/null
report ok 'Check session signed out'
printf '\n'

if [ "$failures" -gt 0 ]; then
    printf 'Not ready: %d issue(s) above.\n' "$failures"
    exit 1
fi

printf 'Ready. One thing this cannot tell you: whether MATRIX_TEST_RECOVERY_KEY is the *right*\n'
printf 'key for this account — only decrypting proves that, which the suite itself does.\n'
