local http = require "luci.httpclient" -- luci-lib-httpclient
local json = require "luci.json" -- luci-lib-json
local util = require "luci.util" -- luci-lib-base
local sha2 = require "sha2" -- https://raw.githubusercontent.com/Egor-Skriptunoff/pure_lua_SHA/master/sha2.lua

local math = math
local type = type
local pairs = pairs
local tostring = tostring
local print = print
local pcall = pcall
local error = error
local string = string

module "sagemcom"

DEBUG = false

local function debug(s)
  if DEBUG then
    print(s)
  end
end

local function urlencode(str) -- the luci httpclient urlencode isn't compatible with the sagemcom
  return string.gsub(str, "([^0-9a-zA-Z!'()*._~-])", function (c) return string.format("%%%02X", string.byte(c)) end)
end

Client = util.class()

function Client.__init__(self, addr)
  debug("connecting to " .. addr)
  self.addr = addr
  self.session = nil

  debug("getting config from gui js")
  local guijs, status, msg = http.request_to_buffer("http://" .. addr .. "/gui/js/gui-core.js")
  if not guijs then error("failed to get gui js, status=" .. status .. " msg=" .. msg) end

  local idx1, idx2 = guijs:find("gui.opt%s*=%s*{")
  if not idx2 then error("couldn't find start of gui.opt") end
  self.guiopt = guijs:sub(idx2)
  local idx1, idx2 = self.guiopt:find("}%s*;")
  if not idx1 then error("couldn't find end of gui.opt") end
  self.guiopt = self.guiopt:sub(0, idx1)

  local idx1, idx2 = self.guiopt:find('GUI_PASSWORD_SALT%s*:%s*"[^"]*"%s*[,}]')
  if idx1 and idx2 then
    local value = self.guiopt:sub(idx1, idx2)
    local idx1, idx2 = value:find(':')
    value = value:sub(idx2+1, #value-1)
    self.salt = json.decode(value)
    if not self.salt then error("couldn't decode salt value json " .. value) end
    if #self.salt > 0 then
      debug("- using salt " .. self.salt)
    else
      debug("- not using salt")
    end
  end

  self.hash = self.guiopt:find("GUI_ACTIVATE_SHA512ENCODE_OPT%s*:%s*1%s*[,}]") and sha2.sha512 or sha2.md5
  debug("- using " .. self:hasher() .. " for auth hash")
end

function Client.hasher(self)
  if self.hash == sha2.sha512 then
    return "sha512"
  elseif self.hash == sha2.md5 then
    return "md5"
  else
    return "unknown"
  end
end

function Client.rpc(self, actions, priority)
  if not self.session then
    error("not logged in")
  end

  self.session.seq = self.session.seq + 1
  local cnonce = math.random(2147483647)
  local pass = self.hash(self.session.password .. (#self.salt > 0 and (":" .. self.salt) or ""))
  local cred = self.hash(self.session.username .. ":" .. self.session.nonce .. ":" .. pass)
  local auth = self.hash(cred .. ":" .. self.session.seq .. ":" .. cnonce .. ":JSON:/cgi/json-req")

  local obj = {
    ["request"] = {
      ["id"] = self.session.seq,
      ["session-id"] = tostring(self.session.id),
      ["priority"] = priority and true or false,
      ["actions"] = actions,
      ["cnonce"] = cnonce,
      ["auth-key"] = auth,
    },
  }

  local resp, status, msg = http.request_to_buffer("http://" .. self.addr .. "/cgi/json-req", {
    method = "POST",
    body = "req=" .. urlencode(json.encode(obj)),
  })
  if not resp then
    error("failed to make request, status=" .. status .. " msg=" .. msg)
  end

  local obj = json.decode(resp)
  if not obj then
    error("null response or json decode failed for " .. resp)
  end
  if type(obj["reply"]) ~= "table" then
    error("no reply object in response " .. resp)
  end
  if type(obj["reply"]["error"]) ~= "table" then
    error("no error object in reply " .. resp)
  end
  if type(obj["reply"]["error"]["description"]) ~= "string" then
    error("no error description in reply " .. resp)
  end
  if obj["reply"]["error"]["description"] ~= "XMO_REQUEST_NO_ERR" then
    if obj["reply"]["error"]["description"] ~= "Ok" then
      if obj["reply"]["error"]["description"] ~= "XMO_REQUEST_ACTION_ERR" then
        error("sagemcom error " .. obj["reply"]["error"]["description"])
      end
    end
  end
  if type(obj["reply"]["actions"]) ~= "table" then
    error("no actions array in reply " .. resp)
  end
  if type(obj["reply"]["events"]) ~= "table" then
    error("no events array in reply " .. resp)
  end
  return obj["reply"]["actions"] -- note: each action result can also have an error
end

function Client.logout(self)
  if self.session then
    self:rpc({
      {
        ["id"] = 0,
        ["method"] = "logOut",
      },
    })
  end
  self.session = nil
end

function Client.login(self, username, password)
  local username = tostring(username or "guest")
  local password = tostring(password or "")

  debug("logging in as " .. username)
  self.session = {
    username = username,
    password = password,
    id = 0,
    nonce = "",
    seq = -1,
  }

  local actions = self:rpc({
    {
        ["id"] = 0,
        ["method"] = "logIn",
        ["parameters"] = {
            ["user"] = self.session.username,
            ["persistent"] = true,
            ["session-options"] = {
                ["nss"] = {{
                    ["name"] = "gtw",
                    ["uri"] = "http://sagemcom.com/gateway-data",
                }},
                ["language"] = "ident",
                ["context-flags"] = {
                    ["get-content-name"] = true,
                    ["local-time"] = true,
                },
                ["depth"] = 2,
                ["capability-depth"] = 2,
                ["capability-flags"] = {
                    ["name"] = true,
                    ["default-value"] = false,
                    ["restriction"] = true,
                    ["description"] = false,
                },
                ["time-format"] = "ISO_8601",
                ["write-only-string"] = "_XMO_WRITE_ONLY_",
                ["undefined-write-only-string"] = "_XMO_UNDEFINED_WRITE_ONLY_",
            },
        },
    },
  })
  if #actions ~= 1 then
    error("expected exactly one action reply")
  end
  if actions[1]["error"]["description"] ~= "XMO_NO_ERR" then
    error("sagemcom error " .. actions[1]["error"]["description"])
  end
  if type(actions[1]["callbacks"][1]["parameters"]["id"]) ~= "number" then
    error("session id not set in response")
  end
  if type(actions[1]["callbacks"][1]["parameters"]["nonce"]) ~= "string" then
    error("server nonce not set in response")
  end
  self.session.id = actions[1]["callbacks"][1]["parameters"]["id"]
  self.session.nonce = actions[1]["callbacks"][1]["parameters"]["nonce"]
end

function Client.get(self, xpath, value)
  debug("getting " .. xpath)
  local actions = self:rpc({
    {
      ["id"] = 0,
      ["method"] = "getValue",
      ["xpath"] = xpath,
      ["options"] = {},
    },
  })
  if #actions ~= 1 then
    error("expected exactly one action reply")
  end
  if actions[1]["error"]["description"] ~= "XMO_NO_ERR" then
    error("sagemcom error " .. actions[1]["error"]["description"])
  end

  local values = {}
  for _, callback in pairs(actions[1]["callbacks"]) do
    if callback["result"]["description"] ~= "XMO_NO_ERR" then
      error("sagemcom error " .. callback["result"]["description"] .. " for " .. callback["xpath"])
    end
    debug("- got " .. callback["xpath"] .. " = " .. json.encode(callback["parameters"]["value"]))
    values[callback["xpath"]] = callback["parameters"]["value"]
  end
  return values
end

function Client.set(self, xpath, value)
  debug("setting " .. xpath .. " = " .. tostring(value))
  local actions = self:rpc({
    {
      ["id"] = 0,
      ["method"] = "setValue",
      ["xpath"] = xpath,
      ["parameters"] = {
        ["value"] = value,
      },
      ["options"] = {},
    },
  })
  if #actions ~= 1 then
    error("expected exactly one action reply")
  end
  if actions[1]["error"]["description"] ~= "XMO_NO_ERR" then
    error("sagemcom error " .. actions[1]["error"]["description"])
  end

  local xpaths = {}
  for _, callback in pairs(actions[1]["callbacks"]) do
    if callback["result"]["description"] ~= "XMO_NO_ERR" then
      error("sagemcom error " .. callback["result"]["description"] .. " for " .. callback["xpath"])
    end
    debug("- set " .. callback["xpath"])
    xpaths[#xpaths+1] = callback["xpath"]
  end
  return xpaths
end
