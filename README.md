# store
testing traefik


Nota: si tiene apache ejecutandose el contenedor no podra iniciar 
por conflictos de puertos, es necesario apagar apache antes de iniciar 

primero se debe crear la red app para el container 
	docker network create app
Luego se ejeucuta el comando docker-compose up -d
	docker-compose up -d

Este comando descarga el container si no existe en el sistema o 
solo iniciara dicho contenedor si a sido descargado previamente.



