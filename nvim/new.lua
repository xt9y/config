-- options
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

vim.o.autocomplete = true
vim.o.pumheight = 5
vim.o.pumborder = "none"
vim.o.pumblend = 10


-- leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "


-- plugins
vim.pack.add {
    -- lsp/tools
    'https://github.com/mason-org/mason.nvim.git',
    'https://github.com/mason-org/mason-lspconfig.nvim.git',
    'https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim',
    'https://github.com/neovim/nvim-lspconfig.git',

    -- syntax
    'https://github.com/nvim-treesitter/nvim-treesitter.git',

    -- ui
    'https://github.com/metalelf0/black-metal-theme-neovim',
    'https://github.com/morhetz/gruvbox.git',
    'https://github.com/rebelot/kanagawa.nvim',

    -- tools
    'https://github.com/nvim-lua/plenary.nvim.git',
    'https://github.com/nvim-telescope/telescope.nvim.git',
    'https://github.com/numToStr/Comment.nvim.git',
}


-- filetypes
vim.filetype.add({
    extension = {
        ll = "llvm",
        zig = "zig",
        odin = "odin",
    },
})


-- treesitter
require("nvim-treesitter").install({
    "c",
    "cpp",
    "lua",
    "zig",
    "odin",
    "bash",
    "json",
    "markdown",
})

vim.api.nvim_create_autocmd("FileType", {
    callback = function()
        if pcall(vim.treesitter.start) then
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
})


-- mason
require("mason").setup({})

require("mason-lspconfig").setup({
    ensure_installed = {
        "zls",
        "ols",
    },
})

require("mason-tool-installer").setup({})


-- lsp
vim.lsp.config("clangd", {
    cmd = { "env", "LC_ALL=C", "clangd", "--query-driver=/usr/bin/cc", "--resource-dir=/usr/lib/clang/21" },
})

vim.lsp.enable({
    "zls",
    "ols",
    "clangd",
})

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))

        if client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(
                true,
                client.id,
                ev.buf,
                {autotrigger = true}
            )
        end
    end,
})

-- diagnostics
vim.diagnostic.config({
    virtual_text = {
        spacing = 4,
        prefix = "●",
    },
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = {
        border = "rounded",
        source = "always",
    },
})

-- show diagnostic popup on hover
vim.api.nvim_create_autocmd("CursorHold", {
    callback = function()
        vim.diagnostic.open_float(nil, {
            focus = false,
            scope = "cursor",
        })
    end,
})

-- llvm ir
vim.api.nvim_create_autocmd("FileType", {
    pattern = "llvm",
    callback = function()
        vim.bo.commentstring = "; %s"
        vim.cmd("syntax enable")
        vim.cmd("runtime! syntax/llvm.vim")
    end,
})


-- telescope
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


-- comments
require("Comment").setup({
    toggler = {
        line = "gcc",
        block = "gbc",
    },

    opleader = {
        line = "gc",
        block = "gb",
    },
})


-- theme
-- require("black-metal").setup({
--     theme = "darkthrone", -- khold 
--     variant = "dark",
--     alt_bg = true,
--
--     code_style = {
--         comments = "italic",
--         conditionals = "none",
--         functions = "none",
--         keywords = "none",
--         headings = "bold",
--         operators = "none",
--         keyword_return = "none",
--         strings = "none",
--         variables = "none",
--     },
-- })

-- require("black-metal").load()
--
vim.cmd.colorscheme("retrobox")


-- telescope open helpers
local function open_in(split)
    return function()
        require("telescope.builtin").find_files({
            attach_mappings = function(prompt_bufnr, map)

                local open = function()
                    local sel = require("telescope.actions.state").get_selected_entry()
                    require("telescope.actions").close(prompt_bufnr)

                    if split == "v" then
                        vim.cmd("vsplit " .. sel.path)
                    elseif split == "h" then
                        vim.cmd("split " .. sel.path)
                    else
                        vim.cmd("edit " .. sel.path)
                    end
                end

                map("i", "<CR>", open)
                map("n", "<CR>", open)

                return true
            end,
        })
    end
end


-- keymaps
vim.keymap.set("n", "mm", function()
    vim.cmd("w | make")
end)

vim.keymap.set("n", "<Space><Space>", function()
    require("telescope.builtin").find_files()
end)

vim.keymap.set("n", "<Space><Enter>", function()
    require("telescope.builtin").live_grep()
end)

vim.keymap.set("n", "hh", open_in("v"))
vim.keymap.set("n", "vv", open_in("h"))

vim.keymap.set("n", "cc", function()
    vim.cmd("e ~/.config/nvim/init.lua")
end)
