local config = require("mdchat.config")
local buffer = require("mdchat.buffer")
local files = require("mdchat.files")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")

local M = {}

-- HACK: PoC for completions
-- TODO: Will need to move and rewrite
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
            -- TODO: Move this to a function that's being called repeatedly
            local models = {}
            for title, mapping in pairs(config.model_aliases) do
                for alias, name in pairs(mapping) do
                    table.insert(models, {
                        label = alias,
                        sortText = alias,
                        detail = "# API Provider: "
                            .. title
                            .. "\n# Model: "
                            .. name
                            .. "\n\n## Default: "
                            .. config.opts.default.model,
                    })
                end
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
                        label = "med",
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
- Use `nil` or delete the line if you want to include all history
- Use `0` if you only want to send your current request

## Default: ]]
            callback({
                items = {
                    {
                        label = "nil",
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

function M.setup_buffer(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    buffer.setup_buffer(bufnr)
    -- TODO: should have keymap logic here instead of in buffer.lua
end

function M.open_chat(filename)
    files.open_chat(filename)
end

function M.create_new_chat()
    files.create_new_chat()
end

function M.change_model(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local entries = {}
    for provider, mapping in pairs(config.model_aliases) do
        for alias, model in pairs(mapping) do
            -- print(string.format("%s - %s", provider, alias))
            table.insert(entries, {
                label = string.format("%s | %s → %s", provider, model, alias),
                ordinal = string.format("%s %s", provider, model),
                value = alias,
            })
        end
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
                        buffer.set_setting(bufnr, { name = "model", value = selection.value })
                    end
                end)
                return true
            end,
        })
        :find()
end

function M.replace_settings(filename)
    files.get_system_settings(filename, function(settings)
        buffer.set_settings(nil, vim.split(settings, "\n"))
    end)
end

-- TODO: implement NUI prompt
function M.save_settings(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local filename = "settings"

    vim.ui.input({ prompt = "Enter filename: " }, function(input)
        if input then
            filename = input
        end
    end)
    local settings = buffer.get_settings_string(bufnr)
    files.save_system_settings(filename, settings)
end

function M.setup(opts)
    config.setup(opts)
    setup_cmp()
end

return M
