local M = {}

function M.get(key)
    return require("mdchat").config[key]
end

-- TODO: Refactor
M.default_model_aliases = {}

-- TODO: Refactor. Shouldn't be a function. Just create opts here
M.defaults = function()
    return {
        root_dir = vim.fn.stdpath("data") .. "/mdchat",
        chat_dir = "/chats",
        system_dir = "/systems",
        -- save_to_local = false,
        api_keys = {
            openai = function()
                return os.getenv("OPENAI_API_KEY") or vim.fn.input("OpenAI API Key: ")
            end,
            anthropic = function()
                return os.getenv("ANTHROPIC_API_KEY") or vim.fn.input("Anthropic API Key: ")
            end,
            openrouter = function()
                return os.getenv("OPENROUTER_API_KEY") or vim.fn.input("OpenRouter API Key: ")
            end,
        },
        default = {
            title = "# New Chat",
            model = "sonnet-4-5",
            temp = 0.5,
            reasoning = nil, -- nil, low, med, high
            -- TODO: implement exclude reason tokens from response (data = {reasoning {effort = 'medium', exclude = true, enabled = true}})
            exclude_reason = true,
            history = nil, -- number of chat message pairs to include in next completion request
            system_message = [[You are a principal software engineer and best practices are very important. Your colleague will ask you various questions about their code and ask you to assist with some coding tasks. 
Answer concisely and when asked for code avoid unnecessary verbose explanation. Only provide usage and explanation when asked or when providing system design assistance.]],
        },
        title_model = "haiku",
        auto_scroll = true, -- scroll to bottom of chat when response is finished
        -- auto_format = false, -- automatically format the chat on save
        scroll_on_focus = false, -- automatically scroll to the bottom when chat is focused
        -- code_register = "c", -- register to use for yanking/pasting code
        keymap = {
            send_message = "<CR>", -- normal mode keybind in chat windows to send message
            yank_code = "<leader>cy", -- yank the fenced code block under cursor into the code register
            paste_code = "<leader>cp", -- paste from the code register (empty string to unset)
            delete_chat = "<C-d>", -- keymap to delete a chat (in telescope menu)
            stop_generation = "<C-c>",
        },
        delimiters = { -- delimiters for sections of the chat
            settings = "## Settings",
            model = "> Model: ",
            temp = "> Temperature: ",
            reasoning = "> Reasoning: ",
            history = "> History: ",
            system = "> System Message",
            chat = "## Chat",
            user = "### User",
            assistant = "### Assistant",
        },
        -- popup = {
        --     size = 40, -- percent of screen
        --     direction = "right", -- left, right, top, bottom, center
        -- }
    }
end

M.setup = function(opts)
    opts = opts or {}
    M.opts = vim.tbl_deep_extend("force", {}, M.defaults(), opts)
    -- TODO: refactor
    M.model_aliases = vim.deepcopy(M.default_model_aliases)
    if opts.model_maps then
        for provider, model_map in pairs(opts.model_maps) do
            M.model_aliases[provider] = vim.tbl_deep_extend("force", M.model_aliases[provider] or {}, model_map)
        end
    end
end

return M
