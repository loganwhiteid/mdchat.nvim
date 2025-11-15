local config = require("mdchat.config")

local M = {}

--[[
-- Files needs to have the following features
-- file save
-- file open
-- file search
--]]

--[[
-- stored settings
--  - Name
--  - settings buffer
--]]

M.open_chat = function(filename)
    local chat_path = config.opts.root_dir .. config.opts.chat_dir

    if filename and filename ~= "" then
        vim.cmd("edit " .. chat_path .. "/" .. filename)
        return
    end

    local function call_telescope()
        local previewers = require("telescope.previewers")
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        local custom_previewer = previewers.new_buffer_previewer({
            define_preview = function(self, entry, _)
                local path = entry.path or entry.filename
                vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
                vim.fn.jobstart({ "cat", path }, {
                    stdout_buffered = true,
                    on_stdout = function(_, data)
                        if data then
                            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, data)
                        end
                    end,
                })
            end,
        })

        local entry_maker = function(line)
            local entry = require("telescope.make_entry").gen_from_vimgrep()(line)
            -- we only care about '^# ' matches if it's the first line. Otherwise any other '^# ' in the file will be returned
            if entry.value:match(":1:1") then
                local entry_filename, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
                entry.filename = entry_filename
                entry.lnum = tonumber(lnum)
                entry.col = tonumber(col)
                entry.text = text
                entry.path = require("plenary.path"):new(chat_path, entry_filename):absolute()
                entry.time = vim.uv.fs_stat(entry.path).mtime.sec
                local timestamp = os.date("%b %d %Y %H:%M", entry.time)
                entry.display = string.format("%s (%s)", entry.text:sub(3), timestamp)
                entry.ordinal = entry.display
                return entry
            end
            return nil
        end

        require("telescope.builtin").grep_string({
            prompt_title = "Load Conversation",
            search = "^# ",
            use_regex = true,
            cwd = chat_path,
            glob_pattern = "*.mdchat",
            entry_maker = entry_maker,
            previewer = custom_previewer,
            additional_args = function()
                return { "--sortr=modified" } -- sort by modified date asc
            end,
            attach_mappings = function(prompt_bufnr, map)
                local function delete_file()
                    local entry = action_state.get_selected_entry()
                    local filepath = entry.path
                    vim.cmd("silent !rm " .. filepath)
                    actions.close(prompt_bufnr)
                    vim.schedule(function()
                        call_telescope()
                    end)
                end

                map("i", config.opts.keymap.delete_chat, function()
                    delete_file()
                end)
                map("n", config.opts.keymap.delete_chat, function()
                    delete_file()
                end)
                return true
            end,
        })
    end

    -- wait so the popup doesn't cover finder
    vim.defer_fn(function()
        call_telescope()
    end, 100)
end

-- TODO: refactor. Files module shouldn't be directly messing with buffers
M.create_new_chat = function()
    local chat_path = config.opts.root_dir .. config.opts.chat_dir
    -- don't create new file if one already exists with default title
    -- for _, file in ipairs(vim.fn.readdir(chat_path)) do
    --     local path = string.format("%s/%s", chat_path, file)
    --     local lines = vim.fn.readfile(path)
    --     if lines[1] == config.opts.default.title then
    --         vim.cmd("edit " .. path)
    --         return vim.api.nvim_get_current_buf()
    --     end
    -- end

    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    local filename = string.format("%s/%s.mdchat", chat_path, timestamp)

    vim.cmd("edit " .. filename)
    local bufnr = vim.api.nvim_get_current_buf()

    local lines = {
        config.opts.default.title,
        "",
        config.opts.delimiters.settings,
        "",
        config.opts.delimiters.model .. config.opts.default.model,
        config.opts.delimiters.temp .. config.opts.default.temp,
    }
    if config.opts.default.history ~= nil then
        table.insert(lines, config.opts.delimiters.history .. config.opts.default.history)
    end
    if config.opts.default.reasoning ~= nil then
        table.insert(lines, config.opts.delimiters.reasoning .. config.opts.default.reasoning)
    end

    table.insert(lines, "")
    table.insert(lines, config.opts.delimiters.system)

    local system_lines = vim.split(config.opts.default.system_message, "\n", { plain = true })
    vim.list_extend(lines, system_lines)
    table.insert(lines, "")
    table.insert(lines, config.opts.delimiters.chat)
    table.insert(lines, "")
    table.insert(lines, config.opts.delimiters.user)
    table.insert(lines, "")
    table.insert(lines, "")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    vim.cmd("write")

    return bufnr
