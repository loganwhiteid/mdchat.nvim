local M = {}

function M.get(key)
    return require("mdchat").config[key]
end

M.defaults = {
    root_dir = vim.fn.stdpath("data") .. "/mdchat",
    chat_dir = "/chats",
    system_dir = "/systems",
    default = {
        title = "# New Chat",
        model = "sonnet-4-5",
        temp = 0.5,
        reasoning = nil, -- nil, low, medium, high
        exclude_reason = true,
        history = nil, -- number of chat message pairs to include in next completion request
        system_message = [[You are a principal software engineer and best practices are very important. Your colleague will ask you various questions about their code and ask you to assist with some coding tasks. 
Answer concisely and when asked for code avoid unnecessary verbose explanation. Only provide usage and explanation when asked or when providing system design assistance.]],
    },
    title_model = "haiku",
    auto_scroll = true, -- scroll to bottom of chat when response is finished
    scroll_on_focus = false, -- automatically scroll to the bottom when chat is focused
    show_snapshot = true, -- Print snapshot of settings used at the end of Assistant header

    --- chat buffer specific keymaps
    keymap = {
        send_message = "<CR>", -- normal mode keybind in chat windows to send message
        yank_code = "<leader>cy", -- yank the fenced code block under cursor into the code register
        paste_code = "<leader>cp", -- paste from the code register (empty string to unset)
        delete_chat = "<C-d>", -- keymap to delete a chat (in telescope menu)
        stop_generation = "<C-c>",
        jump_next_header = "]]", -- jumping to user and assistant headers
        jump_prev_header = "[[", -- jumping to user and assistant headers
    },
    delimiters = { -- delimiters for sections of the chat
        settings = "## Settings",
        model = "> Model: ",
        temp = "> Temperature: ",
        reasoning = "> Reasoning: ",
        exclude_reason = "> Exclude Reason: ",
        history = "> History: ",
        system = "> System Message",
        chat = "## Chat",
        user = "### User",
        assistant = "### Assistant",
    },
    providers = {
        -- ["openai"] = {
        --     url = "",
        --     api_key = function returning api key as string
        --     header = function(parsed buffer) returning table of header items
        --     -- needs to return a table of all headers and not just changes to default
        --     data = function(parsed buffer) returning table of data
        --     -- needs to return a table of all items that will be in the data/body of the request
        --     on_complete = function that normalizes the api completion response
        --     -- needs to return a fixed data set
        --     on_chunk = function to normalize api streamed chunks
        --     -- needs to return a fixed data set
        -- },
        ["openai"] = {
            url = "https://api.openai.com/v1/chat/completions",
            api_key = function()
                local f = assert(io.open(os.getenv("HOME") .. "/.chat/openai", "r"))
                local api_key = string.gsub(f:read("*all"), "\n", "")
                f:close()
                return api_key
            end,
        },
        ["openrouter"] = {
            url = "https://openrouter.ai/api/v1/chat/completions",
            api_key = function()
                local f = assert(io.open(os.getenv("HOME") .. "/.chat/openrouter", "r"))
                local api_key = string.gsub(f:read("*all"), "\n", "")
                f:close()
                return api_key
            end,
        },
        ["anthropic"] = {
            url = "https://api.anthropic.com/v1/messages",
            api_key = function()
                local f = assert(io.open(os.getenv("HOME") .. "/.chat/anthropic", "r"))
                local api_key = string.gsub(f:read("*all"), "\n", "")
                f:close()
                return api_key
            end,
            header = function(self)
                return {
                    ["Content-Type"] = "application/json",
                    ["anthropic-version"] = "2023-06-01",
                    ["x-api-key"] = self.api_key(),
                }
            end,
        },
    },
    --- Shorthand model alias used in your chats
    --- Models must provide a `provider` and a `model`
    models = {
        ["openrouter-claude45"] = {
            provider = "openrouter",
            model = "anthropic/claude-sonnet-4.5",
        },
        ["openai-gpt5"] = {
            provider = "openai",
            model = "gpt-5",
        },
        ["haiku"] = {
            provider = "anthropic",
            model = "claude-3-5-haiku-20241022",
        },
    },
}

function M.setup(opts)
    opts = opts or {}
    M.opts = vim.tbl_deep_extend("force", {}, M.defaults, opts)
end

return M
