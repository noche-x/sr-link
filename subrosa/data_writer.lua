local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local data_writer = {}
data_writer.__index = data_writer

---@return table writer
function data_writer.new()
	return setmetatable({ out = {}, bit_pos = 0 }, data_writer)
end

---@param value number
---@param count number how many bits to write
function data_writer:bits(value, count)
	local out = self.out
	for i = 0, count - 1 do
		if self.bit_pos == 0 then
			out[#out + 1] = 0
		end

		local bit_value = band(rshift(value, i), 1)

		out[#out] = bor(out[#out], lshift(bit_value, self.bit_pos))

		self.bit_pos = (self.bit_pos + 1) % 8
	end
end

---@param s string bytes to write
function data_writer:bytes(s)
	self.bit_pos = 0
	for i = 1, #s do
		self.out[#self.out + 1] = s:byte(i)
	end
end

---@param value number
---@param size number size in bytes
function data_writer:unsigned(value, size)
	local bytes = {}
	for i = 1, size do
		bytes[i] = string.char(value % 256)
		value = math.floor(value / 256)
	end

	self:bytes(table.concat(bytes))
end

---@param value number
function data_writer:uint8(value)
	self:unsigned(value, 1)
end

---@param value number
function data_writer:uint16(value)
	self:unsigned(value, 2)
end

---@param value number
function data_writer:uint32(value)
	self:unsigned(value, 4)
end

---@param s string decimal digits, since a SteamID64 does not fit in a Lua number
function data_writer:uint64(s)
	local value = 0
	for digit in s:gmatch("%d") do
		value = value * 10 + tonumber(digit)
	end
	-- low 32
	self:uint32(tonumber(value % 2 ^ 32))
	-- high 32
	self:uint32(tonumber(value / 2 ^ 32))
end

---@param address string dotted IPv4, stored as a uint32
function data_writer:ipv4(address)
	local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	assert(a, "not an IPv4 address: " .. address)
	self:uint32(((tonumber(a) * 256 + tonumber(b)) * 256 + tonumber(c)) * 256 + tonumber(d))
end

---@param s string
---@param length number size of the field in bytes
function data_writer:string(s, length)
	s = s:sub(1, length)
	self:bytes(s .. ("\0"):rep(length - #s))
end

---@return string bytes
function data_writer:data()
	return string.char(unpack(self.out))
end

return data_writer
