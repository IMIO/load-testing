[![IMIO Load testing our websites using a JMeter cluster](http://www.imio.be/logo.png)](https://github.com/IMIO/load-testing)

## What

The goal of this project is to automate measurement of a website response time.
While testing:

  - we don't want to impact production but we want to test website with production data.
  - we want to reduce side effects

We also want to be able to replay previous traffic on a website with this project.

## How

We create new machines on `OVH Cloud` and copy over data required for the website to be running on a new machine.

Here is a list of the tasks:

 - Import all docker components (docker, machine, compose)
 - Create a consul machine
 - Create a site machine as swarm master
 - Copy current data to the new site machine
 - Start the site on the new site machine
 - Create JMeter slave machine with test data

## Tools

We are using concurrent to run tasks in parallel as much as possible.

We use docker, docker-machine, docker-compose.

We use jmeter to run the load testing and create performance reports

We use consul as the service discovery tool for the swarm cluster and for fabio

We use fabio as the dynamic reverse proxy to the site based on consul service discoveries

## TODO

- make site name generic and configurable
