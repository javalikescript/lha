## Overview

This extension allows to connect to the [Matter(.js) Server](https://github.com/matter-js/matterjs-server).

## Prerequisites

The Matter server must be available.

It is recommended to use Docker to run the Matter server.

### Docker

Follow the [Running Matter.js Server in Docker](https://github.com/matter-js/matterjs-server/blob/main/docs/docker.md).

Optionally retrieve the Docker image.
```sh
docker pull ghcr.io/matter-js/matterjs-server:stable
```

Start Matter server in background.
```sh
mkdir $HOME/matter-data
docker run -d --name matterjs-server --restart unless-stopped \
-v $HOME/matter-data:/data --network=host \
-v /run/dbus:/run/dbus:ro -e NOBLE_BINDINGS=dbus -e BLUETOOTH_ADAPTER=0 \
ghcr.io/matter-js/matterjs-server:stable
```

### Open Thread Border Router

If you use an USB dongle to connect to the thread network then you need to setup a thread border router.

Optionally retrieve the Docker image.
```sh
docker pull openthread/border-router
lsusb
```

Start the border router in background.
```sh
mkdir $HOME/otbr-data
docker run -d --name otbr --restart unless-stopped --network=host --cap-add=NET_ADMIN \
-e OT_RCP_DEVICE=spinel+hdlc+uart:///dev/ttyACM0?uart-baudrate=460800 -e OT_INFRA_IF=eth0 -e OT_THREAD_IF=wpan0 -e OT_LOG_LEVEL=7 \
--device=/dev/serial/by-id/usb-SONOFF_SONOFF_Dongle_Plus_MG24:/dev/ttyACM0 \
--device=/dev/net/tun -v $HOME/otbr-data:/data \
openthread/border-router
```

Follow the OpenThread Border Router [Thread Network](https://openthread.io/guides/border-router/form-network) guide to create a nework.

## Setup

Provide the The WebSocket URL, default to `ws://localhost:5580/ws`

## Usage

Access the Matter server web dashboard to commission new nodes.
