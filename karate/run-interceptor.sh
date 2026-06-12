#!/usr/bin/env bash
# Start an actor interceptor that WAITS for a client system, so you can test
# that client's conformance without changing it. It stores nothing: pushes are
# forwarded to the real server's $validate (client gets the OperationOutcome
# back), pulls are gated (must be patient-scoped) and then forwarded.
#
#   ./run-interceptor.sh ehr 8080                      # EHR: order placer + result consumer
#   ./run-interceptor.sh lab 8081                      # Lab: order fulfiller + result provider
#   TARGET=https://my-shr/fhir ./run-interceptor.sh ehr 8080   # real server behind the interceptor
#   MODE=dryrun ./run-interceptor.sh ehr 8080          # validate-only: relay verdicts, store nothing
#
# Default MODE=proxy: a pass-through conformance proxy — point the client at
# it ONCE and leave it; requests are forwarded to the real server and pushes
# are scored against the ZW profiles on the way through (X-ZW-Validation
# header + ZWPROXY log lines). Stop with Ctrl+C.
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../.. && pwd)"

ACTOR="${1:?usage: run-interceptor.sh <ehr|lab> [port]}"
PORT="${2:-8080}"
MODE="${MODE:-proxy}"
if [ "$MODE" = "dryrun" ]; then
  FEATURE="features/interceptors/${ACTOR}.feature"
else
  FEATURE="features/interceptors/${ACTOR}-proxy.feature"
fi
[ -f "$FEATURE" ] || { echo "ERROR: unknown actor '$ACTOR' (expected: ehr, lab)" >&2; exit 1; }

# returns success when a working Java 17+ is NOT on the PATH
need_java() {
  command -v java >/dev/null 2>&1 || return 0
  major="$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)"
  [ -z "$major" ] && return 0
  [ "$major" -lt 17 ]
}
if need_java; then
  JAVA_CANDIDATE="$(sed -n 's/^java=//p' "$REPO_ROOT/.sdkmanrc" 2>/dev/null || true)"
  SDK_JAVA="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java/${JAVA_CANDIDATE:-none}"
  [ -x "$SDK_JAVA/bin/java" ] && export JAVA_HOME="$SDK_JAVA" && export PATH="$JAVA_HOME/bin:$PATH"
fi
if need_java; then
  echo "ERROR: Java 17+ required. With SDKMAN: 'sdk env install' in the repo root." >&2
  exit 1
fi

KARATE_VERSION="${KARATE_VERSION:-2.0.3}"
JAR="karate-${KARATE_VERSION}.jar"
if [ ! -f "$JAR" ]; then
  echo "Downloading Karate ${KARATE_VERSION} (one-time)..."
  curl -fL -o "$JAR" "https://github.com/karatelabs/karate/releases/download/v${KARATE_VERSION}/karate-${KARATE_VERSION}.jar"
fi

echo "${ACTOR} ${MODE} interceptor listening on http://localhost:${PORT} (target: ${TARGET:-default})"
# zw.port scopes the proxy's state files (session patients / validation
# reports) so concurrent or leftover proxies never share them
java ${TARGET:+-Dtarget="$TARGET"} -Dzw.port="$PORT" -jar "$JAR" mock -m "$FEATURE" -p "$PORT"
