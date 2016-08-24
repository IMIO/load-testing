#!/usr/bin/env bash

set -e -o pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/concurrent.lib.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.lib.sh"

main() {
	local args=(
                - "Sync tests data on jmeter slaves"    sync_jmeter_data jmeter-slave-1
                - "Sync tests data on jmeter master"    sync_jmeter_data consul
                - "Start jmeter tests"                  start_jmeter_tests

		--require "Sync tests data on jmeter slaves"
		--require "Sync tests data on jmeter master"
		--before  "Start jmeter tests"

	)
	concurrent "${args[@]}"
}

main "${@}"
