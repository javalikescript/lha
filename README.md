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
