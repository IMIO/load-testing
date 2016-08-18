clean:
	rm -fr docker

remove-machines:
	PATH=$(PWD)/docker:$(PATH) docker-machine rm -y -f consul jmeter-slave-1 site