end

local read_settings_file = function(filename)
    --expects full expanded path
    local file = io.open(filename, "r")
    if not file then
        vim.notify("Failed to open file: " .. filename, vim.log.levels.ERROR)
        return ""
    end
    local content = file:read("*a")
    file:close()

    return content
end

-- TODO: needs refactor. build without callbacks
M.get_system_settings = function(filename, callback)
    local file_path = vim.fn.expand(vim.fs.joinpath(config.opts.root_dir, config.opts.system_dir))
    local settings_string = ""
    if filename and filename ~= "" then
        local full_path = vim.fs.joinpath(file_path, filename .. ".mdchat")
        settings_string = read_settings_file(full_path)
        if callback then
            callback(settings_string)
        end
    else
        local function call_telescope()
            local previewers = require("telescope.previewers")
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")

            local custom_previewer = previewers.new_buffer_previewer({
                define_preview = function(self, entry, _)
                    local path = entry.path or entry.filename
                    vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
                    vim.api.nvim_set_option_value("wrap", true, { win = self.state.winid })
                    vim.fn.jobstart({ "cat", path }, {
                        stdout_buffered = true,
                        on_stdout = function(_, data)
                            if data then
                                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, data)
                            end
                        end,
                    })
                end,
            })

            require("telescope.builtin").find_files({
                prompt_title = "Load Settings",
                cwd = file_path,
                glob_pattern = "*.mdchat",
                previewer = custom_previewer,
                path_display = function(_, path)
                    return vim.fn.fnamemodify(path, ":t:r")
                end,
                layout_config = {
                    height = 0.35,
                    width = 0.8,
                },
                additional_args = function()
                    return { "--sortr=modified" } -- sort by modified date asc
                end,
                attach_mappings = function(prompt_bufnr, map)
                    local function delete_file()
                        local entry = action_state.get_selected_entry()
                        local filepath = entry.path
                        vim.cmd("silent !rm " .. filepath)
                        actions.close(prompt_bufnr)
                        vim.schedule(function()
                            call_telescope()
                        end)
                    end

                    actions.select_default:replace(function()
                        local entry = action_state.get_selected_entry()
                        actions.close(prompt_bufnr)
                        local settings = read_settings_file(entry.path)
                        if callback then
                            callback(settings)
                        end
                    end)
                    map("i", config.opts.keymap.delete_chat, function()
                        delete_file()
                    end)
                    map("n", config.opts.keymap.delete_chat, function()
                        delete_file()
                    end)
                    return true
                end,
            })
        end

        -- wait so the popup doesn't cover finder
        vim.defer_fn(function()
            call_telescope()
        end, 100)
    end
end

--- Store settings snapshot to disk
---
---@param name string filename to use
---@param settings string prebuilt string of the settings section of a buffer
M.save_system_settings = function(name, settings)
    local file_path = vim.fn.expand(vim.fs.joinpath(config.opts.root_dir, config.opts.system_dir))
    vim.fn.mkdir(file_path, "p")

    local full_path = vim.fs.joinpath(file_path, name .. ".mdchat")
    local file = io.open(full_path, "w")
    if not file then
        vim.notify("Failed to open file: " .. full_path, vim.log.levels.ERROR)
        return
    end

    file:write(settings)
    file:close()
end

return M
