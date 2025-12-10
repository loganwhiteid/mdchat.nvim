# MDchat.nvim

A basic LLM chat system using Markdown files as your active chat

No fancy chat UIs or Agentic capabilities, just parses the markdown file as a chat using the delimiters and sends to an API of your choice.
The response is then streamed into the file. Very similar to API playgrounds like OpenRouter Chat or Anthropic's Console.


Heavy inspiration and chunks of code from ![e-cal/chat.nvim](https://github.com/e-cal/chat.nvim)

### Purpose

I don't like agentic tools and prefer to use LLMs as a sounding board and boilerplate.
Instead of using one of the many online chat app or a provider's API playground, I wanted something that lived in nvim that felt like
an API playground which led me to e-cal's plugin. After using it for a while I decided I wanted to make my own version as a way to learn 
nvim plugin development.

### Features

- Change system settings on the fly manually or from user stored defaults
- Modify chat history (changes or deletions)
- Use chat file in a full window or popup via nui
- Uses OpenAI API Schema by default but allows for manual configuration of other schemas

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

## Usage



## Configuration Options



## API Keys

It is recommended to either export your api keys in your shell environment and
use the api key functions as they are, or define your own.

For example, if you have your openai api key stored as text files on your system you might change the function to:

```lua
api_keys = {
  openai = function()
    local f = assert(io.open(os.getenv("HOME") .. "/<path to key>", "r"))
    local api_key = string.gsub(f:read("*all"), "\n", "")
    f:close()
    return api_key
  end,
}
```
