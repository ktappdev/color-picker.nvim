---@diagnostic disable: undefined-global

local M = {}
local api = vim.api

local function detect_colors(str)
	local hex_pattern = "#%x%x%x%x%x%x"
	local rgb_pattern = "rgb%(%s*%d+%s*,%s*%d+%s*,%s*%d+%s*%)"
	local hsl_pattern = "hsl%(%s*%d+%s*,%s*%d+%s*,%s*%d+%s*%)"

	local results = {}
	local patterns = { hex_pattern, rgb_pattern, hsl_pattern }

	for _, pattern in ipairs(patterns) do
		local start_index = 1
		while true do
			local _start, _end = string.find(str, pattern, start_index)
			local _match = string.match(str, pattern, start_index)

			if _start == nil then
				break
			end

			table.insert(results, { _start, _end, _match })
			start_index = _end + 1
		end
	end

  return results
end

local function get_current_line()
	local cur_line = api.nvim_get_current_line()
	local cur_line_num = api.nvim_win_get_cursor(0)[1]
	return cur_line, cur_line_num
end

-- color: #121221, #122233
-- color: #f4f4f4
-- color: rgb(0,0,0)
-- color: rgb( 0, 0, 0)
-- color: rgb( 0  , 0 , 0)
-- color: hsl( 0  , 0 , 0)

--> replacing color under cursor with random text

local function sandwich()
  local cur_line = api.nvim_get_current_line()
  local cur_pos = api.nvim_win_get_cursor(0)
  local cur_pos_col = cur_pos[2]

  local colorRanges = detect_colors(cur_line)

  for _, color in ipairs(colorRanges) do
    local start_pos = color[1]
    local end_pos = color[2]

    if start_pos <= cur_pos_col and end_pos >= cur_pos_col then
      P(color[3])
    end
  end
end

vim.keymap.set("n", "<C-A-K>", function()
	vim.cmd("messages clear")
  sandwich()
end, { noremap = true, silent = true })

-- for quickly reload file
vim.keymap.set("n", "<A-r>", ":luafile %<cr>", { noremap = true, silent = false })

return M
