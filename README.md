lha is a light home automation application

> :warning: The project is still experimental.

The application could be run on small computers such as the Raspberry Pi or the WD MyCloud.
It is built around a scheduler and an HTTP server based on [luajls](https://github.com/javalikescript/luajls).
The application allows [Lua](https://www.lua.org/) extensions and [Blockly](https://developers.google.com/blockly/) scripts.
It exposes a [Web of Things](https://iot.mozilla.org/wot/) API.

Available extensions are:
* [ConBee](https://phoscon.de/en/conbee), Dresden elektronik ConBee REST API
* [Philips Hue](http://meethue.com/), Hue Bridge REST API
* [Z-Wave JS](https://github.com/zwave-js), Z-Wave JS API using Zwave to MQTT
* [MQTT](https://mqtt.org/) Broker, provides a light message broker
* HTTPS server, provides lha on a secure server
* [Docker](https://www.docker.com/), allows to manage docker remotely
* Monitoring, based on Lua and [libuv](https://github.com/luvit/luv)
* Ping, Test the reachability of a host on the network

You could find the [luajls binaries here](https://github.com/javalikescript/luajls/releases/latest) or [here](http://javalikescript.free.fr/lua/download/).

lha includes a web extension which requires the following libraries:
* "vuejs" is licensed under the MIT License see https://vuejs.org/
  *Reactive, component-oriented view layer for modern web interfaces*
* "blockly" is licensed under the Apache License 2.0 see https://developers.google.com/blockly/
  *Blockly is a library from Google for building beginner-friendly block-based programming languages*
* "Chart.js" is licensed under the MIT License see http://chartjs.org/
  *Simple yet flexible JavaScript charting for designers & developers*
* "Moment.js" is licensed under the MIT License see https://momentjs.com/
  *Parse, validate, manipulate, and display dates and times in JavaScript*
* "Font Awesome Free" is licensed under multiple licenses see https://fontawesome.com/license/free
  *The iconic font and CSS framework*
* "fetch" is licensed under the MIT license see https://github.com/github/fetch/releases
* "promise" is licensed under the MIT license see https://github.com/taylorhakes/promise-polyfill

You could find the required libraries [here](https://javalikescript.github.io/lha/download/lha_assets.20220209.zip).
