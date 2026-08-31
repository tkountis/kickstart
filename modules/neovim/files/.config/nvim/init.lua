-- Managed by kickstart. Settings and keymaps only, no plugins, so this file
-- behaves identically on a laptop and on a box with no internet access.

local o = vim.opt

o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.scrolloff = 5
o.wrap = false

o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true

o.ignorecase = true
o.smartcase = true
o.incsearch = true
o.hlsearch = true

o.undofile = true
o.swapfile = false
o.backup = false
o.updatetime = 250

o.splitright = true
o.splitbelow = true
o.termguicolors = true
o.mouse = "a"
o.clipboard = "unnamedplus"

vim.g.mapleader = " "

local map = vim.keymap.set
map("n", "<leader>w", "<cmd>write<cr>", { desc = "write" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "quit" })
map("n", "<esc>", "<cmd>nohlsearch<cr>", { desc = "clear search highlight" })
map("n", "<leader>e", "<cmd>Explore<cr>", { desc = "file explorer" })

-- Move between splits without the <C-w> prefix.
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- Keep the cursor put when joining lines and when scrolling by half pages.
map("n", "J", "mzJ`z")
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

-- Briefly highlight text on yank so you can see what you took.
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.highlight.on_yank({ timeout = 150 }) end,
})
