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
It exposes a Thing Description JSON API, see [Web of Things](https://www.w3.org/WoT/).

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

The web base pages.  
![tiles](https://github.com/user-attachments/assets/398653c6-2f51-4c8d-a72e-d73043a6b0d3)
![extensions](https://github.com/user-attachments/assets/b879bb4e-8aeb-4d22-8a25-b1f36617f45a)
![things](https://github.com/user-attachments/assets/26904e22-7801-43fc-a789-224a6f43497c)

A chart of temperature sensor.  
![chart](https://github.com/user-attachments/assets/946a697c-652a-4f3a-b86c-11e679955633)

An example of script to send a SMS on an intrusion.  
![script](https://github.com/user-attachments/assets/5be2ba32-8c52-4132-acfb-b2f1f7d1c755)

Custom views.  
![kiosk](https://github.com/user-attachments/assets/69ee4525-a937-4e17-b8ed-56663eaaa8da)
![power](https://github.com/user-attachments/assets/60834f38-34b7-4c7b-b535-d51146cf5c83)
![temp](https://github.com/user-attachments/assets/287bc36a-87d9-4e67-afe7-52f9e017365e)

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
