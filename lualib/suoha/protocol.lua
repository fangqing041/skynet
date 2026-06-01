local protobuf = require "suoha.protobuf"

local protocol = {}

protocol.HEAD_LENGTH = 5
protocol.TAG_ZIP = 1

protocol.OPCODE = {
	LOGIN_C_LOGIN = 1,
	LOGIN_S_LOGIN = 2,
	LOGIN_C_CREATE_ROLE = 3,
	LOGIN_S_CREATE_ROLE = 4,
	LOGIN_C_REGISTER = 5,
	LOGIN_S_REGISTER = 6,
	LOGIN_C_PING = 7,
	LOGIN_S_PONG = 8,
	LOGIN_C_RECONNECT = 9,
	LOGIN_S_RECONNECT = 10,
	LOGIN_C_UPDATE_LANG = 13,
	LOGIN_S_UPDATE_LANG = 14,
	LOGIN_C_CREATE_NAME = 15,
	LOGIN_S_CREATE_NAME = 16,
	USER_S_LOGOUT = 100,
}

protocol.ERROR = {
	Ok = 0,
	ServerError = 1,
	RequestParamError = 2,
	OperationInvalid = 5,
	AccountOrPasswordError = 15,
	AccountAlreadyExists = 16,
	AccountNotRegister = 17,
	LoginPasswordError = 18,
	PlayerLoginIng = 32,
	AccountLoginOtherDevice = 33,
	ReconnectSignError = 34,
	PlayerTokenExpired = 37,
}

local SCHEMA = {}

SCHEMA.LOGIN_C_REGISTER = {
	[1] = { name = "account", type = "string" },
	[2] = { name = "password", type = "string" },
}

SCHEMA.LOGIN_C_LOGIN = {
	[1] = { name = "account", type = "string" },
	[2] = { name = "password", type = "string" },
	[3] = { name = "is_token", type = "bool" },
	[4] = { name = "version", type = "string" },
	[5] = { name = "lang", type = "string" },
	[6] = { name = "network", type = "string" },
	[7] = { name = "device_id", type = "string" },
}

SCHEMA.LOGIN_C_RECONNECT = {
	[1] = { name = "id", type = "int64" },
	[2] = { name = "sig", type = "string" },
	[3] = { name = "account", type = "string" },
	[4] = { name = "network", type = "string" },
}

SCHEMA.ENTER = {
	[1] = { name = "id", type = "int64" },
	[2] = { name = "name", type = "string" },
	[5] = { name = "gold", type = "int32" },
	[7] = { name = "diamond", type = "int32" },
	[9] = { name = "level", type = "int32" },
	[10] = { name = "exp", type = "int64" },
	[11] = { name = "physical", type = "int32" },
	[18] = { name = "utc", type = "int64" },
	[24] = { name = "sig", type = "string" },
}

SCHEMA.LOGIN_S_LOGIN = {
	[1] = { name = "is_new", type = "bool" },
	[2] = { name = "enter", type = "message", schema = SCHEMA.ENTER },
}

SCHEMA.LOGIN_S_RECONNECT = {
	[1] = { name = "enter", type = "message", schema = SCHEMA.ENTER },
}

SCHEMA.LOGIN_S_PONG = {
	[1] = { name = "utc", type = "int64" },
}

SCHEMA.USER_S_LOGOUT = {
	[1] = { name = "logout_type", type = "int32" },
}

protocol.SCHEMA = SCHEMA

function protocol.decode_request(msg_id, body)
	if msg_id == protocol.OPCODE.LOGIN_C_LOGIN then
		return protobuf.decode(SCHEMA.LOGIN_C_LOGIN, body)
	elseif msg_id == protocol.OPCODE.LOGIN_C_REGISTER then
		return protobuf.decode(SCHEMA.LOGIN_C_REGISTER, body)
	elseif msg_id == protocol.OPCODE.LOGIN_C_RECONNECT then
		return protobuf.decode(SCHEMA.LOGIN_C_RECONNECT, body)
	end
	return {}
end

function protocol.encode_message(name, obj)
	return protobuf.encode(SCHEMA[name], obj or {})
end

function protocol.read_frame(read_exact)
	local head = read_exact(2)
	if not head then
		return nil
	end
	local total_len = string.unpack(">I2", head)
	if total_len < protocol.HEAD_LENGTH then
		error("invalid frame length " .. tostring(total_len))
	end
	local rest = read_exact(total_len - 2)
	if not rest then
		return nil
	end
	local tag, msg_id = string.unpack(">BI2", rest)
	return {
		length = total_len,
		tag = tag,
		msg_id = msg_id,
		body = rest:sub(4),
	}
end

function protocol.pack_frame(msg_id, body, err_code)
	body = body or ""
	err_code = err_code or protocol.ERROR.Ok
	local payload = string.pack(">I2", err_code) .. body
	local total_len = protocol.HEAD_LENGTH + #payload
	return string.pack(">I2BI2", total_len, 0, msg_id) .. payload
end

function protocol.pack_error(msg_id, err_code)
	return protocol.pack_frame(msg_id, "", err_code)
end

return protocol
