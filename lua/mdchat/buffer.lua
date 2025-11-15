local config = require("mdchat.config")

local M = {}

-- TODO: should use vim.list_slice instead of repeated table.remove calls
local trim_table = function(buffer)
    while #buffer > 0 and buffer[1] == "" do
        table.remove(buffer, 1)
    end
    while #buffer > 0 and buffer[#buffer] == "" do
        table.remove(buffer)
    end
    return buffer
end

M.setup_buffer = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local opts = { buf = bufnr }
    vim.api.nvim_set_option_value("textwidth", vim.api.nvim_win_get_width(0) - 10, opts)

    if config.opts.scroll_on_focus then
        vim.cmd("normal! G")
    end

    -- TODO: Need to set the current chat buffer as a global
    -- this fuction should only be called by autocommands when entering a *.chat file
    -- then in all functions in this module shouldn't take in a bufnr and just use the global instead
    -- otherwise the functions could be triggered outside the chat buffer
    vim.g.mdchat_cur_bufnr = bufnr
end

M.parse_buffer = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local settings = {}
    local messages = {}

    local current_section = nil
    local current_message_type = nil
    local in_system_message = false
    local in_reasoning = false
    local buffer = {} --for multiline values in the chat

    -- HACK: I HATE ALL THE EMBEDDED IFS
    -- TODO: Add notes out the wahzoo. THis is one of the ugliest things I've written
    for i, line in ipairs(lines) do
        if line:match("^" .. config.opts.delimiters.settings) then
            current_section = "settings"
            current_message_type = nil
            settings.start_index = i
        elseif line:match("^" .. config.opts.delimiters.chat) then
            current_section = "chat"
            current_message_type = nil
            in_system_message = false
            settings.end_index = i - 1
        elseif current_section == "chat" and line:match("^" .. config.opts.delimiters.user) then
            if current_message_type == "assistant" then
                buffer = trim_table(buffer)
                table.insert(messages, { role = "assistant", content = table.concat(buffer, "\n") })
            end
            current_message_type = "user"
            buffer = {}
        elseif current_section == "chat" and line:match("^" .. config.opts.delimiters.assistant) then
            if current_message_type == "user" then
                buffer = trim_table(buffer)
                table.insert(messages, { role = "user", content = table.concat(buffer, "\n") })
            end
            current_message_type = "assistant"
            buffer = {}
        elseif current_section == "chat" and current_message_type then
            if current_message_type == "assistant" then
                -- TODO: Should this be hardcoded? Or should this be a config item
                if not in_reasoning then
                    if line:match("^> #### Reasoning") then
                        in_reasoning = true
                    else
                        table.insert(buffer, line)
                    end
                    -- Reasoning is always in a comment block followed by a blank line
                elseif not line:match("^>") then
                    in_reasoning = false
                end
            else
                table.insert(buffer, line)
            end
        elseif current_section == "settings" and line ~= "" then
            -- check for known settings by config.delimiters
            if line:find("^" .. config.opts.delimiters.model) then
                settings.model = { value = line:sub(config.opts.delimiters.model:len() + 1), index = i }
            elseif line:find("^" .. config.opts.delimiters.temp) then
                settings.temp = { value = tonumber(line:sub(config.opts.delimiters.temp:len() + 1)), index = i }
            elseif line:find("^" .. config.opts.delimiters.history) then
                settings.history = { value = tonumber(line:sub(config.opts.delimiters.history:len() + 1)), index = i }
            elseif line:find("^" .. config.opts.delimiters.reasoning) then
                settings.reasoning = { value = line:sub(config.opts.delimiters.reasoning:len() + 1), index = i }
            elseif line == config.opts.delimiters.system then
                in_system_message = true
                settings.system_message = ""
            elseif in_system_message then
                settings.system_message = settings.system_message .. line .. "\n"
            end
        end
    end
    -- Last section should be the latest user request/message
    if current_message_type == "user" then
        buffer = trim_table(buffer)
        table.insert(messages, { role = "user", content = table.concat(buffer, "\n") })
    end
    return { settings = settings, messages = messages }
end

M.get_settings = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parsed_buf = M.parse_buffer(bufnr)
    return parsed_buf.settings
end

M.get_settings_string = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parsed_buf = M.parse_buffer(bufnr)
    local settings_lines =
        vim.api.nvim_buf_get_lines(bufnr, parsed_buf.settings.start_index, parsed_buf.settings.end_index, false)
    return table.concat(settings_lines, "\n")
end

-- TODO: currently expecting array of lines sent for new settings
-- Do we need a structured table instead so we can replace only the settings provided?

--- Set current buffer's Settings section
-- @param bufnr The chat buffer idx to be updated
-- @param settings A list of lines to replace current settings section with
M.set_settings = function(bufnr, settings)
    if settings == nil then
        vim.notify("No settings provided. Unable to set_settings")
        return
    end
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parsed_buf = M.parse_buffer(bufnr)
    local cur_settings = parsed_buf.settings
    vim.api.nvim_buf_set_lines(bufnr, cur_settings.start_index, cur_settings.end_index, false, settings)
end

--- Set the value for a single setting
-- @param bufnr The chat buffer idx to be updated
-- @param setting enum of name and value
-- @return string of the found value
M.get_setting = function(bufnr, setting)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parsed_buf = M.parse_buffer(bufnr)
    return parsed_buf.settings[setting].value
end

M.set_setting = function(bufnr, setting)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parsed_buf = M.parse_buffer(bufnr)
    if parsed_buf.settings[setting.name] then
        local idx = parsed_buf.settings[setting.name].index
        vim.api.nvim_buf_set_lines(
            bufnr,
            idx - 1,
            idx,
            false,
            { config.opts.delimiters[setting.name] .. setting.value }
        )
    else
        -- assumes the setting isn't in the buffer yet. Add it.
        -- WARN: this assumes there's always a model setting. Should be refactored
        local modelidx = parsed_buf.settings.model.index
        vim.api.nvim_buf_set_lines(
            bufnr,
            modelidx,
            modelidx,
            false,
            { config.opts.delimiters[setting.name] .. setting.value }
        )
    end
end

M.get_messages = function(bufnr, history)
    local messages = M.parse_buffer(bufnr).messages

    if history ~= nil and #messages > (history * 2) + 1 then
        -- only return the last [history] pairs plus the last user message
        local reduced_messages = {}
        table.insert(reduced_messages, 1, messages[#messages])

        -- TODO:refactor needed, but retain `0` history handling
        for i = #messages - 1, 1, -1 do
            if history > 0 then
                if messages[i].role == "assistant" then
                    table.insert(reduced_messages, 1, messages[i])
                elseif messages[i].role == "user" then
                    table.insert(reduced_messages, 1, messages[i])
                    history = history - 1
                end
            else
                break
            end
        end
        return reduced_messages
    else
        return messages
    end
end

M.add_chat = function(bufnr, header)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if config.opts.delimiters[header] ~= nil then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", config.opts.delimiters[header], "", "" })
    end
end

return M
