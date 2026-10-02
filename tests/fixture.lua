-- tests/fixture.lua
-- Spawns throw-away Neovim instances for tests/run-tests.ps1 and keeps them alive until a stop
-- file appears. Run as:  nvim --headless -l tests/fixture.lua <pids-out-file> <stop-file>
--
-- "gui1"/"gui2" are "nvim --embed" cores with a UI attached over RPC, exactly what a GUI such as
-- Neovide runs (no --headless on the command line, owns \\.\pipe\nvim.<pid>.0). They stand in for
-- a person's editor. A TUI behind a bare pty was tried first: its embedded core never became
-- responsive (the UI attach never completed), which a real terminal does not show.
-- The two headless ones must be ignored by the discovery.
-- Only processes started here are ever stopped (by job id), never by image name.

-- luacheck: globals vim
---@diagnostic disable: undefined-global

local out, stop = arg[1], arg[2]
assert(out and stop, "usage: fixture.lua <pids-out-file> <stop-file>")

local nvim = vim.v.progpath
local jobs, lines = {}, {}

local function spawn(label, args, attach_ui)
	local cmd = { nvim }
	vim.list_extend(cmd, args)
	local id = vim.fn.jobstart(cmd, { rpc = attach_ui or false })
	assert(id > 0, "jobstart failed for " .. label)
	jobs[#jobs + 1] = id
	lines[#lines + 1] = label .. "=" .. vim.fn.jobpid(id)
	if attach_ui then
		-- An --embed instance finishes its startup only once a UI has attached.
		vim.rpcrequest(id, "nvim_ui_attach", 80, 24, {})
	end
	vim.wait(1500) -- distinct start times, and give each one time to open its pipe
end

spawn("gui1", { "--clean", "--embed" }, true)
spawn("gui2", { "--clean", "--embed" }, true)
spawn("headless", { "--clean", "--headless" })
spawn("embedhl", { "--clean", "--embed", "--headless", "-n", "-u", "NONE" })

vim.fn.writefile(lines, out)

while vim.fn.filereadable(stop) == 0 do
	vim.wait(200)
end
for _, id in ipairs(jobs) do
	pcall(vim.fn.jobstop, id)
end
vim.wait(500)
