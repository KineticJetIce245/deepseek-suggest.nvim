--- Runtime state shared between the API layer and the status bar hint.
--- Tracks the connection status of the last API request so the status bar can
--- show green (connected), red (no API key) or yellow (no balance), plus the
--- accumulated token usage per model.

local M = {}

local state = { status = nil, usage = {}, cost = {} }

---@param kind nil|"ok"|"no_key"|"no_balance"|"error"
function M.set(kind)
  state.status = kind
end

---@return nil|"ok"|"no_key"|"no_balance"|"error"
function M.get()
  return state.status
end

--- Adds tokens and cost used by a model to the running totals.
---@param model string
---@param tokens? number
---@param cost? number estimated USD
function M.add_usage(model, tokens, cost)
  if not model then
    return
  end
  if tokens and tokens > 0 then
    state.usage[model] = (state.usage[model] or 0) + tokens
  end
  if cost and cost > 0 then
    state.cost[model] = (state.cost[model] or 0) + cost
  end
end

--- Total tokens used by a model in this session.
---@param model string
---@return number
function M.get_usage(model)
  return state.usage[model] or 0
end

--- Estimated cost (USD) used by a model in this session.
---@param model string
---@return number
function M.get_cost(model)
  return state.cost[model] or 0
end

--- All tracked models with their token/cost totals.
---@return table<string, { tokens: number, cost: number }>
function M.get_all()
  local all = {}
  local models = {}
  for model in pairs(state.usage) do
    models[model] = true
  end
  for model in pairs(state.cost) do
    models[model] = true
  end
  for model in pairs(models) do
    all[model] = { tokens = M.get_usage(model), cost = M.get_cost(model) }
  end
  return all
end

return M
