-- server -> client: server list entry, answer to info_request.
local packet = {}
packet.type = 1
packet.name = "server_info"

---@param reader table data_reader over the body
---@return table fields
function packet.read(reader)
	local data = {}
	data.build = reader:bits(8)
	data.timestamp = reader:uint32()
	data.gamemode = reader:bits(4)
	data.current_players = reader:bits(8)
	data.max_players = reader:bits(8)
	reader:bits(4)
	data.name = reader:string(32)
	data.id = reader:uint32()
	data.address = reader:ipv4()
	data.port = reader:uint16()
	data.password_protected = reader:bits(1) == 1
	data.sub_version = reader:bits(8)
	reader:bits(8)
	return data
end

---@param writer table data_writer
---@param data table fields
function packet.write(writer, data)
	writer:uint8(data.build)
	writer:uint32(data.timestamp)
	writer:bits(data.gamemode, 4)
	writer:bits(data.current_players, 8)
	writer:bits(data.max_players, 8)
	writer:bits(9, 4)
	writer:string(data.name, 32)
	writer:uint32(data.id)
	-- 0.0.0.0 until the master server has told us our public address
	writer:ipv4(data.address or "0.0.0.0")
	writer:uint16(data.port)
	writer:bits(data.password_protected and 1 or 0, 1)
	writer:bits(data.sub_version, 8)
	writer:bits(71, 8)
end

return packet
