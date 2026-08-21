--- Runtime state shared between the API layer and the status bar hint.
--- Tracks the connection status of the last API request so the status bar can
--- show green (connected), red (no API key) or yellow (no balance), plus the
--- accumulated token usage per model.

local M = {}

local state = { status = nil, usage = {} }

---@param kind nil|"ok"|"no_key"|"no_balance"|"error"
function M.set(kind)
  state.status = kind
end

---@return nil|"ok"|"no_key"|"no_balance"|"error"
function M.get()
  return state.status
end

--- Adds tokens used by a model to the running total.
---@param model string
---@param tokens number
function M.add_usage(model, tokens)
  if not model or not tokens or tokens <= 0 then
    return
  end
  state.usage[model] = (state.usage[model] or 0) + tokens
end

--- Total tokens used by a model in this session.
---@param model string
---@return number
function M.get_usage(model)
  return state.usage[model] or 0
end

return M
