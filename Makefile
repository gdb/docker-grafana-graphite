# docker-grafana-graphite makefile
VERSION = $$(cat VERSION)

# Environment Varibles
CONTAINER = kamon-grafana-dashboard

.PHONY: up

all : build push

prep :
	mkdir -p \
		data/whisper \
		data/elasticsearch \
		data/grafana \
		log/graphite \
		log/graphite/webapp \
		log/elasticsearch

pull :
	docker-compose pull

up : prep pull
	docker-compose up -d

down :
	docker-compose down

shell :
	docker exec -ti $(CONTAINER) /bin/bash

tail :
	docker logs -f $(CONTAINER)

build:
	docker build -t thegdb/grafana_graphite:$(VERSION) .
	docker tag thegdb/grafana_graphite:$(VERSION) thegdb/grafana_graphite

push:
	docker push thegdb/grafana_graphite:$(VERSION)
	docker push thegdb/grafana_graphite
