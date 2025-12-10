-------------------------------------------------------------------------------
--                               User Commands                               --
-------------------------------------------------------------------------------
if vim.g.mdchat_loaded then
    return
end
vim.g.mdchat_loaded = true

local cmd = vim.api.nvim_create_user_command

cmd("MdchatUpdateSetting", function(opts)
    if #opts.fargs == 2 then
        print("2 args passed " .. opts.fargs[1] .. " - " .. opts.fargs[2])
        require("mdchat.buffer").set_setting({ name = opts.fargs[1], value = opts.fargs[2] })
    end
end, { nargs = "*" })
cmd("MdchatModel", function()
    require("mdchat").change_model()
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
cmd("MdchatRequest", function()
    require("mdchat").send_request()
end, {})
cmd("MdchatTitle", function()
    require("mdchat").generate_title()
end, {})

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
        require("mdchat").setup_buffer()
    end,
})

autocmd("BufLeave", {
    group = chat_group,
    pattern = "*.mdchat",
    command = "silent! write!",
})
