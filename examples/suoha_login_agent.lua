local skynet = require "skynet"
local socket = require "skynet.socket"
local protocol = require "suoha.protocol"

local store, fd, addr = ...
store = tonumber(store)
fd = tonumber(fd)

local OPCODE = protocol.OPCODE
local ERROR = protocol.ERROR

local account
local closed = false

local function read_exact(size)
	local data = socket.read(fd, size)
	if data == false or data == nil or #data ~= size then
		return nil
	end
	return data
end

local function send(msg_id, body, err_code)
	if not closed then
		socket.write(fd, protocol.pack_frame(msg_id, body, err_code))
	end
end

local function send_error(msg_id, err_code)
	if not closed then
		socket.write(fd, protocol.pack_error(msg_id, err_code))
	end
end

local function enter_from_account(a)
	return {
		id = a.player_id,
		name = a.name or a.account,
		gold = a.gold or 0,
		diamond = a.diamond or 0,
		level = a.level or 1,
		exp = a.exp or 0,
		physical = a.physical or 0,
		utc = math.floor(skynet.time() * 1000),
		sig = a.reconnect_sign or "",
	}
end

local function kick_repeat_login()
	local body = protocol.encode_message("USER_S_LOGOUT", { logout_type = 1 })
	send(OPCODE.USER_S_LOGOUT, body)
	socket.close(fd)
	closed = true
end

local function notify_old_session(old)
	if old and old.agent and old.agent ~= skynet.self() then
		skynet.send(old.agent, "lua", "repeat_logout")
	end
end

local function handle_register(body)
	local req = protocol.decode_request(OPCODE.LOGIN_C_REGISTER, body)
	local a, err = skynet.call(store, "lua", "register", req.account, req.password)
	if not a then
		if err == "exists" then
			send_error(OPCODE.LOGIN_S_REGISTER, ERROR.AccountAlreadyExists)
		else
			send_error(OPCODE.LOGIN_S_REGISTER, ERROR.AccountOrPasswordError)
		end
		return
	end
	send(OPCODE.LOGIN_S_REGISTER)
end

local function handle_login(body)
	if account then
		send_error(OPCODE.LOGIN_S_LOGIN, ERROR.OperationInvalid)
		return
	end
	local req = protocol.decode_request(OPCODE.LOGIN_C_LOGIN, body)
	if not req.account or req.account == "" or not req.password or req.password == "" then
		send_error(OPCODE.LOGIN_S_LOGIN, ERROR.AccountOrPasswordError)
		return
	end
	local a, err, old = skynet.call(store, "lua", "login", req.account, req.password, req.is_token,
		skynet.self(), fd, req.lang, req.network, req.device_id)
	if not a then
		if err == "not_register" then
			send_error(OPCODE.LOGIN_S_LOGIN, ERROR.AccountNotRegister)
		elseif err == "token_error" then
			send_error(OPCODE.LOGIN_S_LOGIN, ERROR.PlayerTokenExpired)
		else
			send_error(OPCODE.LOGIN_S_LOGIN, ERROR.LoginPasswordError)
		end
		return
	end
	account = a.account
	notify_old_session(old)
	local resp = protocol.encode_message("LOGIN_S_LOGIN", {
		is_new = not a.role_created,
		enter = a.role_created and enter_from_account(a) or nil,
	})
	send(OPCODE.LOGIN_S_LOGIN, resp)
	skynet.error(string.format("login ok account=%s playerId=%d fd=%d addr=%s", a.account, a.player_id, fd, addr))
end

local function handle_reconnect(body)
	if account then
		send_error(OPCODE.LOGIN_S_RECONNECT, ERROR.OperationInvalid)
		return
	end
	local req = protocol.decode_request(OPCODE.LOGIN_C_RECONNECT, body)
	if not req.account or req.account == "" or not req.sig or req.sig == "" or not req.id or req.id <= 0 then
		send_error(OPCODE.LOGIN_S_RECONNECT, ERROR.RequestParamError)
		return
	end
	local a, err, old = skynet.call(store, "lua", "reconnect", req.account, req.id, req.sig,
		skynet.self(), fd, req.network)
	if not a then
		if err == "not_register" then
			send_error(OPCODE.LOGIN_S_RECONNECT, ERROR.AccountNotRegister)
		else
			send_error(OPCODE.LOGIN_S_RECONNECT, ERROR.ReconnectSignError)
		end
		return
	end
	account = a.account
	notify_old_session(old)
	local resp = protocol.encode_message("LOGIN_S_RECONNECT", { enter = enter_from_account(a) })
	send(OPCODE.LOGIN_S_RECONNECT, resp)
end

local function handle_ping()
	local body = protocol.encode_message("LOGIN_S_PONG", { utc = math.floor(skynet.time() * 1000) })
	send(OPCODE.LOGIN_S_PONG, body)
end

local function serve()
	socket.start(fd)
	while not closed do
		local ok, frame = pcall(protocol.read_frame, read_exact)
		if not ok then
			skynet.error(string.format("close invalid frame fd=%d err=%s", fd, frame))
			break
		end
		if not frame then
			break
		end
		if (frame.tag & protocol.TAG_ZIP) ~= 0 then
			send_error(frame.msg_id + 1, ERROR.RequestParamError)
		elseif frame.msg_id == OPCODE.LOGIN_C_REGISTER then
			handle_register(frame.body)
		elseif frame.msg_id == OPCODE.LOGIN_C_LOGIN then
			handle_login(frame.body)
		elseif frame.msg_id == OPCODE.LOGIN_C_RECONNECT then
			handle_reconnect(frame.body)
		elseif frame.msg_id == OPCODE.LOGIN_C_PING then
			handle_ping()
		else
			send_error(frame.msg_id + 1, account and ERROR.OperationInvalid or ERROR.OperationInvalid)
		end
	end
	if account then
		skynet.call(store, "lua", "logout", account, skynet.self())
	end
	if not closed then
		socket.close(fd)
		closed = true
	end
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, cmd)
		if cmd == "repeat_logout" then
			kick_repeat_login()
		end
	end)
	skynet.timeout(1, serve)
end)
