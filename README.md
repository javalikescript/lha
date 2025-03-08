lha is a light home automation application

## Overview

The lha application allows to
* enrich your existing gateway such as the [Hue](https://www.philips-hue.com/) bridge
* record and display historical device values such as temperature
* interact between incompatible protocols such as _ZigBee_ and _Z-Wave_
* compose advanced automations using [Blockly](https://developers.google.com/blockly/) scripts
* design web views using [HTML](https://html.spec.whatwg.org/) and [Vue.js](https://v2.vuejs.org/)
* create your own [Lua](https://www.lua.org/) extensions

The lha engine manages the extensions including scripts, the things, the scheduler and a web server.
The engine records thing property values in dedicated time based log files.

It is a pure [Lua](https://www.lua.org/) application built around a scheduler and an HTTP server based on [luajls](https://github.com/javalikescript/luajls).
It exposes a [Web of Things](https://iot.mozilla.org/wot/) API.

The lha application could be run on small computers such as the _Raspberry PI_ or the _WD MyCloud_.
It could also be run on any _Linux_ distribution or _Windows_.
The application is small, around 5MB, and does not need any dependency.

## Extensions

lha comes with a bunch of core extensions and allows to add new ones.

See details of [extensions](extensions.md)

## Devices

Any device available through ConBee, Hue or Z-Wave JS could be added by enhancing the extension JSON mapping files.

See list of already available [devices](devices.md)

## Screenshots

An example of a dashboard setup with temperature and motion sensors.
![dashboard](https://user-images.githubusercontent.com/9386420/170430755-c585a479-1277-4eac-a8a8-fc15bcec452d.png)

A chart of temperature sensors.
![data-chart](https://user-images.githubusercontent.com/9386420/170430776-2f4277ba-039f-426c-8c2a-60c7d8bef64a.png)

An example of script to send a SMS on an intrusion.
![alarm-script](https://user-images.githubusercontent.com/9386420/170430789-86008c90-5a5a-4f2c-bd82-911addb9d373.png)

## Setup

Download the [latest](https://github.com/javalikescript/lha/releases/latest) release corresponding to your target OS.
Unzip the archive and launch the engine using `bin/lua lha.lua -ll info`

Open the web interface in a browser.
Go to the extension section to add and configure your extensions.

Note that you will need to provide an authorized user to use the ConBee or Hue bridge.

## Dependencies

The lha release includes web extensions using the following libraries:
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
