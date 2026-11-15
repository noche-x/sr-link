local web = {}

local fs = require("fs")
local json = require("json")
local path = require("path")
local openssl = require("openssl")
local url = require("url")
local querystring = require("querystring")
local http = require("coro-http")

local config = require("../config")
local interactions = require("./interactions")
local linked_roles = require("./linked_roles")


local STATE_COOKIE = "srlink_state"


---@param status number HTTP status
---@param content_type string
---@param body string
---@param headers table|nil more { name, value } headers
---@return table head
---@return string body
function web.respond(status, content_type, body, headers)
	local head = { code = status, { "Content-Type", content_type }, { "Content-Length", tostring(#body) } }
	for _, header in ipairs(headers or {}) do
		head[#head + 1] = header
	end

	return head, body
end

---@param status number HTTP status
---@param value table
---@return table head
---@return string body
function web.respond_json(status, value)
	return web.respond(status, "application/json", json.encode(value))
end

---@param text string
---@return string html
function web.escape_html(text)
	return (text:gsub("[&<>\"]", { ["&"] = "&#38;", ["<"] = "&#60;", [">"] = "&#62;", ['"'] = "&#34;" }))
end

---@param name string html file next to this one
---@param values table name -> text for each {{name}} in the file
---@return string html
function web.render(name, values)
	local escaped = {}
	for key, value in pairs(values) do
		escaped[key] = web.escape_html(value)
	end

	local html = fs.readFileSync(path.join(module.dir, name)):gsub("{{([%w_]+)}}", escaped)
	local unknown = html:match("{{([%w_]+)}}")
	if unknown then
		error(("%s uses unknown value %s"):format(name, unknown))
	end

	return html
end

---@param status number HTTP status
---@param title string
---@param message string
---@param headers table|nil
---@return table head
---@return string body
function web.respond_page(status, title, message, headers)
	local html = web.render("page.html", { title = title, message = message })
	return web.respond(status, "text/html; charset=utf-8", html, headers)
end

---@param head table request head, headers are { name, value } pairs
---@param name string
---@return string|nil value
function web.find_header(head, name)
	name = name:lower()
	local value
	for _, header in ipairs(head) do
		if header[1]:lower() == name then
			if value then
				error("duplicate request header " .. name)
			end
			value = header[2]
		end
	end

	return value
end

---@param head table
---@return string|nil state the state cookie, nil when it's missing or sent twice
function web.find_state_cookie(head)
	local state
	for cookie in (web.find_header(head, "Cookie") or ""):gmatch("[^;]+") do
		local name, value = cookie:match("^%s*([^=]+)=(.-)%s*$")
		if name == STATE_COOKIE then
			if state then
				return nil
			end
			state = value
		end
	end

	return state
end

function web.on_home()
	local html = web.render("home.html", {
		install_url = "https://discord.com/oauth2/authorize?" .. querystring.stringify({
			client_id = config.discord_application_id,
			integration_type = "1",
			redirect_uri = config.public_url .. "/install/callback",
			response_type = "code",
			scope = "applications.commands",
		}),
		server_name = config.server_name,
	})
	return web.respond(200, "text/html; charset=utf-8", html)
end

function web.on_install_callback(head, body, query)
	if query.error or type(query.code) ~= "string" or query.code == "" then
		return web.respond_page(400, "Installation not completed", "Return to the home page and try again.")
	end

	local html = web.render("installed.html", { server_name = config.server_name })
	return web.respond(200, "text/html; charset=utf-8", html, { { "Referrer-Policy", "no-referrer" } })
end

function web.on_icon()
	return web.respond(200, "image/png", fs.readFileSync(path.join(module.dir, "icon.png")))
end

---@param head table
---@param body string
function web.on_interaction(head, body)
	local signature = web.find_header(head, "X-Signature-Ed25519")
	local timestamp = web.find_header(head, "X-Signature-Timestamp")
	if not interactions.is_signed(signature, timestamp, body) then
		return web.respond(401, "text/plain", "invalid request signature")
	end

	-- bad json decodes to nil, which handle errors on
	local ok, response = pcall(interactions.handle, json.decode(body))
	if not ok then
		print("interaction failed: " .. tostring(response))
		response = interactions.error_response()
	end

	return web.respond_json(200, response)
end

function web.on_linked_role()
	local state = openssl.hex(openssl.random(16))
	return web.respond(302, "text/plain", "", {
		{ "Location", linked_roles.sign_in_url(state) },
		{ "Set-Cookie", ("%s=%s; Path=/oauth; Max-Age=600; HttpOnly; Secure; SameSite=Lax"):format(STATE_COOKIE, state) },
	})
end

---@param head table
---@param body string
---@param query table
function web.on_sign_in_callback(head, body, query)
	local state = web.find_state_cookie(head)
	if not state or not state:match("^" .. ("%x"):rep(32) .. "$") or state ~= query.state
		or type(query.code) ~= "string" or query.code == "" then
		return web.respond_page(400, "Link expired", "Open the role from the Linked Roles menu again.")
	end

	local headers = { { "Set-Cookie", STATE_COOKIE .. "=; Path=/oauth; Max-Age=0; HttpOnly; Secure; SameSite=Lax" } }

	local ok, user, linked = pcall(linked_roles.finish_sign_in, query.code)
	if not ok then
		print("Linked Roles sign-in failed: " .. tostring(user))
		return web.respond_page(500, "Something went wrong", "Try again from the Linked Roles menu.", headers)
	end

	if not linked then
		return web.respond_page(
			200,
			"Not linked yet",
			"Run /link anywhere in Discord, or right-click your profile image and choose Apps → SR Link → Sub Rosa Link. "
				.. "Generate a code and join the link server with it. "
				.. "Your roles update by themselves once you are linked.",
			headers
		)
	end

	return web.respond_page(
		200,
		"Verified",
		("%s, your Sub Rosa account is linked. Discord will give you the role."):format(user.username),
		headers
	)
end

web.routes = {
	["GET /"] = web.on_home,
	["GET /icon.png"] = web.on_icon,
	["GET /install/callback"] = web.on_install_callback,
	["POST /interactions"] = web.on_interaction,
	["GET /linked-role"] = web.on_linked_role,
	["GET /oauth/callback"] = web.on_sign_in_callback,
}

---@param head table
---@param body string
---@return table head
---@return string body
function web.on_request(head, body)
	local request_url = url.parse(head.path, true)
	local route = web.routes[head.method .. " " .. request_url.pathname]
	if not route then
		return web.respond(404, "text/plain", "not found")
	end

	-- an error here would drop the connection without an answer
	local ok, response_head, response_body = pcall(route, head, body, request_url.query or {})
	if not ok then
		print(("%s %s failed: %s"):format(head.method, request_url.pathname, tostring(response_head)))
		return web.respond(500, "text/plain", "internal error")
	end

	return response_head, response_body
end

function web.start()
	http.createServer("127.0.0.1", config.http_port, web.on_request)
	print(("HTTP on 127.0.0.1:%d, public at %s"):format(config.http_port, config.public_url))
end

return web
