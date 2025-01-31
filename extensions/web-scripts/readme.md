
This extension provides a web page to create scripts.

There are 3 types of scripts, `blocks`, `view` and `lua` each having a dedicated editor.

A `blocks` script is a server side extension composed with basic blocks to react to thing property value modifications.
A `view` script is a front-end extension composed with HTML to show and interact with thing property values.
A `lua` script is a raw extension.

## Blocks

This type of script allows to graphically define automatic behavior.

You have access to generic Blockly components in the categories: Logic, Loops, Math, Text, List.
You could also define Variables and Functions.
You have specific categories: Data, Event, Expression.

The Data category allows to get or set a thing property value or to watch the changes on a property value.
* get: gets the thing property current value
* set: sets the thing property value
* watch: triggers an action on a thing property value change with the new value as parameter

The Event category allows to react on an engine event, to trigger execution on a recurring schedule or a timer.
* on: triggers an action on an engine event
* every: triggers an action on a schedule, minutes hours days months weekdays, ex: */5 1,3 2-4
* set timer: triggers an action after a delay, the timer is unique for the name and can be cancelled
* clear timer: clears a timer

## View

This type of script allows to compose user interface using HTML code.

In the configuration you could define an icon that will be used to present the view page in the default home page.
You also define the title and the id that is used in the URL path.

You could configure multiple mappings between a key and a thing property value. The key could be used in the HTML code to interact with the thing property.

## Lua

This type of script allows to create raw extension.

The script receives the extension as a parameter.

```lua
local extension = ...
```

You then have access to the extension and Thing API.
 