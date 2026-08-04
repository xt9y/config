vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 300
vim.opt.wrap = false
vim.opt.linebreak = false
vim.opt.sidescroll = 1
vim.opt.sidescrolloff = 1

vim.opt.complete:append("o")
vim.opt.completeopt = {"menuone", "noselect"}

vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.o.autocomplete = true;
vim.o.pumheight = 5
vim.o.pumborder = "none"
vim.o.pumblend = 10

vim.pack.add {
    'https://github.com/mason-org/mason.nvim.git',
    'https://github.com/mason-org/mason-lspconfig.nvim.git',
    'https://github.com/neovim/nvim-lspconfig.git',
    'https://github.com/catppuccin/nvim',
    'https://github.com/morhetz/gruvbox.git',
    'https://github.com/rebelot/kanagawa.nvim',
    'https://github.com/nvim-lua/plenary.nvim.git', 
    'https://github.com/nvim-telescope/telescope.nvim.git',
    'https://github.com/numToStr/Comment.nvim.git',
}

local function load_matugen_colors()
    local matugen_path = vim.fn.stdpath("config") .. "/matugen_colors.lua"
    local overrides = {}

    if vim.fn.filereadable(matugen_path) == 1 then
        local chunk = loadfile(matugen_path)
        if chunk then
            local colors = chunk()
            if type(colors) == "table" then
                overrides = { all = colors, mocha = colors }
            end
        end
    end

    return overrides
end

local function apply_catppuccin_theme()
    local check_cat_installed = pcall(require, "catppuccin")
    if not check_cat_installed then
        return false
    end

    for k, _ in pairs(package.loaded) do
        if k:match("^catppuccin") then
            package.loaded[k] = nil
        end
    end

    local ok_cat, cat = pcall(require, "catppuccin")
    if not ok_cat then
        return false
    end

    vim.cmd("hi clear")
    if vim.fn.exists("syntax_on") == 1 then
        vim.cmd("syntax reset")
    end
    vim.g.colors_name = nil

    cat.setup({
        flavour = "mocha",
        compile = { enabled = false },
        color_overrides = load_matugen_colors(),
        integrations = {
            cmp = true,
            gitsigns = true,
            nvimtree = true,
            treesitter = true,
            telescope = { enabled = true },
            indent_blankline = { enabled = true },
            native_lsp = {
                enabled = true,
                underlines = {
                    errors = { "undercurl" },
                    hints = { "undercurl" },
                    warnings = { "undercurl" },
                    information = { "undercurl" },
                },
            },
        },
    })

    vim.cmd("colorscheme catppuccin")

    local ok_lualine, lualine = pcall(require, "lualine")
    if ok_lualine then
        lualine.setup({ options = { theme = "catppuccin-nvim" } })
    end

    vim.cmd("redraw!")
    return true
end

local function reload_catppuccin_with_retry(attempts)
    if apply_catppuccin_theme() then
        vim.notify("Matugen colors reloaded!", vim.log.levels.INFO)
        return
    end

    if attempts > 0 then
        vim.defer_fn(function()
            reload_catppuccin_with_retry(attempts - 1)
        end, 100)
    end
end

_G.reload_matugen_colors = function()
    vim.schedule(function()
        reload_catppuccin_with_retry(20)
    end)
end

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        _G.reload_matugen_colors()
    end,
})

do
    local uv = vim.uv or vim.loop
    local config_dir = vim.fn.stdpath("config")
    _G.matugen_reload_timer = uv.new_timer()
    _G.matugen_theme_watcher = uv.new_fs_event()

    if _G.matugen_theme_watcher then
        _G.matugen_theme_watcher:start(config_dir, {}, vim.schedule_wrap(function(err, filename)
            if not err and filename == "matugen_colors.lua" then
                _G.matugen_reload_timer:stop()
                _G.matugen_reload_timer:start(250, 0, vim.schedule_wrap(function()
                    _G.reload_matugen_colors()
                end))
            end
        end))
    end
end

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
        if client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, ev.buf, {autotrigger = true})
        end
    end,
})

require("mason").setup({})
require("mason-lspconfig").setup({})

require("telescope").setup({
    defaults = {
        file_ignore_patterns = {
            "^build/",
            "^cmake%-build.*",
            "^out/",
            "^%.git/",
        },
    },
})

require("Comment").setup({ 
    toggler = { 
        line = "gcc", 
        block = "gbc" 
    }, 
    opleader = { 
        line = "gc", 
        block = "gb"
    }, 
})

local function open_in(split)
    return function()
        require("telescope.builtin").find_files({
            attach_mappings = function(prompt_bufnr, map)
                map("i", "<CR>", function()
                    local sel = require("telescope.actions.state").get_selected_entry()
                    require("telescope.actions").close(prompt_bufnr)
                    vim.cmd(split == "v" and "vsplit " or split == "h" and "split " or "" .. sel.path)
                end)
                map("n", "<CR>", function()
                    local sel = require("telescope.actions.state").get_selected_entry()
                    require("telescope.actions").close(prompt_bufnr)
                    vim.cmd(split == "v" and "vsplit " or split == "h" and "split " or "" .. sel.path)
                end)
                return true
            end,
        })
    end
end

vim.keymap.set("n", "mm", function() vim.cmd("w | make") end)
vim.keymap.set("n", "<Space><Space>", function() require("telescope.builtin").find_files() end)
vim.keymap.set("n", "<Space><Enter>", function() require("telescope.builtin").live_grep()  end)
vim.keymap.set("n", "hh", open_in("v"))
vim.keymap.set("n", "vv", open_in("h"))
vim.keymap.set("n", "cc", function() vim.cmd("e ~/.config/nvim/init.lua") end)
