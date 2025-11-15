local config = require("mdchat.config")

local M = {}

-- build headers
--   bearer
--   content type
--   HTTP-Referer : site URL
--   X-Title: site name
-- build body/data
--   model
--   message
--   stream
--   reasoning = { effort = "low", exclude = true, enabled = true },
--   max_tokens
--   temperature

return M
