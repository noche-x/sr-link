local config = require("../config")
local api = require("./api")


-- installed on the user's account, usable in servers, the bot dm and private channels
local USER_INSTALL = { 1 }
local EVERYWHERE = { 0, 1, 2 }


return function()
	if not config.discord_bot_token then
		error("DISCORD_BOT_TOKEN is needed to register commands")
	end

	local authorization = "Bot " .. config.discord_bot_token
	local app = config.discord_application_id

	api.request("PUT", ("/applications/%s/commands"):format(app), authorization, {
		{
			type = 1,
			name = "link",
			description = "Link your Sub Rosa account",
			integration_types = USER_INSTALL,
			contexts = EVERYWHERE,
		},
		-- app launcher button, handler 1 sends the click to us instead of an activity
		{
			type = 4,
			handler = 1,
			name = "launch",
			description = "Link your Sub Rosa account",
			integration_types = USER_INSTALL,
			contexts = EVERYWHERE,
		},
		-- right click a user, Apps, Sub Rosa Link
		{
			type = 2,
			name = "Sub Rosa Link",
			integration_types = USER_INSTALL,
			contexts = EVERYWHERE,
		},
	})
	print("registered commands")

	api.request("PUT", ("/applications/%s/role-connections/metadata"):format(app), authorization, {
		-- boolean equal, a role can require linked == true
		{
			type = 7,
			key = "linked",
			name = "Sub Rosa account linked",
			description = "Has linked a Sub Rosa account",
		},
	})
	print("registered Linked Roles metadata")
end
