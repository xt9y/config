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
    'https://github.com/neovim/nvim-lspconfig.git',
    'https://github.com/mason-org/mason.nvim.git',
    'https://github.com/mason-org/mason-lspconfig.nvim.git',
    'https://github.com/neovim/nvim-lspconfig.git',
    'https://github.com/morhetz/gruvbox.git',
    'https://github.com/bluz71/vim-moonfly-colors',
    'https://github.com/rebelot/kanagawa.nvim',
    'https://github.com/nvim-lua/plenary.nvim.git', 
    'https://github.com/nvim-telescope/telescope.nvim.git',
    'https://github.com/numToStr/Comment.nvim.git',
}

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
        if client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, ev.buf, {autotrigger = true})
        end
    end,
})

require("mason").setup({})

vim.lsp.config.clangd = { cmd = { "clangd" }, }
vim.lsp.enable("clangd")

require("telescope").setup({})

require("Comment").setup({ toggler = { line = "gcc", block = "gbc" }, opleader = { line = "gc", block = "gb"}, })

vim.cmd.colorscheme("gruvbox")

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
