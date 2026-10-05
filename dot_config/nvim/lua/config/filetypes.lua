local group = vim.api.nvim_create_augroup("notes_filetypes", { clear = true })

-- Wrap the current charwise visual selection in <tag>…</tag>.
local function wrap_visual(tag)
  local open, close = "<" .. tag .. ">", "</" .. tag .. ">"
  local save_reg, save_type = vim.fn.getreg("z"), vim.fn.getregtype("z")
  vim.cmd('noautocmd normal! "zy')
  vim.fn.setreg("z", open .. vim.fn.getreg("z") .. close, "v")
  vim.cmd('noautocmd normal! gv"zp')
  vim.fn.setreg("z", save_reg, save_type)
end

-- Follow the markdown link under / nearest the cursor: a URL opens in the
-- browser (vim.ui.open), a relative path opens as a file (relative to the
-- current note). Falls back to <cfile> under the cursor.
local function follow_link()
  local line = vim.api.nvim_get_current_line()
  local cur = vim.fn.col(".")
  local target
  local from = 1
  while true do
    local _, e, link = line:find("%]%(([^)]+)%)", from)
    if not link then
      break
    end
    if cur <= e then
      target = link
      break
    end
    target = link -- remember last link seen before the cursor
    from = e + 1
  end
  target = target or vim.fn.expand("<cfile>")
  if not target or target == "" then
    vim.notify("No link under cursor", vim.log.levels.WARN)
    return
  end
  if target:match("^%a[%w+.-]*://") or target:match("^mailto:") then
    vim.ui.open(target)
    return
  end
  local path = (target:gsub("#.*$", ""))
  local first = path:sub(1, 1)
  if first == "~" then
    path = vim.fn.expand(path) -- home-relative (~/…)
  elseif first ~= "/" then
    path = vim.fn.expand("%:p:h") .. "/" .. path -- relative to the current note
  end
  -- else: already absolute (/…)
  path = vim.fn.fnamemodify(path, ":p")
  vim.cmd.edit(vim.fn.fnameescape(path))
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "tex", "markdown" },
  callback = function(ev)
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en"
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.textwidth = 0
    vim.opt_local.colorcolumn = "150"
    if ev.match == "markdown" then
      vim.opt_local.conceallevel = 2
      vim.opt_local.breakindent = true
      vim.opt_local.breakindentopt = "list:-1"
      vim.opt_local.formatlistpat = [[^\s*[-*+]\s\+\|^\s*\d\+[.)]\s\+]]

      -- Color shortcuts: in visual mode, <leader>c<key> wraps the selection in
      -- a Catppuccin-named tag (shown in the <leader>mp browser preview).
      local color_keys = {
        r = "red", g = "green", b = "blue", y = "yellow",
        p = "peach", m = "mauve", t = "teal", l = "lavender",
      }
      for key, name in pairs(color_keys) do
        vim.keymap.set("x", "<leader>c" .. key, function()
          wrap_visual(name)
        end, { buffer = ev.buf, desc = "Color: wrap selection in <" .. name .. ">" })
      end

      -- gl: follow the markdown link / URL under the cursor (gx handles bare
      -- URLs too, via the built-in default mapping).
      vim.keymap.set("n", "gl", follow_link, { buffer = ev.buf, desc = "Follow markdown link / URL" })
    end
  end,
})
