lha is a light home automation application

The application could be run on small computers such as the Raspberry Pi or the WD MyCloud.
It is built around a scheduler and an HTTP server based on [luajls](https://github.com/javalikescript/luajls).
The application allows [Lua](https://www.lua.org/) extensions and [Blockly](https://developers.google.com/blockly/) scripts.
It exposes a [Web of Things](https://iot.mozilla.org/wot/) API.

Available extensions are:
* [ConBee](https://phoscon.de/en/conbee), Dresden elektronik ConBee REST API
* [Philips Hue](http://meethue.com/), Hue Bridge REST API
* Monitoring, based on Lua and [SIGAR](https://github.com/hyperic/sigar)
* Ping, Test the reachability of a host on the network

You could find the [luajls binaries here](http://javalikescript.free.fr/lua/download/).

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

You could find the required libraries [here](https://javalikescript.github.io/lha/download/lha_assets.20200329.zip).
