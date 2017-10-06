#!/bin/bash
set -e

export GIT_BRANCH="${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
export TAG="${TAG:-branch-$(basename "$GIT_BRANCH")}"
export COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-consul}"
export COMPOSE_FILE="${COMPOSE_FILE:-./local-compose.yml}"

project="$COMPOSE_PROJECT"
manifest="$COMPOSE_FILE"

fail() {
    echo
    echo '------------------------------------------------'
    echo 'FAILED: dumping logs'
    echo '------------------------------------------------'
    docker-compose -p "$project" -f "$manifest" ps
    docker-compose -p "$project" -f "$manifest" logs
    echo '------------------------------------------------'
    echo 'FAILED'
    echo "$1"
    echo '------------------------------------------------'
    exit 1
}

pass() {
    teardown
    echo
    echo '------------------------------------------------'
    echo 'PASSED!'
    echo
    exit 0
}

function finish {
    result=$?
    if [ $result -ne 0 ]; then fail "unexpected error"; fi
    pass
}
trap finish EXIT



# --------------------------------------------------------------------
# Helpers

# asserts that 'count' Consul instances are running and marked as Up
# by Docker. fails after the timeout.
wait_for_containers() {
    local count timeout i got
    count="$1"
    timeout="${3:-60}" # default 60sec
    i=0
    echo "waiting for $count Consul containers to be Up..."
    while [ $i -lt "$timeout" ]; do
        got=$(docker-compose -p "$project" -f "$manifest" ps consul)
        got=$(echo "$got" | grep -c "Up")
        if [ "$got" -eq "$count" ]; then
            echo "$count instances reported Up in <= $i seconds"
            return
        fi
        i=$((i+1))
        sleep 1
    done
    fail "$count instances did not report Up within $timeout seconds"
}

restart() {
    node="${project}_$1"
    docker restart "$node"
}

netsplit() {
    # it's a bit of a pain to netsplit this container without extra privileges,
    # or doing some non-portable stuff in the underlying VM, so instead we'll
    # pause the container which will cause its TTL to expire
    echo "netsplitting ${project}_$1"
    docker pause "${project}_$1"
}

heal() {
    echo "healing netsplit for ${project}_$1"
    docker unpause "${project}_$1"
}

run() {
    echo
    echo '* cleaning up previous test run'
    echo
    docker-compose -p "$project" -f "$manifest" stop
    docker-compose -p "$project" -f "$manifest" rm -f

    echo
    echo '* standing up initial test targets'
    echo
    docker-compose -p "$project" -f "$manifest" up -d
}

teardown() {
    echo
    echo '* tearing down containers'
    echo
    docker-compose -p "$project" -f "$manifest" stop
    docker-compose -p "$project" -f "$manifest" rm -f
}

scale() {
    count="$1"
    echo
    echo '* scaling up cluster'
    echo
    docker-compose -p "$project" -f "$manifest" scale consul="$count"
}

# --------------------------------------------------------------------
# Test sections

