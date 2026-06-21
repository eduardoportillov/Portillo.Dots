-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local vertical_divider_resize_step = 15
local horizontal_divider_resize_step = 5

local function set_width_delta(win, delta)
  local min_width = vim.o.winminwidth
  local width = vim.api.nvim_win_get_width(win)

  pcall(vim.api.nvim_win_set_width, win, math.max(min_width, width + delta))
end

local function set_height_delta(win, delta)
  local min_height = vim.o.winminheight
  local height = vim.api.nvim_win_get_height(win)

  pcall(vim.api.nvim_win_set_height, win, math.max(min_height, height + delta))
end

local function range_overlap(first_start, first_end, second_start, second_end)
  return first_start <= second_end and second_start <= first_end
end

local function overlap_size(first_start, first_end, second_start, second_end)
  return math.min(first_end, second_end) - math.max(first_start, second_start) + 1
end

local function win_geometry(win)
  local position = vim.fn.win_screenpos(win)
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)

  return {
    win = win,
    top = position[1],
    left = position[2],
    bottom = position[1] + height - 1,
    right = position[2] + width - 1,
  }
end

local function adjacent_win(direction)
  local current_win = vim.api.nvim_get_current_win()
  local current = win_geometry(current_win)
  local best_win = nil
  local best_distance = math.huge
  local best_overlap = 0

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= current_win and vim.api.nvim_win_get_config(win).relative == "" then
      local candidate = win_geometry(win)
      local distance = nil
      local overlap = 0

      if direction == "left" and candidate.right < current.left then
        if range_overlap(candidate.top, candidate.bottom, current.top, current.bottom) then
          distance = current.left - candidate.right
          overlap = overlap_size(candidate.top, candidate.bottom, current.top, current.bottom)
        end
      elseif direction == "right" and candidate.left > current.right then
        if range_overlap(candidate.top, candidate.bottom, current.top, current.bottom) then
          distance = candidate.left - current.right
          overlap = overlap_size(candidate.top, candidate.bottom, current.top, current.bottom)
        end
      elseif direction == "up" and candidate.bottom < current.top then
        if range_overlap(candidate.left, candidate.right, current.left, current.right) then
          distance = current.top - candidate.bottom
          overlap = overlap_size(candidate.left, candidate.right, current.left, current.right)
        end
      elseif direction == "down" and candidate.top > current.bottom then
        if range_overlap(candidate.left, candidate.right, current.left, current.right) then
          distance = candidate.top - current.bottom
          overlap = overlap_size(candidate.left, candidate.right, current.left, current.right)
        end
      end

      if distance and (distance < best_distance or (distance == best_distance and overlap > best_overlap)) then
        best_win = win
        best_distance = distance
        best_overlap = overlap
      end
    end
  end

  return best_win
end

local function move_vertical_divider(direction)
  local current = vim.api.nvim_get_current_win()
  local left = adjacent_win("left")
  local right = adjacent_win("right")

  if direction == "right" then
    local left_side = right and current or left

    if left_side then
      set_width_delta(left_side, vertical_divider_resize_step)
    end
  else
    local left_side = left or (right and current)

    if left_side then
      set_width_delta(left_side, -vertical_divider_resize_step)
    end
  end
end

local function move_horizontal_divider(direction)
  local current = vim.api.nvim_get_current_win()
  local up = adjacent_win("up")
  local down = adjacent_win("down")

  if direction == "down" then
    local top_side = down and current or up

    if top_side then
      set_height_delta(top_side, horizontal_divider_resize_step)
    end
  else
    local top_side = up or (down and current)

    if top_side then
      set_height_delta(top_side, -horizontal_divider_resize_step)
    end
  end
end

-- Move physical split dividers, not the logical size of the focused window.
-- Neighbor detection is geometry-based so it scales to any number of splits and
-- avoids Neovim's focus-relative resize inversion. For edge windows, the nearest
-- inward divider is still moved in the requested physical direction.
vim.keymap.set("n", "<C-w>>", function()
  move_vertical_divider("right")
end, { desc = "Move vertical divider right" })

vim.keymap.set("n", "<C-w><lt>", function()
  move_vertical_divider("left")
end, { desc = "Move vertical divider left" })

vim.keymap.set("n", "<C-w>+", function()
  move_horizontal_divider("down")
end, { desc = "Move horizontal divider down" })

vim.keymap.set("n", "<C-w>-", function()
  move_horizontal_divider("up")
end, { desc = "Move horizontal divider up" })

-- Equalizes regular editable splits in the current layout. Fixed sidebars such as
-- Explorer/Neo-tree can keep their configured width, so they may not become equal.
vim.keymap.set("n", "<C-w>=", "<C-w>=", { desc = "Equally high and wide" })
