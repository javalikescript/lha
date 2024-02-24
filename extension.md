
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

