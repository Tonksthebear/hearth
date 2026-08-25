-- @template Rails Worktree Lifecycle
-- @description Link Hearth's local Tailwind Plus reference into new worktrees
-- @category plugins
-- @dest plugins/rails-worktree-lifecycle/init.lua
-- @scope repo
-- @version 1.0.0

local hooks = require("hub.hooks")

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function source_repo(ctx)
    return ctx.repo
        or (ctx.metadata and ctx.metadata.target_path)
        or worktree.repo_root()
end

local function link_reference(ctx)
    local repo_root = source_repo(ctx)
    if not repo_root then
        log.warn("[rails-worktree-lifecycle] Could not resolve Hearth's source checkout")
        return
    end

    local source = repo_root .. "/reference"
    local destination = ctx.path .. "/reference"

    if not fs.exists(source) then
        log.warn("[rails-worktree-lifecycle] Missing shared reference directory at " .. source)
        return
    end

    if fs.exists(destination) then
        log.info("[rails-worktree-lifecycle] reference already exists in " .. ctx.path)
        return
    end

    local ok = os.execute("ln -s " .. shell_quote(source) .. " " .. shell_quote(destination))
    if ok == true or ok == 0 then
        log.info("[rails-worktree-lifecycle] Linked reference into " .. ctx.path)
    else
        log.warn("[rails-worktree-lifecycle] Could not link reference into " .. ctx.path)
    end
end

hooks.on("worktree_created", "rails-worktree-lifecycle.reference", function(ctx)
    local ok, err = pcall(link_reference, ctx)
    if not ok then
        log.warn("[rails-worktree-lifecycle] worktree_created error: " .. tostring(err))
    end
end)

log.info("[rails-worktree-lifecycle] Hearth plugin loaded")

return {}
