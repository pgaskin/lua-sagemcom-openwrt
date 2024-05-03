#!/usr/bin/env lua

local sagemcom = require "sagemcom"

io.stdout:setvbuf("no")
io.stderr:setvbuf("no")
math.randomseed(os.time())

if #arg ~= 4 and #arg ~= 5 then
  print("usage: " .. arg[0] .. " IP USERNAME PASSWORD get|enable|disable [RADIO_ALIAS|RADIO_INDEX]")
  os.exit(2)
end

if #arg == 4 then
  xpath = "Device/WiFi/Radios/Radio/Enable"
elseif arg[5]:find("%D") then
  xpath = "Device/WiFi/Radios/Radio[Alias='" .. arg[5] .. "']/Enable" -- e.g., RADIO2G4, RADIO5G, RADIO6G
elseif arg[5] == "0" then
  print("error: radios are indexed starting at 1")
  os.exit(2)
else
  xpath = "Device/WiFi/Radios/Radio[@uid='" .. arg[5] .. "']/Enable"
end

client = sagemcom.Client(arg[1])
client:login(arg[2], arg[3])

op = arg[4]
if op == "get" or op == "query" then
  for key, value in pairs(client:get(xpath)) do
    print("get " .. client.addr .. " " .. key .. " = " .. tostring(value))
  end
else
  if op == "enable" or op == "1" or op == "true" or op == "on" then
    state = true
  elseif op == "disable" or op == "0" or op == "false" or op == "off" then
    state = false
  else
    print("error: first argument, if provided, must be 1/true/on/0/false/off/query/get")
    os.exit(2)
  end
  client:set(xpath, state)
  print("set " .. client.addr .. " " .. xpath .. " = " .. tostring(state))
end
