#!/usr/bin/env lua

local sagemcom = require "sagemcom"
local json = require "luci.json"

io.stdout:setvbuf("no")
io.stderr:setvbuf("no")
math.randomseed(os.time())

sagemcom.DEBUG = true

client = sagemcom.Client("192.168.2.1")
client:login("admin", "password")
print(json.encode(client:get("Device/WiFi/Radios/Radio/Enable")))
print(json.encode(client:set("Device/WiFi/Radios/Radio/Enable", false)))
print(json.encode(client:get("Device/WiFi/Radios/Radio/Enable")))
print(json.encode(client:get("Device/WiFi/Radios/*")))
print(json.encode(client.session))
print(client.guiopt)
