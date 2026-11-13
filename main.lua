-- run with: luvit main.lua
-- you need to do luvit main.lua register once to register the Discord commands and Linked Roles metadata with Discord before starting the server
if args[2] == "register" then
	require("./discord/register")()
	return
end

require("./discord/web").start()
require("./subrosa/link_server").start()
