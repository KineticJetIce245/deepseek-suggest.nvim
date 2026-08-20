local mock = {}

local state = {
  providers = {},
  shown = nil,
  accepted = false,
}

function mock.add_source_provider(id, cfg)
  assert(state.providers[id] == nil, "Provider with id " .. id .. " already exists")
  state.providers[id] = cfg
end

function mock.show(opts)
  state.shown = opts
  return true
end

function mock.get_selected_item()
  return nil
end

function mock.accept(_)
  state.accepted = true
  return true
end

mock._state = state

return mock
