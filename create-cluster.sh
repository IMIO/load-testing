#!/usr/bin/env bash

set -e -o pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/concurrent.lib.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.lib.sh"

function setup_docker_local_env() {
	local args=(
		- "Init: Fetch docker"	                  fetch_docker
		- "Init: Fetch docker machine"	          fetch_docker_machine
		- "Init: Fetch docker compose"	          fetch_docker_compose
		- "Init: Fetch docker machine ovh driver" fetch_docker_machine_ovh_driver
        )
	concurrent "${args[@]}"
}

main() {
	local args=(
		- "Init: Create consul machine" create_consul_machine
		- "Init: Create consul service" create_consul_service
		- "Site: Create site machine"		create_site_machine
		--sequential
                - "Site: Create registrator service"  create_registrator_service
                - "Site: Create remote directories"	create_remote_dirs
		- "Site: Sync data"			sync_data
		- "Site: Sync docker image"		sync_docker_image
                - "Site: Start site"                  start_site

		--require "Site: Create remote directories"
		--before  "Site: Sync data"

		--require "Site: Create site machine"
		--before "Site: Create remote directories"
		--before "Site: Sync data"
		--before "Site: Sync docker image"

                --require "Site: Create site machine"
                --before "Site: Create registrator service"

                --require "Site: Sync docker image"
                --require "Site: Sync data"
                --before  "Site: Start site"

		- "JMeter slave: Create jmeter slave machine"		create_jmeter_slave_machine jmeter-slave-1
                - "JMeter slave: Sync jmeter data"                    sync_jmeter_data jmeter-slave-1
                - "JMeter slave: Create jmeter slave container"       create_jmeter_slave_container
                --require "JMeter slave: Create jmeter slave machine"
                --before "JMeter slave: Sync jmeter data"
                --before "JMeter slave: Create jmeter slave container"

                --require "JMeter slave: Sync jmeter data"
                --before  "JMeter slave: Create jmeter slave container"

	)
	concurrent "${args[@]}"
}

sudo echo
setup_docker_local_env "${@}"
main "${@}"
