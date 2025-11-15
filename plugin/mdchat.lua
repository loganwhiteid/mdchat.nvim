-------------------------------------------------------------------------------
--                               User Commands                               --
-------------------------------------------------------------------------------
if vim.g.mdchat_loaded then
    return
end
vim.g.mdchat_loaded = true

local cmd = vim.api.nvim_create_user_command

cmd("MdchatParse", function()
    local serpent = require("serpent")
    local parsed = require("mdchat.buffer").parse_buffer()

    print(serpent.dump(parsed.messages))
    print(serpent.dump(parsed.settings))
end, {})
cmd("MdchatMessages", function()
    local parsed = require("mdchat.buffer").get_messages(_, 2)

    print(vim.inspect(parsed))
end, {})
cmd("MdchatConfig", function()
    -- local serpent = require("serpent")
    local config = require("mdchat.config")

    print(vim.inspect(config.opts.delimiters))
end, {})
cmd("MdchatUpdateSetting", function(opts)
    if #opts.fargs == 2 then
        print("2 args passed " .. opts.fargs[1] .. " - " .. opts.fargs[2])
        require("mdchat.buffer").set_setting(_, { name = opts.fargs[1], value = opts.fargs[2] })
    end
end, { nargs = "*" })
cmd("MdchatAddUser", function()
    local bufnr = vim.api.nvim_get_current_buf()
    require("mdchat.buffer").add_chat(bufnr, "user")
end, {})
cmd("MdchatAddAssis", function()
    local bufnr = vim.api.nvim_get_current_buf()
    require("mdchat.buffer").add_chat(bufnr, "assistant")
end, {})
cmd("MdchatModel", function()
    local bufnr = vim.api.nvim_get_current_buf()
    require("mdchat").change_model(bufnr)
end, {})
cmd("MdchatOpen", function()
    require("mdchat").open_chat()
end, {})
cmd("MdchatNew", function()
    require("mdchat").create_new_chat()
end, {})
cmd("MdchatSaveSettings", function()
    require("mdchat").save_settings()
end, {})
cmd("MdchatReplaceSettings", function(opts)
    require("mdchat").replace_settings(opts.fargs[1])
end, { nargs = "?" })

-------------------------------------------------------------------------------
--                               Auto Commands                               --
-------------------------------------------------------------------------------

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local chat_group = augroup("_mdchat_nvim", { clear = true })

autocmd({ "BufNewFile", "BufRead" }, {
    group = chat_group,
    pattern = "*.mdchat",
    command = "set filetype=markdown",
})

autocmd("BufEnter", {
    group = chat_group,
    pattern = "*.mdchat",
    callback = function()
        require("mdchat").setup_buffer(vim.api.nvim_get_current_buf())
    end,
})
