#!/usr/bin/env bash


if  docker network ls | grep -w app
then 
    echo "Network with name app already exists"
else
    echo "Creating network app"
    docker network create app
fi

echo "Starting container"
# service apache2 stop
docker-compose up -d

echo "Container started"

