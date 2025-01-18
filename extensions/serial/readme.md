
This extension exposes things from a serial connection.

You could use an Arduino board to retrieve sensor data and expose the data through the serial port.

The messages are sent in JSON format in a single line.

```JSON
[commandId, thingId, value, propertyId]
```

The available commands are:

* 0: WELCOME - To initiate the connexion
* 1: INFO - To discover things
* 2: READ - To read thing property values
* 3: WRITE - To write a thing property value (not implemented)

The messages are received in JSON format in a single line.

```JSON
{
  success: true,
  id: thingId,
  cmd: commandId,
  values: ['humidity', 'temperature', 'pressure', 'custom property name']
}
```
