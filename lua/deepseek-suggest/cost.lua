--- Cost estimation for the accumulated API usage.
---
--- DeepSeek returns an exact token breakdown per request
--- (`prompt_cache_hit_tokens`, `prompt_cache_miss_tokens`, `completion_tokens`),
--- so the cost is `tokens / 1e6 * price`. The per-model prices are NOT bundled:
--- they must be supplied by the user via `opts.pricing`. Without a pricing entry
--- for the active model no cost is tracked and nothing is shown.
---
--- Prices are USD per 1M tokens (off-peak base). During peak hours the off-peak
--- base is doubled. Peak hours are 01:00-04:00 and 06:00-10:00 UTC, and — since
--- 2026-08-23 — weekends (Beijing time) are off-peak all day.

local M = {}

--- Whether the given Unix timestamp (defaults to now) falls in a peak window.
---@param timestamp? number
---@return boolean
function M.is_peak(timestamp)
  local t = timestamp or os.time()
  -- weekend in Beijing time (UTC+8) -> off-peak all day
  local bj_weekday = tonumber(os.date("%u", t + 8 * 3600))
  if bj_weekday == 6 or bj_weekday == 7 then
    return false
  end
  local hour = tonumber(os.date("!%H", t))
  return (hour >= 1 and hour < 4) or (hour >= 6 and hour < 10)
end

--- Rates for a model from the user-provided `pricing` table, or nil when no
--- pricing is configured for it.
---@param pricing table
---@param model string
---@return { input_cache_hit: number, input_cache_miss: number, output: number }?
function M.rates(pricing, model)
  if type(pricing) ~= "table" then
    return nil
  end
  local rates = pricing[model]
  if type(rates) ~= "table" then
    return nil
  end
  return {
    input_cache_hit = rates.input_cache_hit or rates.input or 0,
    input_cache_miss = rates.input_cache_miss or rates.input or 0,
    output = rates.output or 0,
  }
end

--- Estimates the cost in USD of a request from its usage object.
--- Returns nil when no pricing is configured for the model.
---@param usage { prompt_tokens?: number, prompt_cache_hit_tokens?: number, prompt_cache_miss_tokens?: number, completion_tokens?: number, total_tokens?: number }?
---@param pricing table user-provided `opts.pricing`
---@param model string
---@param peak? boolean when nil, `pricing_peak` decides; when given, forces it
---@return number?
function M.compute_cost(usage, pricing, model, peak)
  local rates = M.rates(pricing, model)
  if not rates or not usage then
    return nil
  end
  local miss = usage.prompt_cache_miss_tokens or usage.prompt_tokens or 0
  local hit = usage.prompt_cache_hit_tokens or 0
  local out = usage.completion_tokens
    or math.max(0, (usage.total_tokens or 0) - (usage.prompt_tokens or 0))
  local cost = miss / 1e6 * rates.input_cache_miss + hit / 1e6 * rates.input_cache_hit
    + out / 1e6 * rates.output
  if peak == nil then
    peak = M.is_peak()
  end
  if peak then
    cost = cost * 2
  end
  return cost
end

--- Formats a cost as USD with two decimal places.
---@param cost number
---@return string
function M.format_cost(cost)
  if not cost or cost <= 0 then
    return "$0.00"
  end
  return string.format("$%.2f", cost)
end

return M
