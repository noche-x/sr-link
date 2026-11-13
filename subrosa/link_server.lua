local link_server = {}

local dgram = require("dgram")
local timer = require("timer")
local uv = require("uv")
local http = require("coro-http")

local config = require("../config")
local db = require("../db")
local linked_roles = require("../discord/linked_roles")
local packets = require("./packets")


local HEARTBEAT_MS = 16000
local REMOVE_EXPIRED_MS = 10000
local AUTH_MAX_AGE_MS = 10000
local ANSWER_CACHE_MS = 30000
local MAX_WRONG_CODES = 5
local WRONG_CODE_WINDOW_MS = 600000


---@type table|nil UDP socket from dgram.createSocket
link_server.socket = nil
---@type { ip: string, port: number }|nil
link_server.master = nil
---@type string|nil our address as the master server sees it
link_server.public_ip = nil
---@type table<number, { auth: table, at: number }> account_id -> the master server's auth packet
link_server.auths = {}
---@type table<string, { message: string, at: number }> "account_id:ticket" -> the answer sent
link_server.answers = {}
---@type table<string, { count: number, since: number }> "steam:<id>" or "account:<id>" -> wrong guesses
link_server.wrong_codes = {}

function link_server.find_master_server()
	local host, base_port = "66.226.72.227", 27590

	local ok, response, body = pcall(
		http.request,
		"GET",
		"https://www.crypticsea.com/anewzero/serverinfo.php",
		{ { "User-Agent", "sr-link-discord" } }
	)
	if ok and response.code == 200 then
		local fields = {}
		-- tab seperated
		for field in body:gmatch("[^\t]+") do
			fields[#fields + 1] = field
		end

		host, base_port = fields[2], tonumber(fields[3])
		if not host or not base_port then
			-- shouldn't happen
			error("unreadable master server info: " .. body)
		end
	else
		-- not good, WARN ALEX
		print("could not reach crypticsea.com, using the default master server")
	end

	local addresses = assert(uv.getaddrinfo(host, nil, { family = "inet", socktype = "dgram" }))
	link_server.master = { ip = addresses[1].addr, port = base_port + 2 }

	print(("master server at %s:%d"):format(link_server.master.ip, link_server.master.port))
end

---@param packet table packet module from packets/
---@param data table|nil fields for packet.write
---@param ip string
---@param port number
function link_server.send(packet, data, ip, port)
	link_server.socket:send(packets.write_packet(packet, data), port, ip)
end

---@param request table decoded info_request
---@param ip string sender
---@param port number sender
function link_server.on_info_request(request, ip, port)
	link_server.send(packets.server_info, {
		build = 38,
		sub_version = ('z'):byte() - 97,
		timestamp = request.timestamp,
		gamemode = 3, -- round
		current_players = 0,
		max_players = 32,
		name = config.server_name,
		id = 80085,
		address = link_server.public_ip,
		port = config.udp_port,
		password_protected = true,
	}, ip, port)
end

---@param ping table decoded master_ping
---@param ip string sender
---@param port number sender
function link_server.on_master_ping(ping, ip, port)
	if ip ~= link_server.master.ip or port ~= link_server.master.port then
		print(("dropped master_ping packet from %s:%d, not the master server"):format(ip, port))
		return
	end

	if link_server.public_ip ~= ping.ip then
		print(("public address is %s:%d"):format(ping.ip, ping.port))
	end

	link_server.public_ip = ping.ip
end

---@param auth table decoded auth
---@param ip string sender
---@param port number sender
function link_server.on_auth(auth, ip, port)
	if ip ~= link_server.master.ip or port ~= link_server.master.port then
		print(("dropped auth packet from %s:%d, not the master server"):format(ip, port))
		return
	end

	link_server.auths[auth.account_id] = { auth = auth, at = uv.now() }
end

-- answers a join, and remembers the answer for the client's resends
---@param key string "account_id:ticket"
---@param ip string
---@param port number
---@param message string
function link_server.reply(key, ip, port, message)
	link_server.answers[key] = { message = message, at = uv.now() }
	link_server.send(packets.connect_response, { reason = message }, ip, port)
end

---@param join table decoded join_request
---@param ip string sender
---@param port number sender
function link_server.on_join_request(join, ip, port)
	local key = join.account_id .. ":" .. join.auth_ticket

	local previous = link_server.answers[key]
	if previous and uv.now() - previous.at <= ANSWER_CACHE_MS then
		link_server.send(packets.connect_response, { reason = previous.message }, ip, port)
		return
	end

	local pending = link_server.auths[join.account_id]
	if not pending or uv.now() - pending.at > AUTH_MAX_AGE_MS or pending.auth.auth_ticket ~= join.auth_ticket then
		print(("dropped join_request packet from %s:%d, invalid auth"):format(ip, port))
		return
	end
	local auth = pending.auth

	local code = join.password:match("^%s*(%d%d%d%d%d%d)%s*$")
	if not code then
		return link_server.reply(key, ip, port, "Enter your 6-digit Discord code as the password.")
	end

	local wrong_code_keys = { "steam:" .. auth.steam_id, "account:" .. auth.account_id }
	for _, wrong_code_key in ipairs(wrong_code_keys) do
		local wrong = link_server.wrong_codes[wrong_code_key]
		if wrong and uv.now() - wrong.since > WRONG_CODE_WINDOW_MS then
			link_server.wrong_codes[wrong_code_key] = nil
		elseif wrong and wrong.count >= MAX_WRONG_CODES then
			return link_server.reply(key, ip, port, "Too many wrong codes. Wait 10 minutes.")
		end
	end

	local link, replaced_discord_id = db.redeem_code(code, auth)
	if not link then
		for _, wrong_code_key in ipairs(wrong_code_keys) do
			local wrong = link_server.wrong_codes[wrong_code_key] or { count = 0, since = uv.now() }
			wrong.count = wrong.count + 1
			link_server.wrong_codes[wrong_code_key] = wrong
		end
		return link_server.reply(key, ip, port, "Invalid or expired code. Get a new one in Discord.")
	end

	print(
		("linked %s (%s, phone %d) to Discord %s"):format(
			auth.player_name,
			auth.steam_id,
			auth.phone_number,
			link.discord_name
		)
	)
	link_server.reply(key, ip, port, "Linked to Discord: " .. link.discord_name)

	linked_roles.update_later(link.discord_id, true)
	if replaced_discord_id then
		linked_roles.update_later(replaced_discord_id, false)
	end
end

link_server.handlers = {
	info_request = link_server.on_info_request,
	master_ping = link_server.on_master_ping,
	auth = link_server.on_auth,
	join_request = link_server.on_join_request,
}

---@param message string the datagram
---@param rinfo table sender { ip, port }
function link_server.on_message(message, rinfo)
	local ip, port = rinfo.ip, rinfo.port
	local ok, packet, data = pcall(packets.read_packet, message)
	if not ok then
		print(("bad packet from %s:%d: %s"):format(ip, port, tostring(packet)))
		return
	end

	local handler = packet and link_server.handlers[packet.name]
	if handler then
		handler(data, ip, port)
	end
end

function link_server.remove_expired()
	local now = uv.now()
	for account_id, pending in pairs(link_server.auths) do
		if now - pending.at > AUTH_MAX_AGE_MS then
			link_server.auths[account_id] = nil
		end
	end

	for key, answer in pairs(link_server.answers) do
		if now - answer.at > ANSWER_CACHE_MS then
			link_server.answers[key] = nil
		end
	end
	
	for key, wrong in pairs(link_server.wrong_codes) do
		if now - wrong.since > WRONG_CODE_WINDOW_MS then
			link_server.wrong_codes[key] = nil
		end
	end
end

function link_server.heartbeat()
	link_server.send(packets.master_ping, nil, link_server.master.ip, link_server.master.port)
end

---@param err string
function link_server.on_socket_error(err)
	print("socket error: " .. tostring(err))
end

function link_server.start()
	link_server.find_master_server()

	link_server.socket = dgram.createSocket("udp4")
	link_server.socket:on("message", link_server.on_message)
	link_server.socket:on("error", link_server.on_socket_error)

	link_server.socket:bind(config.udp_port, "0.0.0.0")

	print(("Sub Rosa Discord link server on udp/%d"):format(config.udp_port))

	link_server.heartbeat()
	link_server.heartbeat_timer = timer.setInterval(HEARTBEAT_MS, link_server.heartbeat)
	link_server.remove_expired_timer = timer.setInterval(REMOVE_EXPIRED_MS, link_server.remove_expired)

	process:on("sigint", link_server.stop)
	process:on("sigterm", link_server.stop)
end

function link_server.stop()
	print("stopping")
	timer.clearInterval(link_server.heartbeat_timer)
	timer.clearInterval(link_server.remove_expired_timer)
	link_server.socket:close()
	process:exit(0)
end

return link_server
