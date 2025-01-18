## Overview

This extension allows to connect to the Conbee II via the deCONZ application.

This extension only requires the REST API and WebSockets.

See the [Phoscon documentation](https://phoscon.de/en/conbee2/install#docker) and the [docker repository](https://github.com/deconz-community/deconz-docker#readme).

## Prerequisites

The deCONZ app must be available.

It is recommended to use Docker to run the deCONZ app.

### Docker

On Raspberry PI the setup of Docker can be painfull, please consult the [Docker documentation](https://docs.docker.com/engine/install/debian/).

Optionally retrieve the Docker image.
```sh
docker pull deconzcommunity/deconz:stable
lsusb
```

Start deCONZ in background.
```sh
mkdir $HOME/deconz
docker run -d --name=deconz --restart=unless-stopped -p 8080:8080 -p 8088:8088 \
-e DECONZ_WEB_PORT=8080 -e DECONZ_WS_PORT=8088 \
-v /etc/localtime:/etc/localtime:ro -v $HOME/deconz:/opt/deCONZ \
-e DECONZ_DEVICE=/dev/ttyACM0 --device=/dev/serial/by-id/usb-dresden_elektronik_ingenieurtechnik_GmbH_ConBee_II-if00:/dev/ttyACM0 \
deconzcommunity/deconz:stable
```

## Setup

You will need to acquire an API key.

You could use `curl` with the gateway credentials:
```sh
curl --user "login:password" -X POST http://localhost:8080/api
```


## Usage

You need to add your device in the Phoscon app prior adding it through this extension.

The JSON mapping defines the how the Conbee devices are mapped to things.
