
The lha engine is meant to be enhanced by extensions.

The `core` extensions are included with lha, `other` extensions could be added in the work `extensions` folder.
The `script` extensions are user defined and located in the work `scripts` folder.

## Core Extensions

Available core extensions are:
* [ConBee II](https://phoscon.de/en/conbee), Dresden elektronik ConBee REST API  
The recommended tool is [deCONZ](https://github.com/deconz-community/deconz-docker) using docker
* [Philips Hue V2](https://www.philips-hue.com/), Hue Bridge REST API  
The recommended tool is the Hue Bridge
* [Z-Wave JS WS](https://github.com/zwave-js), Z-Wave JS API  
The recommended tool is [Z-Wave JS UI](https://github.com/zwave-js/zwave-js-ui) using docker
* [MQTT](https://mqtt.org/) Broker, provides a light message broker
* Generic  
Create virtual things, usefull for scripting
* Web Chart  
Display thing property values in a time chart
* Web Dashboard  
Setup tiles with relevant thing properties
* Web Scripts  
Automatically trigger thing modifications or show custom data
* Share server folders to download and upload files
* Users Management, adds user and permissions
* HTTPS server, provides lha on a secure server
* Self monitoring, based on Lua and [libuv](https://github.com/luvit/luv)
* Ping, Test the reachability of a host on the network

You need to include your devices using the dedicated tool such as deCONZ, Hue App or Z-Wave JS UI Control Panel.

## Scripts Extensions

There are 3 types of scripts, `blocks`, `view` and `lua` each having a dedicated editor.

A blocks extension is a server side extension composed with basic blocks to react to thing property value modifications.
A view extension is a front-end extension composed with HTML to show thing property values.

## Lua Extensions

An extension consists in a folder containing a manifest file and a Lua script.

The manifest is loaded from the file *manifest.json* and consists in the extension name and description.

```json
{
  "name": "Serial",
  "description": "Serial RF and sensors",
  "version": "1.0"
}
```

The manifest could define a JSON schema using the *schema* property. The schema described the extension configuration.

The script is loaded from the file *init.lua* or the file name defined in the manifest *script* property.

The script receives the extension as a parameter.

```lua
local extension = ...
```
