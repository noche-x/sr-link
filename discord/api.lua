local api = {}

local json = require("json")
local querystring = require("querystring")
local http = require("coro-http")

local config = require("../config")


local BASE_URL = "https://discord.com/api/v10"
local USER_AGENT = { "User-Agent", "sr-link-discord" }


---@param method string
---@param path string route after /api/v10, e.g. "/users/@me"
---@param authorization string "Bot <token>" or "Bearer <access token>"
---@param body table|nil sent as json
---@return table|nil answer decoded json, nil when Discord sent no body
function api.request(method, path, authorization, body)
	local headers = { USER_AGENT, { "Authorization", authorization } }
	if body then
		headers[#headers + 1] = { "Content-Type", "application/json" }
		body = json.encode(body)
	end

	local response, answer = http.request(method, BASE_URL .. path, headers, body)
	if response.code < 200 or response.code > 299 then
		error(("Discord %s %s answered %d"):format(method, path, response.code))
	end

	if answer == "" then
		return nil
	end

	return json.decode(answer)
end

---@param grant table grant_type and its fields, our client id and secret get added
---@return table|nil tokens { access_token, refresh_token, expires_in }
---@return string|nil error "invalid_grant" when Discord rejected the code or refresh token
function api.request_tokens(grant)
	grant.client_id = config.discord_application_id
	grant.client_secret = config.discord_client_secret

	local response, answer = http.request(
		"POST",
		BASE_URL .. "/oauth2/token",
		{ USER_AGENT, { "Content-Type", "application/x-www-form-urlencoded" } },
		querystring.stringify(grant)
	)
	if response.code == 400 and json.decode(answer).error == "invalid_grant" then
		return nil, "invalid_grant"
	end

	if response.code ~= 200 then
		error(("Discord token request answered %d"):format(response.code))
	end

	return json.decode(answer)
end

return api
