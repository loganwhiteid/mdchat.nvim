# MDchat.nvim

> [!WARNING]
> BOTH THE PLUGIN AND README ARE VERY MUCH A WORK IN PROGRESS
> CURRENT FEATURES ONLY FUNCTIONAL ON LINUX
> DEFAULT API CALLBACKS BUILT AROUND OPENROUTER

A basic LLM chat system using Markdown files as your active chat

No fancy chat UIs or Agentic capabilities, just parses the markdown file as a chat using the delimiters and sends to an API of your choice.
The response is then streamed into the file. Very similar to API playgrounds like OpenRouter Chat or Anthropic's Console.


Heavy inspiration and chunks of code from ![e-cal/chat.nvim](https://github.com/e-cal/chat.nvim)

### Purpose

I'm not a fan of agentic tools and prefer to use LLMs as a sounding board and for minor code generation.

Instead of using one of the many online chat app or a provider's API playground, I wanted something that lived in nvim that felt like an API playground which led me to e-cal's plugin.

After using it for a while I decided I wanted to make my own version as a way to learn nvim plugin development.

### Features

- [x] Change system settings on the fly manually or from user stored defaults
- [x] Modify chat history (changes or deletions)
- [ ] Use chat file in a full window or [!TODO] popup via nui
- [x] Uses OpenRouter API Schema by default but allows for manual configuration of other schemas
- [ ] Include OpenAI and Anthropic schemas
- [x] Clone current chat into new chat buffer (clone file, add `Cloned` tag to header)

## Installation

Using lazy.nvim

```lua
{
  "loganwhiteid/mdchat.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  opts = {
    -- your config, or leave empty for defaults
  }
}
```

## Configuration Options

### Chat Directories

|Name|Description|
|----|----|
|root_dir|root directory the other directories live under|
|chat_dir|directory inside `root_dir` where your chat files live|
|system_dir|directory inside `root_dir` where your system setting backups live|
|title_model|model alias to use when generating title header|
|show_snapshot|true/false write snapshot of settings used on next assistant header|

```lua
opts = {
  root_dir = vim.fn.stdpath("data") .. "/mdchat", -- root directory for the other to live under
  chat_dir = "/chats",
  system_dir = "/systems",
  title_model = "haiku",
  show_snapshot = true, -- Print snapshot of settings used at the end of Assistant header
}
```

### New Chat Default Settings

|Name|Description|
|----|----|
|title|The header title to use on line one (will be updated based on your chat convo)|
|model|Model alias (see models section for alias options)|
|temp|The Model's temperature (typically between 0.0 and 2.0)|
|reasoning|Should the model use Reasoning and at what level (nil, low, medium, high)|
|exlcude_reason|If reasoning is enabled, should the reasoning be excluded from the response (true, false)|
|history|how many chat message pairs should be included in the next request (nil: all messages, 0: only current)|
|system_message|System role message to be used in the request|

```lua
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
```

### Keymaps

**NOTE: Keymaps only used in the current chat buffer**

|Name|Description|
|----|----|
|send_message|normal mode keybind to send message|
|delete_chat|keymap to delete a chat file (while in Telescope menu)|
|stop_generation|keymap used to kill the current request and halt the SSE stream|
|jump_next_header|normal mode keybind for jumping to the next user or assistant header|
|jump_prev_header|normal mode keybind for jumping to the previous user or assistant header|

```lua
keymap = {
    send_message = "<CR>", -- normal mode keybind in chat windows to send message
    delete_chat = "<C-d>", -- keymap to delete a chat (in telescope menu)
    stop_generation = "<C-c>",
    jump_next_header = "]]", -- jumping to user and assistant headers
    jump_prev_header = "[[", -- jumping to user and assistant headers
},
```

### Chat buffer delimiters

**NOTE: Start of line values for each chat setting value**
|Name|Description|
|----|----|
|settings|Settings header flagging the start of the settings section|
|model|Start of line for the Model value|
|temp|Start of line for the temp value|
|reasoning|start of line for reasoning value|
|exclude_reason||
|history||
|system||
|chat|Chat header, flagging the start of the Chat section|
|user|User header, flagging the start of the next user request|
|assistant|Assistant header, flagging the start of the next response|

```lua
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
```

### providers

**Table of API providers and their unique settings**

|Name|Description|
|----|----|
|url|URL of the API endpoint|
|api_key|lua function returning a string of the API key to use|
|header|lua callback function for building the HTTP header, will be passed the parsed buffer, returns table of header key/values|
|data|lua callback function for building the HTTP data/body, will be passed the parsed buffer, returns table of body key/values|
|on_chunk|function to normalize the APIs SSE chunks. Will be passed a boolean if it's streamed, and the raw returned chunk. Needs to return a table of `{error: "", content: "", reason: ""}`|


[!TODO] Build table and example for each callback so users know params and returns

```lua
-- openrouter will use default header, data, and on_chunk callbacks
providers = {
  ["openrouter"] = {
      url = "https://openrouter.ai/api/v1/chat/completions",
      api_key = function()
          local f = assert(io.open(os.getenv("HOME") .. "/.chat/openrouter", "r"))
          local api_key = string.gsub(f:read("*all"), "\n", "")
          f:close()
          return api_key
      end,
  },
}
```

### models

**Table of model aliases**

Each model alias needs the following key values

|Name|Description|
|----|----|
|provider|Matching provider name from `Provider` config|
|model|Full model name used by the Provider|

```lua
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
```
