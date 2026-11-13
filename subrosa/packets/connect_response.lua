-- server -> client: connection response for refusing the join.
-- reason is capped at 63 characters because the length is stored in 6 bits, 2^6 - 1 = 63.
local packet = {}
packet.type = 3
packet.name = "connect_response"

---@param reader table data_reader over the body
---@return table fields
function packet.read(reader)
	local length = reader:bits(6)
	return { reason = reader:bytes(length) }
end

---@param writer table data_writer
---@param data table fields
function packet.write(writer, data)
	local reason = data.reason:sub(1, 63)
	writer:bits(#reason, 6)
	writer:bytes(reason)
end

return packet
