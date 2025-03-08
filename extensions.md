
The lha engine is meant to be enhanced by extensions.

The `core` extensions are included with lha, `other` Lua extensions could be added in the work `extensions` folder.
The `script` extensions are user defined and located in the work `scripts` folder.

## Core Extensions

Available core extensions are:
* [ConBee II](https://github.com/javalikescript/lha/blob/master/extensions/conbee-2/readme.md), Dresden elektronik [ConBee](https://phoscon.de/en/conbee) REST API  
* [Philips Hue V2](https://github.com/javalikescript/lha/blob/master/extensions/hue-v2/readme.md), [Hue](https://www.philips-hue.com/) Bridge REST API  
* [Z-Wave JS WS](https://github.com/javalikescript/lha/blob/master/extensions/zwave-js-ws/readme.md), [Z-Wave JS](https://github.com/zwave-js) API  
* MQTT Broker, provides a light [MQTT](https://mqtt.org/) message broker
* [Generic](https://github.com/javalikescript/lha/blob/master/extensions/generic/readme.md)  
* Web Chart  
* [Web Scripts](https://github.com/javalikescript/lha/blob/master/extensions/web-scripts/readme.md)  
* [Share](https://github.com/javalikescript/lha/blob/master/extensions/share/readme.md) server folders to download and upload files
* [Users](https://github.com/javalikescript/lha/blob/master/extensions/users/readme.md) Management, adds user and permissions
* [HTTPS](https://github.com/javalikescript/lha/blob/master/extensions/https/readme.md) server, provides lha on a secure server
* [Self](https://github.com/javalikescript/lha/blob/master/extensions/self/readme.md) monitoring, based on Lua and [libuv](https://github.com/luvit/luv)

You need to include your devices using the dedicated tool such as deCONZ, Hue App or Z-Wave JS UI Control Panel.

## Scripts Extensions

There are 3 types of scripts, `blocks`, `view` and `lua` each having a dedicated editor.

A blocks extension is a server side extension composed with basic blocks to react to thing property value modifications.
A view extension is a front-end extension composed with HTML to show thing property values.
A lua extension is a custom extension in a single Lua script without configuration.

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
