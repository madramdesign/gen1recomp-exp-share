-- Exp Share: always-on party experience.
--
-- Uses battle.exp_award — the engine's documented seam for replacing the
-- participant / EXP.ALL split (see BattleState:awardExp). Prefer this over
-- faking the EXP.ALL bag item so rematch XP scalers that wrap applyShare
-- still compose correctly when they sit outside this hook.

return function(mod)
  mod.options:define({
    {
      key = "mode",
      label = "EXP SHARE MODE",
      type = "choice",
      default = "modern",
      choices = {
        { "MODERN", "modern" },
        { "CLASSIC", "classic" },
        { "OFF", "off" },
      },
      description = "MODERN: full undivided EXP to every living party mon (Gen 6+). CLASSIC: Gen 1 EXP.ALL split without the item. OFF: vanilla (item required).",
    },
    {
      key = "announce",
      label = "EXP MESSAGES",
      type = "choice",
      default = "participants",
      choices = {
        { "FIGHTERS", "participants" },
        { "EVERYONE", "all" },
        { "SILENT", "none" },
      },
      description = "Which Pokémon show the 'gained EXP' text boxes. Bench shares can be silent to cut spam.",
    },
  })

  local function participantSet(ctx)
    local set = {}
    for _, mon in ipairs(ctx.alive or {}) do
      set[mon] = true
    end
    return set
  end

  local function shouldAnnounce(ctx, mon, fighters)
    local style = mod.options:get("announce") or "participants"
    if style == "none" then return false end
    if style == "all" then return true end
    -- participants / fighters only
    return fighters[mon] == true
  end

  -- Classic Gen 1 EXP.ALL: half the pool to fighters (div ×2), half to the
  -- whole living party (div × participants × partyCount × 2).
  local function awardClassic(ctx)
    local party = ctx.battle.game.save.party
    local nPart = math.max(1, ctx.participants or 1)
    local fighters = participantSet(ctx)

    for _, mon in ipairs(ctx.alive) do
      local ann = shouldAnnounce(ctx, mon, fighters)
      ctx.applyShare(mon, nPart * 2, ann and true or false)
    end

    local partyCount = #party
    for _, mon in ipairs(party) do
      if mon.hp and mon.hp > 0 then
        local ann = shouldAnnounce(ctx, mon, fighters)
        -- "expAll" picks the vanilla "with EXP.ALL," dialogue when announcing
        ctx.applyShare(mon, nPart * partyCount * 2, ann and "expAll" or false)
      end
    end
  end

  -- Modern: every living party member gets an undivided share (split = 1),
  -- the amount a sole participant would earn. Matches Gen 6+ Exp Share.
  local function awardModern(ctx)
    local party = ctx.battle.game.save.party
    local fighters = participantSet(ctx)

    for _, mon in ipairs(party) do
      if mon.hp and mon.hp > 0 then
        local ann = shouldAnnounce(ctx, mon, fighters)
        ctx.applyShare(mon, 1, ann and true or false)
      end
    end
  end

  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    local mode = mod.options:get("mode") or "modern"
    if mode == "off" or not ctx or not ctx.applyShare or not ctx.battle then
      return next(ctx)
    end
    if mode == "classic" then
      awardClassic(ctx)
      return
    end
    -- modern (default)
    awardModern(ctx)
  end)
end
