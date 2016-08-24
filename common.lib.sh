#!/usr/bin/env bash

PATH=$(pwd)/docker:$PATH
export PATH

create_remote_dirs() {
	docker-machine ssh site "sudo mkdir -p /srv/instances/theux /srv/docker_scripts/website-theux/ && sudo chown -R ubuntu /srv/instances/theux /srv/docker_scripts/website-theux/"
}

create_site_machine() {

	if ! docker-machine ls -q|grep -q site;
	then
		docker-machine create \
		    --driver ovh \
		    --engine-label type=site \
		    --ovh-flavor "vps-ssd-2" \
                    --ovh-ssh-key jfroche \
                    --ovh-project loadtesting \
                    --ovh-ssh-user ubuntu \
		    --swarm \
		    --swarm-master \
		    --swarm-discovery="consul://$(docker-machine ip consul):8500" \
		    --engine-opt="cluster-store=consul://$(docker-machine ip consul):8500" \
		    --engine-opt="cluster-advertise=ens3:2376" \
		    site
	fi
}

create_consul_machine() {

	if ! docker-machine ls -q|grep -q consul;
	then
		docker-machine create \
		    --driver ovh \
                    --ovh-project loadtesting \
                    --ovh-ssh-key jfroche \
                    --ovh-ssh-user ubuntu \
		    --engine-label type=consul \
		    --ovh-flavor "vps-ssd-1" \
		    --engine-opt="cluster-store=consul://localhost:8500" \
		    --engine-opt="cluster-advertise=ens3:2376" \
		    consul
	fi
}

create_jmeter_slave_machine() {
        local machine_name
        machine_name=$1
	if ! docker-machine ls -q|grep -q "$machine_name";
	then
		docker-machine create \
		    --driver ovh \
		    --engine-label type=jmeter-slave \
                    --ovh-ssh-key jfroche \
                    --ovh-project loadtesting \
                    --ovh-ssh-user ubuntu \
		    --ovh-flavor "vps-ssd-1" \
		    --engine-opt="cluster-store=consul://$(docker-machine ip consul):8500" \
		    --engine-opt="cluster-advertise=ens3:2376" \
		    --swarm-discovery="consul://$(docker-machine ip consul):8500" \
		    --swarm \
		    "$machine_name"
	fi
}

create_jmeter_slave_container() {
        local slave_host
        slave_host=$1
        eval "$(docker-machine env --swarm site)"
        ip=$(docker-machine ip "$slave_host")
        if ! docker ps | grep -q "jfroche/jmeter";
        then
            docker-machine ssh "$slave_host" "sudo mkdir -p /load_tests && sudo chown ubuntu:ubuntu /load_tests"
            docker run \
                --detach \
                --network=loadtesting_cluster \
                --volume /load_tests:/load_tests \
                --publish 1099:1099 \
                --env IP="$ip" \
                --env constraint:node=="$slave_host" \
                jfroche/jmeter:1.5
        fi
}

create_consul_services() {
        eval "$(docker-machine env consul)"
        if ! docker ps | grep -q "progrium/consul";
        then
                docker run -d --restart=always \
                        -p "8500:8500" \
                        -p 8600:53/udp \
                        --name consul \
                        -h "consul" \
                        progrium/consul -server -bootstrap
        fi
        if ! docker ps | grep -q "magiconair/fabio";
        then
                docker-machine ssh consul 'sudo rm -fr /tmp/fabio.properties'
                cat <<EOF | docker-machine ssh consul 'cat - > /tmp/fabio.properties'
registry.consul.addr = $(docker-machine ip consul):8500
EOF
                docker run -d --restart=always \
                        -p "80:9999" \
                        -p 9998 \
                        --name fabio \
                        -h "consul" \
                        -v /tmp/fabio.properties:/etc/fabio/fabio.properties \
                        --label SERVICE_NAME="fabio" \
                        --label SERVICE_9998_TAGS="fabio,urlprefix-/fabio" \
                        --label SERVICE_9998_CHECK_HTTP="/" \
                        magiconair/fabio:latest
        fi

}

function join { local IFS="$1"; shift; echo "$*"; }

start_jmeter_tests() {
        set -x
        IP=$(docker-machine ip consul)
        SLAVES_IPS=()
        for machine in $(docker-machine ls --filter label=type=jmeter-slave -q);
        do
                SLAVES_IPS+=($(docker-machine inspect -f "{{.Driver.IPAddress}}" "$machine"))
        done;
        SLAVES=$(join , "${SLAVES_IPS[@]}")
        echo "$SLAVES"
        TEST_DIR="test1"
        TEST_PLAN="csv-test"
        eval "$(docker-machine env --swarm site)"
        TEST_CONTAINER=$(docker run \
            --detach \
            --publish 1099:1099 \
            --network=loadtesting_cluster \
            --volume /load_tests/$TEST_DIR:/load_tests/$TEST_DIR \
            --env TEST_DIR=$TEST_DIR \
            --env TEST_PLAN=$TEST_PLAN \
            --env IP="$IP" \
            --env MODE="client" \
            --env REMOTE_HOSTS="$SLAVES" \
            --env constraint:node=="consul" \
            --env EXTRA_PARAMETERS="-Ghostname=instance:8081/theux -Gcsv=www.theux.be.csv" \
            jfroche/jmeter:1.6)
        docker logs -f "$TEST_CONTAINER"
        docker rm "$TEST_CONTAINER"
        docker-machine ssh consul cat /load_tests/test1/results.txt
}

