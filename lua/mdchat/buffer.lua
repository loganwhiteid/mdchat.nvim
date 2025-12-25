local config = require("mdchat.config")

local M = {}

local function trim_table(buffer)
    while #buffer > 0 and buffer[1] == "" do
        table.remove(buffer, 1)
    end
    while #buffer > 0 and buffer[#buffer] == "" do
        table.remove(buffer)
    end
    return buffer
end

local function center_cursor()
    local win_height = vim.api.nvim_win_get_height(0)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local top_line = math.max(1, cursor_line - math.floor(win_height / 2))
    vim.fn.winrestview({ topline = top_line })
end

local function jump_to_next_header()
    vim.fn.search("^\\(" .. config.opts.delimiters.user .. "\\|" .. config.opts.delimiters.assistant .. "\\)", "W")
    center_cursor()
end

local function jump_to_prev_header()
    vim.fn.search("^\\(" .. config.opts.delimiters.user .. "\\|" .. config.opts.delimiters.assistant .. "\\)", "bW")
    center_cursor()
end

function M.setup_buffer()
    local bufnr = vim.api.nvim_get_current_buf()

    local opts = { buf = bufnr }
    vim.api.nvim_set_option_value("textwidth", vim.api.nvim_win_get_width(0) - 10, opts)

    if config.opts.scroll_on_focus then
        vim.cmd("normal! G")
    end

    -- Set buffer keymaps
    vim.keymap.set("n", config.opts.keymap.jump_next_header, jump_to_next_header, { buffer = bufnr })
    vim.keymap.set("n", config.opts.keymap.jump_prev_header, jump_to_prev_header, { buffer = bufnr })
    vim.keymap.set("n", config.opts.keymap.stop_generation, function()
        vim.g.mdchat_stop_generation = true
    end, { buffer = bufnr })

    ---Set a global variable for the current chat buffer. That way we don't have to keep passing bufnr from other modules
    vim.g.mdchat_cur_bufnr = bufnr
end

function M.parse_buffer()
    local bufnr = vim.g.mdchat_cur_bufnr
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local settings = {}
    local messages = {}

    local current_section = nil
    local current_message_type = nil
    local in_system_message = false
    local in_reasoning = false
    local buffer = {} --for multiline values in the chat

    -- FIX: I HATE ALL THE EMBEDDED IFS
    -- but the alternative is piles of abstracted functions
    -- TODO: Add notes out the wahzoo. THis is one of the ugliest things I've written in a long time
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
            elseif line:find("^" .. config.opts.delimiters.exclude_reason) then
                settings.exclude_reason =
                    { value = line:sub(config.opts.delimiters.exclude_reason:len() + 1), index = i }
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

function M.get_settings(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parsed_buf = M.parse_buffer()
    return parsed_buf.settings
end

function M.get_settings_string()
    local bufnr = vim.g.mdchat_cur_bufnr
    local parsed_buf = M.parse_buffer()
    local settings_lines =
        vim.api.nvim_buf_get_lines(bufnr, parsed_buf.settings.start_index, parsed_buf.settings.end_index, false)
    return table.concat(settings_lines, "\n")
end

--- Set current buffer's Settings section
-- @param bufnr The chat buffer idx to be updated
-- @param settings A list of lines to replace current settings section with
function M.set_settings(settings)
    if settings == nil then
        vim.notify("No settings provided. Unable to set_settings")
        return
    end
    local bufnr = vim.g.mdchat_cur_bufnr
    local parsed_buf = M.parse_buffer()
    local cur_settings = parsed_buf.settings
    vim.api.nvim_buf_set_lines(bufnr, cur_settings.start_index, cur_settings.end_index, false, settings)
    vim.cmd("silent w!")
end

--- Set the value for a single setting
-- @param bufnr The chat buffer idx to be updated
-- @param setting enum of name and value
-- @return string of the found value
function M.get_setting(setting)
    local bufnr = vim.g.mdchat_cur_bufnr
    local parsed_buf = M.parse_buffer()
    return parsed_buf.settings[setting].value
end

function M.set_setting(setting)
    local bufnr = vim.g.mdchat_cur_bufnr
    local parsed_buf = M.parse_buffer()
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

-- HACK: I don't know how I feel about this. In normal API request we need to get settings and messages
-- If we called each of those functions, we'd be parsing the buffer twice.
-- Instead we changed the function so the buffer was parsed upstream giving the option to pass
-- the already parsed messages to this function
function M.get_messages(messages, history)
    assert(type(history) == "number", "value must be an integer")
    messages = messages or M.parse_buffer().messages

    if history ~= nil and #messages > (history * 2) + 1 then
        -- only return the last [history] pairs plus the last user message
        local reduced_messages = {}
        table.insert(reduced_messages, 1, messages[#messages])

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

function M.add_header(header)
    local bufnr = vim.g.mdchat_cur_bufnr
    if config.opts.delimiters[header] ~= nil then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", config.opts.delimiters[header], "", "" })
    end
end

function M.add_response(response, state)
    local bufnr = vim.g.mdchat_cur_bufnr
    local content = ""
    -- print(vim.inspect(response) .. "\n" .. vim.inspect(state))
    if response.content ~= "" then
        if state.is_reasoning then
            state.is_reasoning = false
            content = "\n>\n\n" .. response.content
        else
            content = response.content
        end
    elseif response.reason ~= "" then
        if not state.is_reasoning then
            state.is_reasoning = true
            content = "> #### Reasoning\n" .. response.reason
        else
            content = response.reason
        end
    end
    local current_line = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1] or ""
    current_line = current_line .. content

    local lines = vim.split(current_line, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, { lines[1] })
    if #lines > 1 then
        local next_lines = vim.list_slice(lines, 2)

        -- reasoning lines should always start with `> `
        if state.is_reasoning then
            for i, line in ipairs(next_lines) do
                next_lines[i] = "> " .. line
            end
        else
            -- Catch response lines that start with known delimiters
            for i, line in ipairs(next_lines) do
                if
                    line:match("^" .. config.opts.delimiters.user)
                    or line:match("^" .. config.opts.delimiters.assistant)
                then
                    -- add extra header tag
                    next_lines[i] = "#" .. line
                end
            end
        end
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, next_lines)
    end
end

function M.get_title()
    local bufnr = vim.g.mdchat_cur_bufnr
    return vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
end

function M.set_title(title)
    local bufnr = vim.g.mdchat_cur_bufnr
    if title ~= "" then
        vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "# " .. title })
    end
    vim.cmd("silent w!")
end

function M.save_chat()
    vim.api.nvim_buf_call(vim.g.mdchat_cur_bufnr, function()
        vim.cmd("silent w!")
    end)
end

return M
