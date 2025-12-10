local config = require("mdchat.config")
local Job = require("plenary.job")

local M = {}

-- build header following OpenAI standard
local function default_header(provider)
    local api_key
    if provider.api_key then
        api_key = provider.api_key()
    else
        api_key = vim.fn.input({ prompt = "key not found, enter here: " })
    end
    return {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
        ["X-Title"] = "mdchat.nvim",
    }
end

-- Build data/body following OpenAI standard
local function default_data(settings, messages, model_name, stream)
    -- vim.api.nvim_buf_set_lines(0, -1, -1, false, vim.split(vim.inspect(parsed_buf), "\n", { plain = true }))
    local data = {
        model = model_name,
    }
    if stream then
        data.stream = true
    end

    if settings.temp then
        data.temperature = settings.temp.value
    end
    -- local reasoning_val = settings.reasoning.value
    -- if reasoning_val and reasoning_val ~= "nil" and string.lower(reasoning_val) ~= "none" then
    if
        settings.reasoning
        and settings.reasoning.value ~= "nil"
        and string.lower(settings.reasoning.value) ~= "none"
    then
        local reasoning = {
            effort = settings.reasoning.value,
        }
        if settings.exclude_reason and string.lower(settings.exclude_reason.value) == "true" then
            reasoning.exclude = true
        end
        data.reasoning = reasoning
    end
    -- WARN: Using parsed_buf.messages instead of deepcopy to new table
    if settings.system_message then
        table.insert(messages, 1, { role = "developer", content = settings.system_message })
    end
    data.messages = messages

    return data
end

local function default_on_stdout(stream, data)
    local response = {
        error = "",
        content = "",
        reason = "",
    }
    local raw_json = string.gsub(data, "^data: ", "")
    local ok, parsed_data = pcall(vim.json.decode, raw_json)
    if not ok then
        vim.print("---failed to decode json")
        vim.print(vim.inspect(raw_json))
        return
    end

    local function check_valid(content)
        return content ~= nil and content ~= vim.NIL and content ~= ""
    end

    if parsed_data.choices ~= nil then
        -- print(vim.inspect(parsed_data.choices[1]))
        if stream then
            local chunk_delta = parsed_data.choices[1].delta
            if check_valid(chunk_delta.content) then
                response.content = chunk_delta.content
            elseif check_valid(chunk_delta.reasoning) then
                response.reason = chunk_delta.reasoning
            -- TODO: this isn't correct. Errors are structured differently
            elseif check_valid(chunk_delta.error) then
                response.error = chunk_delta.error
            end
        else
            response.content = parsed_data.choices[1].message.content
            -- response.reason = parsed_data.choices[1].message.reasoning
        end
    else
        print("choices not found: " .. vim.inspect(parsed_data))
    end

    return response
end
local function default_on_stderror()
    --
end

local function default_on_exit()
    --
end

local function build_curl_args(url, headers, data, stream)
    local curl_args = { "--silent", "--show-error", url }
    if stream then
        table.insert(curl_args, "--no-buffer")
    end

    for k, v in pairs(headers) do
        table.insert(curl_args, "--header")
        table.insert(curl_args, string.format("%s: %s", k, v))
    end

    table.insert(curl_args, "--data")
    table.insert(curl_args, vim.json.encode(data))

    -- debug
    -- local lines = vim.split(vim.inspect(curl_args), "\n", { plain = true })
    -- vim.api.nvim_buf_set_lines(0, -1, -1, false, lines)

    return curl_args
end

function M.sendRequest(opts)
    -- print("API SEND REQUEST---")
    -- print(vim.inspect(parsed_buf))
    -- vim.api.nvim_buf_set_lines(0, -1, -1, false, vim.split(vim.inspect(opts), "\n", { plain = true }))
    local provider_name
    local model_name
    if config.opts.models[opts.settings.model.value] then
        provider_name = config.opts.models[opts.settings.model.value].provider
        model_name = config.opts.models[opts.settings.model.value].model
    else
        --fallback
        provider_name = "openrouter"
        model_name = "x-ai/grok-4.1-fast:free"
    end
    print("provider: " .. provider_name .. " - model: " .. model_name)

    local provider = config.opts.providers[provider_name]

    --build header
    local headers
    if provider.header then
        headers = provider.header()
    else
        headers = default_header(provider)
    end

    --build data
    local data
    if provider.data then
        data = provider.data(opts.settings, opts.messages, model_name, opts.stream)
    else
        data = default_data(opts.settings, opts.messages, model_name, opts.stream)
    end

    local curl_args = build_curl_args(provider.url, headers, data, opts.stream)

    local job = Job:new({
        command = "curl",
        args = curl_args,
        on_stdout = function(_, chunk)
            vim.schedule(function()
                -- local decoded = vim.inspect(chunk)
                -- local lines = vim.split(decoded, "\n", { plain = true })
                -- vim.api.nvim_buf_set_lines(0, -1, -1, false, lines)
                if chunk and chunk ~= "" then
                    local response
                    if provider.on_chunk then
                        response = provider.on_chunk(opts.stream, chunk)
                    else
                        response = default_on_stdout(opts.stream, chunk)
                    end
                    -- vim.api.nvim_buf_set_lines(
                    --     0,
                    --     -1,
                    --     -1,
                    --     false,
                    --     vim.split(vim.inspect(response), "\n", { plain = true })
                    -- )
                    if response ~= nil then
                        opts.response_callback(response)
                    end
                end
            end)
        end,
        on_stderr = function(_, err_data)
            vim.schedule(function()
                local decoded = vim.inspect(err_data)
                local lines = vim.split(decoded, "\n", { plain = true })
                -- vim.api.nvim_buf_set_lines(0, -1, -1, false, { "------ ON_STDERR " })
                -- vim.api.nvim_buf_set_lines(0, -1, -1, false, lines)
            end)
        end,
        on_exit = function(_, return_data)
            vim.schedule(function()
                -- local decoded = vim.inspect(return_data)
                -- local lines = vim.split(decoded, "\n", { plain = true })
                -- vim.api.nvim_buf_set_lines(0, -1, -1, false, { "------ ON_EXIT " })
                -- vim.api.nvim_buf_set_lines(0, -1, -1, false, lines)
                --
                opts.complete_callback()
            end)
        end,
    })

    job:start()
    return job
end

return M
