local M = {}
local api = vim.api

local ui = api.nvim_list_uis()[1]

-- JABS main popup
M.main_win = nil
M.main_buf = nil

-- Buffer preview popup
M.prev_win = nil
M.prev_buf = nil

M.bopen = {}
M.conf = {}
M.win_conf = {}
M.preview_conf = {}

require("split")

function M.setup(c)
	local c = c or {}
	if not c.preview then
		c.preview = {}
	end

	M.win_conf = {
		width = c.width or 50,
		height = c.height or 10,
		style = c.style or "minimal",
		border = c.border or "shadow",
		anchor = "NW",
		relative = c.relative or "win",
	}

	M.preview_conf = {
		width = c.preview.width or 70,
		height = c.preview.height or 30,
		style = c.preview.style or "minimal",
		border = c.preview.border or "double",
		anchor = M.win_conf.anchor,
		relative = c.preview.relative or "win",
		row = 0,
		col = 0,
		-- bufpos={100,10}
	}

	M.conf = {
		position = c.position or "corner",
		preview_position = c.preview_position or "top",
	}

	-- TODO: Convert to a table
	if M.conf.preview_position == "top" then
		M.preview_conf.col = M.win_conf.width / 2 - M.preview_conf.width / 2
		M.preview_conf.row = -M.preview_conf.height - 2
	elseif M.conf.preview_position == "bottom" then
		M.preview_conf.col = M.win_conf.width / 2 - M.preview_conf.width / 2
		M.preview_conf.row = M.win_conf.height
	elseif M.conf.preview_position == "right" then
		M.preview_conf.col = M.win_conf.width
		M.preview_conf.row = M.win_conf.height / 2 - M.preview_conf.height / 2
	elseif M.conf.preview_position == "left" then
		M.preview_conf.col = -M.preview_conf.width
		M.preview_conf.row = M.win_conf.height / 2 - M.preview_conf.height / 2
	end

	M.updatePos()
end

M.bufinfo = {
	["%a"] = { "", "Visual" }, -- current active
	["#a"] = { "", "StatusLine" }, -- alternate buffer
	["a"] = { "", "StatusLine" }, -- active
	["#h"] = { "", "ModeMsg" }, -- alternate hidden
	["h"] = { "﬘", "ModeMsg" }, -- hidden
	["-"] = "",
	["="] = "",
	["+"] = "",
	["R"] = "",
	["F"] = "",
}

M.openOptions = {
	window = "b%s",
	vsplit = "vert sb %s",
	hsplit = "sb %s",
}

function M.updatePos()
	ui = api.nvim_list_uis()[1]

	if M.conf.position == "corner" then
		M.win_conf.col = ui.width - M.win_conf.width
		M.win_conf.row = ui.height - M.win_conf.height
	elseif M.conf.position == "center" then
		M.win_conf.relative = "win"
		M.win_conf.col = (ui.width / 2) - (M.win_conf.width / 2)
		M.win_conf.row = (ui.height / 2) - (M.win_conf.height / 2)
	end
end

-- Open buffer from line
function M.selBufNum(win, opt, count)
	local buf = nil

	-- Check for buffer number
	if count ~= 0 then
		local lines = api.nvim_buf_get_lines(0, 1, -1, true)

		for _, line in pairs(lines) do
			local linebuf = line:split(" ", true)[4]
			if tonumber(linebuf) == count then
				buf = linebuf
				break
			end
		end
		-- Or if it's just an ENTER
	else
		local l = api.nvim_get_current_line()
		-- 4 without icon
		buf = l:split(" ", true)[3]
	end

	M.close()

	if not buf then
		print("Buffer number not found!")
		return
	end

	api.nvim_set_current_win(win)
	vim.cmd(string.format(M.openOptions[opt], buf))
end

-- Preview buffer
function M.previewBuf()
	local l = api.nvim_get_current_line()
	local buf = l:split(" ", true)[3]

	-- Create the buffer for preview window
	M.prev_win = api.nvim_open_win(tonumber(buf), 1, M.preview_conf)
end

-- Close buffer from line
function M.closeBufNum(win)
	local l = api.nvim_get_current_line()
	local buf = l:split(" ", true)[3]

	local current_buf = api.nvim_win_get_buf(win)
	local jabs_buf = api.nvim_get_current_buf()

	if tonumber(buf) ~= current_buf then
		vim.cmd(string.format("bd %s", buf))
		local ln = api.nvim_win_get_cursor(0)[1]
		table.remove(M.bopen, ln - 1)

		M.refresh(jabs_buf)
	else
		api.nvim_notify("JABS: Cannot close current buffer!", 3, {})
	end

	vim.wo.number = false
	vim.wo.relativenumber = false
end

