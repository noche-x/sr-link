local data_reader = require("./data_reader")
local data_writer = require("./data_writer")

local MAGIC = "7DFP"

local packets = {
	auth = require("./packets/auth"),
	connect_response = require("./packets/connect_response"),
	info_request = require("./packets/info_request"),
	join_request = require("./packets/join_request"),
	master_ping = require("./packets/master_ping"),
	server_info = require("./packets/server_info"),
}

local packet_types = {}
for _, packet in pairs(packets) do
	packet_types[packet.type] = packet
end

---@param data string recieved data
---@return table|nil packet the packet module, nil for anything that is not a known 7DFP packet
---@return table|nil fields the decoded body
function packets.read_packet(data)
	if #data < 5 or data:sub(1, 4) ~= MAGIC then
		return nil
	end

	local packet = packet_types[data:byte(5)]
	if not packet then
		return nil
	end

	return packet, packet.read(data_reader.new(data:sub(6)))
end

---@param packet table packet module from packets/
---@param data table|nil fields for packet.write
---@return string data
function packets.write_packet(packet, data)
	local writer = data_writer.new()
	writer:uint8(packet.type)
	packet.write(writer, data or {})
	return MAGIC .. writer:data()
end

return packets
