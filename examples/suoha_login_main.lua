local skynet = require "skynet"
local socket = require "skynet.socket"

local host = skynet.getenv("login_host") or "0.0.0.0"
local port = tonumber(skynet.getenv("login_port") or 8888)
local debug_port = tonumber(skynet.getenv("debug_port") or 8000)

skynet.start(function()
	skynet.newservice("debug_console", debug_port)
	local store = skynet.uniqueservice("suoha_account_store")
	local listen_fd = socket.listen(host, port)
	skynet.error(string.format("Suoha protobuf login server listen on %s:%d", host, port))
	socket.start(listen_fd, function(fd, addr)
		skynet.error(string.format("new login connection fd=%d addr=%s", fd, addr))
		local ok, err = pcall(skynet.newservice, "suoha_login_agent", store, fd, addr)
		if not ok then
			skynet.error(string.format("start login agent failed fd=%d addr=%s err=%s", fd, addr, err))
			socket.close(fd)
		end
	end)
end)