-- Parse ls string
function M.parseLs(buf)
	for i, b in ipairs(M.bopen) do
		local si = 0 -- not empty split count
		local line = "" -- Line to be added to buffer
		local highlight = "" -- Line highlight group
		local linenr = "" -- Buffer line number

		for _, s in ipairs(b:split(" ", true)) do
			if s:len() == 0 then
				goto continue
			end
			si = si + 1
			-- Split with buffer information
			if si == 2 then
				_, highlight = xpcall(function()
					-- print(M.bufinfo[s][2])
					return M.bufinfo[s][2]
				end, function()
					-- print(M.bufinfo[s:sub(1, s:len() - 1)][2])
					return M.bufinfo[s:sub(1, s:len() - 1)][2]
				end)

				local _, symbol = xpcall(function()
					return M.bufinfo[s][1]
				end, function()
					return M.bufinfo[s:sub(s:len(), s:len())]
				end)

				-- Fixes #3
				symbol = symbol or M.bufinfo["h"][1]

				-- line = " " .. symbol .. " " .. line
				line = " " .. symbol .. " " .. line
				-- print(vim.inspect(M.bufinfo[s]))
				-- print(line)
				-- Other non-empty splits (filename, RO, modified, ...)
				-- print(s)
			else
				if s:sub(2, 8) == "term://" then
					line = line .. "Terminal" .. s:gsub("^.*:", ': "')
				else
					if tonumber(s) ~= nil and si > 2 then
						linenr = s
					else
						if s:sub(1, 4) ~= "line" and s ~= "" then
							-- print(s)
							local cwd_path = vim.fn.getcwd() .. "/"
							local bufinfo = string.gsub((M.bufinfo[s] or s), "~", os.getenv("HOME"))
							local name = string.gsub(bufinfo, cwd_path, "")
							-- name = " " .. file_icon .. " " .. name
							line = line .. name .. " "
							-- print(line)
						end
					end
				end
			end
			::continue::
		end

		-- Remove quotes from filename
		line = line:gsub('"', "")

		local chunks = {}
		for substring in line:gmatch("%S+") do
			table.insert(chunks, substring)
		end


		local filename = chunks[3]
		local extension = ""
		extension = filename:match("^.+(%..+)$")
		local default = true
		local hl_group = "FileIconColor"
		if not (extension == nil or extension == " ") then
			extension = extension:gsub("%.", "") -- remove . (. is a special character so we have to escape it)
			hl_group = hl_group .. extension
		else
			if chunks[3] == "Terminal:" then
				hl_group = hl_group .. "term"
        filename = "terminal"
			else
				hl_group = hl_group .. filename:gsub('%W','')
			end
		end


		local file_icon, file_icon_color = require("nvim-web-devicons").get_icon_color(
			filename,
			extension,
			{ default = default }
		)

		vim.api.nvim_set_hl(0, hl_group, { fg = file_icon_color })
		table.insert(chunks, 3, file_icon)
		line = table.concat(chunks, " ")

		-- Truncate line if too long
		local filename_space = M.win_conf.width - linenr:len() - 3
		if line:len() > filename_space then
			line = line:gsub(string.rep("%S", line:len() - filename_space + 3), "...", 1)
		end

		-- Write line
		api.nvim_buf_set_text(buf, i, 1, i, line:len(), { line })
		api.nvim_buf_set_text(buf, i, M.win_conf.width - linenr:len(), i, M.win_conf.width, { " " .. linenr })

		api.nvim_buf_add_highlight(buf, -1, highlight, i, 0, -1)
		api.nvim_buf_add_highlight(buf, -1, hl_group, i, 9, 11)
	end
end

-- Set floating window keymaps
function M.setKeymaps(win, buf)
	-- Basic window buffer configuration
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"<CR>",
		string.format([[:<C-U>lua require'jabs'.selBufNum(%s, 'window', vim.v.count)<CR>]], win),
		{ nowait = true, noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"l",
		string.format([[:<C-U>lua require'jabs'.selBufNum(%s, 'window', vim.v.count)<CR>]], win),
		{ nowait = true, noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"s",
		string.format([[:<C-U>lua require'jabs'.selBufNum(%s, 'hsplit', vim.v.count)<CR>]], win),
		{ nowait = true, noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"v",
		string.format([[:<C-U>lua require'jabs'.selBufNum(%s, 'vsplit', vim.v.count)<CR>]], win),
		{ nowait = true, noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"d",
		string.format([[:lua require'jabs'.closeBufNum(%s)<CR>]], win),
		{ nowait = true, noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"p",
		string.format([[:lua require'jabs'.previewBuf()<CR>]], win),
		{ nowait = true, noremap = true, silent = true }
	)

	-- Navigation keymaps
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"q",
		':lua require"jabs".close()<CR>',
		{ nowait = true, noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(
		buf,
		"n",
		"<Esc>",
		':lua require"jabs".close()<CR>',
		{ nowait = true, noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(buf, "n", "<Tab>", "j", { nowait = true, noremap = true, silent = true })
	api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "k", { nowait = true, noremap = true, silent = true })

	-- Prevent cursor from going to buffer title
	vim.cmd(string.format("au CursorMoved <buffer=%s> if line(\".\") == 1 | call feedkeys('j', 'n') | endif", buf))
end

function M.close()
	-- If JABS is closed using :q the window and buffer indicator variables
	-- are not reset, so we need to take this into account
	xpcall(function()
		api.nvim_win_close(M.main_win, false)
		api.nvim_buf_delete(M.main_buf, {})
		M.main_win = nil
		M.main_buf = nil
	end, function()
		M.main_win = nil
		M.main_buf = nil
		M.open()
	end)
end

function M.refresh(buf)
	local empty = {}
	for _ = 1, #M.bopen + 1 do
		empty[#empty + 1] = string.rep(" ", M.win_conf.width)
	end

	api.nvim_buf_set_option(buf, "modifiable", true)
	api.nvim_buf_set_lines(buf, 0, -1, false, empty)

	M.parseLs(buf)

	-- Draw title
	local title = "Buffers:"
	api.nvim_buf_set_text(buf, 0, 1, 0, title:len() + 1, { title })
	api.nvim_buf_add_highlight(buf, -1, "Folded", 0, 0, -1)

	-- Disable modifiable when done
	api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Floating buffer list
function M.open()
	M.bopen = api.nvim_exec(":ls", true):split("\n", true)
	local back_win = api.nvim_get_current_win()
	-- Create the buffer for the window
	if not M.main_buf and not M.main_win then
		M.updatePos()
		M.main_buf = api.nvim_create_buf(false, true)
		M.main_win = api.nvim_open_win(M.main_buf, 1, M.win_conf)
		M.refresh(M.main_buf)
		M.setKeymaps(back_win, M.main_buf)
	else
		M.close()
	end
end

return M

