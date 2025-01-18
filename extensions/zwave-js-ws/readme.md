## Overview

This extension exposes ZWave devices through ZWave-JS.

## Prerequisites

ZWave-JS-UI must be available.

It is recommended to use Docker to run the ZWave-JS-UI server.

### Docker

On Raspberry PI the setup of Docker can be painfull, please consult the [Docker documentation](https://docs.docker.com/engine/install/debian/).

Bookworm may hang requiring to use Bullseye.

Optionally retrieve the Docker image.
```sh
docker pull zwavejs/zwave-js-ui:latest
lsusb
```

Start ZWave-JS-UI in background.
```sh
mkdir $HOME/zwave-js-ui
docker run -d --name zwavejs --restart unless-stopped -p 8091:8091 -p 3000:3000 -e TZ=Europe/Paris \
--device=/dev/serial/by-id/usb-0000_0000-if00:/dev/zwave \
-v $HOME/zwave-js-ui:/usr/src/app/store zwavejs/zwave-js-ui:latest
```

## Setup

You need to activate the WebSockets feature on your ZWave-JS server.

## Usage

You need to include your device in ZWave-JS prior adding it through this extension.

The JSON mapping defines the how the ZWave devices are mapped to things.