create_docker_network() {
        set -x
        eval "$(docker-machine env --swarm site)"
        if ! docker network ls | grep -q "loadtesting_cluster";
        then
                docker network create -d overlay loadtesting_cluster
        fi
}

create_registrator_service() {
        set -x
        eval "$(docker-machine env --swarm site)"
        if ! docker ps | grep -q "gliderlabs/registrator";
        then
        docker run -d \
                   -v /var/run/docker.sock:/tmp/docker.sock \
                   -h registrator-swarm-master \
                   --name registrator-swarm-master \
                   gliderlabs/registrator:v7 \
                   -ip="$(docker-machine ip site)" \
                   consul://"$(docker-machine ip consul)":8500
        fi
}

function sync_jmeter_data() {
        local destination_host
        destination_host=$1
        docker-machine ssh "$destination_host" "sudo mkdir -p /load_tests && sudo chown ubuntu:ubuntu /load_tests"
        docker-machine scp -r test1 "$destination_host":/load_tests
}

function start_site() {
        eval "$(docker-machine env --swarm site)"
        docker-compose up -d
}

sync_data() {
	set -x
	sudo -E -s rsync -azhe "ssh -o StrictHostKeyChecking=no" --stats --omit-dir-times /srv/instances/theux/ ubuntu@"$(docker-machine ip site)":/srv/instances/theux/
	sudo -E -s rsync -azhe "ssh -o StrictHostKeyChecking=no" --stats --omit-dir-times /srv/docker_scripts/website-theux/ ubuntu@"$(docker-machine ip site)":/srv/docker_scripts/website-theux/
	docker-machine ssh site sudo chown -R 913 /srv/instances/theux
}

sync_docker_image() {
        set -x
        eval "$(docker-machine env -u)"
	REMOTE_DOCKER_IMAGE_ID=$(ssh -o StrictHostKeyChecking=no ubuntu@"$(docker-machine ip site)" sudo docker inspect --format '{{.Id}}' docker-prod.imio.be/mutual-website 2> /dev/null || true)
	LOCAL_DOCKER_IMAGE_ID=$(docker inspect --format '{{.Id}}' docker-prod.imio.be/mutual-website)
	if [[ ! "$REMOTE_DOCKER_IMAGE_ID" == "$LOCAL_DOCKER_IMAGE_ID" ]];
	then
		docker save docker-prod.imio.be/mutual-website:latest | \
		     ssh -o StrictHostKeyChecking=no ubuntu@"$(docker-machine ip site)" 'sudo docker load'
	fi
}

fetch_docker_machine() {
        mkdir -p docker
	if ! [ -f docker/docker-machine ]; then
                curl -L https://github.com/docker/machine/releases/download/v0.8.0/docker-machine-"$(uname -s)"-"$(uname -m)" > docker/docker-machine
	fi
	chmod +x docker/docker-machine
}

fetch_docker_machine_ovh_driver() {
        mkdir -p docker
	if ! [ -f docker/docker-machine-driver-ovh ]; then
                curl -L https://github.com/jfroche/docker-machine-driver-ovh/releases/download/1.0.1/docker-machine-driver-ovh > docker/docker-machine-driver-ovh
	fi
	chmod +x docker/docker-machine-driver-ovh
}

fetch_docker_compose() {
        mkdir -p docker
	if ! [ -f docker/docker-compose ]; then
                curl -L https://github.com/docker/compose/releases/download/1.8.0/docker-compose-"$(uname -s)"-"$(uname -m)" > docker/docker-compose
	fi
	chmod +x docker/docker-compose
}

fetch_docker() {
        mkdir -p docker
	if ! [ -f docker/docker ]; then
                curl -L https://get.docker.com/builds/Linux/x86_64/docker-1.11.2.tgz | tar xvzf -
	fi
}

fetch_urls() {
        set -euo pipefail

        if [ $# -lt 3 ]; then
          echo 1>&2 "$0: not enough arguments"
          exit 1
        fi

        WEBSITE=$1
        START_DATETIME=$2
        END_DATETIME=$3

        DAY=$(date -d "$START_DATETIME" +%Y.%m.%d)
        START=$(date -d "$START_DATETIME" +%s%3N)
        END=$(date -d "$END_DATETIME" +%s%3N)
        read -d '' QUERY << EOF || true
{
  "query": {
    "filtered": {
      "filter": {
        "bool": {
          "must": [
            {
              "range": {
                "@timestamp": {
                  "from": $START,
                  "to": $END
                }
              }
            },
            {
              "fquery": {
                "query": {
                  "query_string": {
                    "query": "@syslog_program=httpd"
                  }
                },
                "_cache": true
              }
            },
            {
              "fquery": {
                "query": {
                  "query_string": {
                    "query": "http_host:($WEBSITE)"
                  }
                },
                "_cache": true
              }
            }
          ]
        }
      }
    }
  },
  "fields": [
    "request"
  ],
  "size": 10000,
  "sort": [
    {
      "@timestamp": {
        "order": "desc",
        "ignore_unmapped": true
      }
    }
  ]
}
EOF
        curl -s -XPOST http://logs.imio.be:9200/logstash-"$DAY"/_search -d "$QUERY" | jq -r ".hits.hits[].fields.request[0]"

}
