local config = require("mdchat.config")
local buffer = require("mdchat.buffer")
local files = require("mdchat.files")
local api = require("mdchat.api")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")

local M = {}

-- WARN: PoC for completions
-- Will need to move and rewrite
local function setup_cmp()
    local ok, cmp = pcall(require, "cmp")
    if not ok then
        return
    end
    local source = {}

    source.new = function()
        return setmetatable({}, { __index = source })
    end

    source.is_available = function()
        local bufname = vim.api.nvim_buf_get_name(0)
        return bufname:match("%.mdchat$") ~= nil
    end

    source.get_trigger_characters = function()
        return { " ", ":" }
    end

    source.complete = function(self, params, callback)
        local line = params.context.cursor_before_line
        if line:match("^" .. config.opts.delimiters.model .. "%s*$") then
            local models = {}
            for alias, mapping in pairs(config.opts.models) do
                -- for alias, name in pairs(mapping) do
                table.insert(models, {
                    label = alias,
                    sortText = alias,
                    detail = "# API Provider: "
                        .. mapping.provider
                        .. "\n# Model: "
                        .. mapping.model
                        .. "\n\n## Default: "
                        .. config.opts.default.model,
                })
                -- end
            end
            table.sort(models, function(a, b)
                return a.label < b.label
            end)
            callback({
                items = models,
            })
        elseif line:match("^" .. config.opts.delimiters.reasoning .. "%s*$") then
            local reasoning = config.opts.default.reasoning or "nil"
            local detail_text = [[
# Level of reasoning (if available)
- Use nil or delete the line if you don't want reasoning used

## Default: ]] .. reasoning
            callback({
                items = {
                    {
                        label = "nil",
                        detail = detail_text,
                    },
                    {
                        label = "low",
                        detail = detail_text,
                    },
                    {
                        label = "medium",
                        detail = detail_text,
                    },
                    {
                        label = "high",
                        detail = detail_text,
                    },
                },
            })
        elseif line:match("^" .. config.opts.delimiters.temp) then
            local detail_text = [[
# Enter a value between `0.0` and `1.0`

## Default:]] .. config.opts.default.temp
            callback({
                items = {
                    {
                        label = tostring(config.opts.default.temp),
                        detail = detail_text,
                    },
                },
            })
        elseif line:match("^" .. config.opts.delimiters.history) then
            local history = config.opts.default.history or "nil"
            local detail_text = [[
# Number of past request and response pairs to include in the next request
- Use `all` or delete the line if you want to include all history
- Use `0` if you only want to send your current request

## Default: ]]
            callback({
                items = {
                    {
                        label = "all",
                        detail = detail_text .. history,
                    },
                    {
                        label = "0",
                        detail = detail_text .. history,
                    },
                },
            })
        else
            callback({ items = {} })
        end
    end

    cmp.register_source("llm_config", source.new())
end

function M.setup_buffer()
    buffer.setup_buffer()
    -- TODO: should have buffer specific keymap logic here instead of in buffer.lua
end

function M.open_chat(filename)
    files.open_chat(filename)
end

function M.focus_chat()
    if vim.g.mdchat_cur_bufnr and vim.api.nvim_buf_is_valid(vim.g.mdchat_cur_bufnr) then
        vim.api.nvim_set_current_buf(vim.g.mdchat_cur_bufnr)
    else
        M.open_chat()
    end
end

function M.create_new_chat()
    files.create_new_chat()
end

function M.clone_chat()
    local new_file = files.clone_chat()
    if new_file then
        files.open_chat(new_file)
        local title = string.sub(buffer.get_title(), 3, -1)
        buffer.set_title(title .. " - (Cloned)")
    else
        print("failed to clone chat")
    end
end

function M.change_model()
    local entries = {}
    for alias, mapping in pairs(config.opts.models) do
        table.insert(entries, {
            label = string.format("%s | %s → %s", mapping.provider, mapping.model, alias),
            ordinal = string.format("%s %s", mapping.provider, mapping.model),
            value = alias,
        })
    end
    table.sort(entries, function(a, b)
        return a.ordinal < b.ordinal
    end)
    pickers
        .new(themes.get_dropdown({}), {
            prompt_title = "Available Models: Provider | Model Name → Alias",
            finder = finders.new_table({
                results = entries,
                entry_maker = function(entry)
                    return {
                        value = entry.value,
                        display = entry.label,
                        ordinal = entry.ordinal,
                    }
                end,
            }),
            sorter = require("telescope.sorters").get_fzy_sorter(),
            attach_mappings = function(prompt_bufnr, _)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    if selection then
                        print(selection.value)
                        buffer.set_setting({ name = "model", value = selection.value })
                    end
                end)
                return true
            end,
        })
        :find()
end

function M.replace_settings(filename)
    files.get_system_settings(filename, function(settings)
        buffer.set_settings(vim.split(settings, "\n"))
    end)
end

-- TODO: implement NUI prompt
function M.save_settings()
    local filename = "settings"

    vim.ui.input({ prompt = "Enter filename: " }, function(input)
        if input then
            filename = input
        end
    end)
    local settings = buffer.get_settings_string()
    files.save_system_settings(filename, settings)
end

function M.send_request()
    -- reset stop_generation flag
    vim.g.mdchat_stop_generation = false

    local parsed_buf = buffer.parse_buffer()
    -- get buffer settings
    -- TODO: need clone the settings with values only. API doesn't need to know about setting position in the buffer
    local buf_settings = parsed_buf.settings
    -- parsed_buf returns all messages in the buffer. get_messages can be used to shrink messages table to the history value only

    local buf_messages
    if buf_settings.history and buf_settings.history.value ~= "all" then
        buf_messages = buffer.get_messages(parsed_buf.messages, buf_settings.history.value)
    else
        buf_messages = parsed_buf.messages
    end

    -- check and update title
    if buffer.get_title() == config.opts.default.title then
        print("generating title")
        M.generate_title()
    end

    -- print(vim.inspect(buf_messages))
    local state = { is_reasoning = false }
    local function process_response(response)
        --response should always be {error, content, reason}
        if response.error and response.error ~= "" then
            -- TODO: need better error log/print
            print("Response returned error: " .. response.error)
        else
            buffer.add_response(response, state)
        end
    end
    local function on_complete()
        buffer.add_header("user")
        buffer.save_chat()
    end

    -- generate snapshot of settings to display on "Assistant" header
    local snapshot
    if config.opts.show_snapshot then
        snapshot = "- {Model: " .. buf_settings.model.value
        if buf_settings.temp then
            snapshot = snapshot .. ", Temp: " .. buf_settings.temp.value
        end
        if buf_settings.history then
            snapshot = snapshot .. ", History: " .. buf_settings.history.value
        end
        if buf_settings.reasoning then
            snapshot = snapshot .. ", Reasoning: " .. buf_settings.reasoning.value
        end
        if buf_settings.exclude_reason then
            snapshot = snapshot .. ", Exclude Reason: " .. buf_settings.exclude_reason.value
        end
        snapshot = snapshot .. "}"
    end

    -- add assistant header with snapshot
    buffer.add_header("assistant", snapshot)

    local opts = {
        settings = buf_settings,
        messages = buf_messages,
        stream = true,
        response_callback = process_response,
        complete_callback = on_complete,
    }
    api.sendRequest(opts)
end

function M.generate_title()
    local messages = buffer.get_messages(nil, 0)
    local settings = {}
    settings.model = { value = config.opts.title_model }
    settings.system_message = [[Your task is to summarize the conversation into a title]]

    table.insert(messages, {
        role = "user",
        content = "Write a short (1-5 words) title for this conversation based on the previous message. Only write the title, do not respond to the query.",
    })

    local function process_response(response)
        if response.error and response.error ~= "" then
            -- TODO: need better error log/print
            print("Response returned error: " .. response.error)
        else
            -- print(vim.inspect(response))
            buffer.set_title(response.content)
        end
    end
    local function on_complete()
        print("title updated")
    end

    local opts = {
        settings = settings,
        messages = messages,
        stream = false,
        response_callback = process_response,
        complete_callback = on_complete,
    }
    api.sendRequest(opts)
end

function M.setup(opts)
    config.setup(opts)
    setup_cmp()
    vim.keymap.set("n", config.opts.keymap.send_message, M.send_request, { buffer = vim.g.mdchat_cur_bufnr })

    --ensure chat and settings paths exist
    local chat_path = vim.fn.expand(vim.fs.joinpath(config.opts.root_dir, config.opts.chat_dir))
    local settings_path = vim.fn.expand(vim.fs.joinpath(config.opts.root_dir, config.opts.system_dir))
    files.ensure_dir(chat_path)
    files.ensure_dir(settings_path)
end

return M
