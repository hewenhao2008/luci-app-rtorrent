--[[
LuCI - Lua Configuration Interface - rTorrent client

Copyright 2014-2015 Sandor Balazsi <sandor.balazsi@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

local rtorrent = require "rtorrent"
local http = require "socket.http"
local common = require "luci.model.cbi.rtorrent.common"

local hash = luci.dispatcher.context.requestpath[4]
local details = rtorrent.batchcall(hash, "d.", {"name"})
local format, total, map = {}, {}, {}

function map.googlemap(latitude, longitude, zoom)
	return "https://google.com/maps/place/%s,%s/@%s,%s,%sz" % {latitude, longitude, latitude, longitude, zoom}
end

function map.openstreetmap(latitude, longitude, zoom)
	return "http://www.openstreetmap.org/?mlat=%s&mlon=%s#map=%s/%s/%s/m" % {latitude, longitude, zoom, latitude, longitude}
end

function format.address(r, v)
	total["address"] = (total["address"] or 0) + 1
	local map = map.googlemap(r.latitude, r.longitude, 11)
	-- local map = map.openstreetmap(r.latitude, r.longitude, 11)
	local flag = "<img src=\"http://www.iplocation.net/images/flags/%s.gif\" />" % string.lower(r["country_code"])
	return "%s <a href=\"%s\" target=\"_blank\">%s</a>" % {flag, map, v}
end

function format.completed_percent(r, v)
	return string.format("%.1f%%", v)
end

function format.down_rate(d, v)
	total["down_rate"] = (total["down_rate"] or 0) + v
	return string.format("%.2f", v / 1000)
end

function format.up_rate(d, v)
	total["up_rate"] = (total["up_rate"] or 0) + v
	return string.format("%.2f", v / 1000)
end

function format.down_total(d, v)
	return "<div title=\"%s B\">%s</div>" % {v, common.human_size(v)}
end

function format.up_total(d, v)
	return format.down_total(d, v)
end

function json2table(json)
	loadstring("j2t = " .. string.gsub(string.gsub(json, '([,%{])%s*\n?%s*"', '%1["'), '"%s*:%s*', '"]='))()
	return j2t
end

function ip2geo(ip)
	-- return http.request("http://www.geoplugin.net/json.gp?ip=%s" % ip)
	return http.request("http://www.telize.com/geoip/%s" % ip)
end

function add_location(r)
	for i, j in pairs(json2table(ip2geo(r.address))) do
		r[i] = j
	end
	local location = {}
	for _, k in ipairs({"country", "region", "city"}) do
		if r[k] ~= "" then table.insert(location, r[k]) end
	end
	r["location"] = table.concat(location, "/")
end

function add_summary(list)
 	table.insert(list, {
 		["address"] = "TOTAL: " .. total["address"] .. " pcs.",
 		["down_rate"] = string.format("%.2f", total["down_rate"] / 1000),
 		["up_rate"] = string.format("%.2f", total["up_rate"] / 1000)
 	})
end

local list = rtorrent.multicall("p.", hash, 0, "address", "completed_percent", "client_version", 
	"down_rate", "up_rate", "up_total", "down_total")

for _, r in ipairs(list) do
	add_location(r)
	for k, v in pairs(r) do
		r[k] = format[k] and format[k](r, v) or tostring(v)
	end
end

f = SimpleForm("rtorrent", details["name"])
f.redirect = luci.dispatcher.build_url("admin/rtorrent/main")
f.reset = false
f.submit = false

if #list > 1 then add_summary(list) end
t = f:section(Table, list)
t.template = "rtorrent/list"
t.pages = common.get_pages(hash)
t.page = "peer list"

AbstractValue.tooltip = function(self, s) self.hint = s return self end

t:option(DummyValue, "address", "Address"):tooltip("Peer IP address").rawhtml = true
t:option(DummyValue, "client_version", "Client"):tooltip("Client version")
t:option(DummyValue, "location", "Location"):tooltip("Location: country/region/city")
t:option(DummyValue, "completed_percent", "Done"):tooltip("Download done percent")
t:option(DummyValue, "down_rate", "Down<br />speed"):tooltip("Download speed in kb/s")
t:option(DummyValue, "up_rate", "Up<br />speed"):tooltip("Upload speed in kb/s")
t:option(DummyValue, "down_total", "Downloaded"):tooltip("Total downloaded").rawhtml = true
t:option(DummyValue, "up_total", "Uploaded"):tooltip("Total uploaded").rawhtml = true

return f

