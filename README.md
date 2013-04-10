DynamicDescription
==================

DynamicDescription is a simple Obj-C library that returns a detailed description of an object (its ivars). It can be called manually passing the object and NULL for the selector (it's unused), or it can replace the description method (or any similar method) for a particular class.

It will display all the ivar information (names and current values) that it can for the object specified.

Example
-------

