-- Shared helpers. Lua 5.0: no `#`, no `%` operator, no `select`, no string.gmatch.

WowLogsAS = WowLogsAS or {}
local A = WowLogsAS

A.version = "0.2.2"
A.schema = 2
A.exportVersion = 2

--- Call a game API by name with an exact argument count. Several AZS_ calls reject extra
--- arguments, even nil ones, so `n` is explicit. Returns value, error table.
function A.Native(name, n, a, b, c)
    local fn = getglobal(name)
    if type(fn) ~= "function" then
        return nil, { code = "MISSING" }
    end
    local ok, value, err
    if n == 0 then
        ok, value, err = pcall(fn)
    elseif n == 1 then
        ok, value, err = pcall(fn, a)
    elseif n == 2 then
        ok, value, err = pcall(fn, a, b)
    else
        ok, value, err = pcall(fn, a, b, c)
    end
    if not ok then
        return nil, { code = "EXCEPTION", message = tostring(value) }
    end
    return value, err
end

--- Bounded deep copy of plain data. Functions and other non-data values are dropped.
function A.Copy(value, depth, budget)
    local kind = type(value)
    if kind == "string" then
        return string.sub(value, 1, 512)
    end
    if kind == "number" or kind == "boolean" then
        return value
    end
    if kind ~= "table" then
        return nil
    end
    budget = budget or { left = 4000 }
    depth = depth or 6
    if depth <= 0 or budget.left <= 0 then
        return nil
    end
    local out = {}
    for k, v in pairs(value) do
        if budget.left <= 0 then
            out.truncated = true
            break
        end
        if type(k) == "string" or type(k) == "number" then
            budget.left = budget.left - 1
            local copied = A.Copy(v, depth - 1, budget)
            if copied ~= nil then
                out[k] = copied
            end
        end
    end
    return out
end

--- Keep only the scalar fields of a table.
function A.Scalars(source)
    local out = {}
    if type(source) ~= "table" then
        return out
    end
    for k, v in pairs(source) do
        local kind = type(v)
        if type(k) == "string" and (kind == "number" or kind == "string" or kind == "boolean") then
            out[k] = A.Copy(v)
        end
    end
    return out
end

function A.Wall()
    return type(time) == "function" and time() or nil
end

function A.Round(value, places)
    if type(value) ~= "number" or value ~= value then
        return nil
    end
    local scale = 1
    for _ = 1, places or 0 do
        scale = scale * 10
    end
    return math.floor(value * scale + 0.5) / scale
end

function A.Count(map)
    local n = 0
    for _ in pairs(map) do
        n = n + 1
    end
    return n
end

--- Rough saved size in bytes, close enough to keep the file bounded.
function A.Size(value)
    local kind = type(value)
    if kind == "string" then
        return string.len(value) + 3
    end
    if kind ~= "table" then
        return 8
    end
    local total = 2
    for k, v in pairs(value) do
        total = total + A.Size(k) + A.Size(v) + 4
    end
    return total
end

function A.Say(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffWoW Logs AS:|r " .. text)
    end
end
