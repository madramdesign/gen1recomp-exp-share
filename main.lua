-- Exp Share: always-on party experience.
--
-- Current engines (awardExp + battle.exp_award, ~0.1.39+ / 0.1.75):
--   wrap the official hook and reuse ctx.applyShare so level-up HUD,
--   Cont text, and catch-exp stay in sync with the engine.
-- Older engines (0.1.38): EXP is inline in enemyMonFainted with no hook —
--   force the EXP.ALL inventory check (classic Gen 1 share math).

return function(mod)
  local Experience = require("src.battle.Experience")
  local Runtime = require("src.mods.Runtime")
  local Strings = require("src.core.Strings")

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
      description = "MODERN: full EXP to every living party mon (needs gen1recomp with battle.exp_award). CLASSIC: Gen 1 EXP.ALL math. On 0.1.38 both use EXP.ALL. OFF: vanilla.",
    },
    {
      key = "announce",
      label = "EXP MESSAGES",
      type = "choice",
      default = "all",
      choices = {
        { "EVERYONE", "all" },
        { "FIGHTERS", "participants" },
        { "SILENT", "none" },
      },
      description = "Who gets the 'gained EXP' text boxes. EVERYONE makes sharing obvious.",
    },
  })

  local installed = false

  local function getMode()
    return mod.options:get("mode") or "modern"
  end

  local function participantSet(alive)
    local set = {}
    for _, mon in ipairs(alive or {}) do
      set[mon] = true
    end
    return set
  end

  local function shouldAnnounce(mon, fighters)
    local style = mod.options:get("announce") or "all"
    if style == "none" then return false end
    if style == "all" then return true end
    return fighters[mon] == true
  end

  local function countParticipants(battle)
    local participants, alive = 0, {}
    for _, mon in ipairs(battle.game.save.party) do
      if battle.participants and battle.participants[mon] then
        participants = participants + 1
        if mon.hp > 0 then table.insert(alive, mon) end
      end
    end
    if participants == 0 and battle.player and battle.player.mon
       and battle.player.mon.hp > 0 then
      participants, alive = 1, { battle.player.mon }
    end
    return participants, alive
  end

  -- Fallback applyShare for engines that expose awardExp but not the hook
  -- context (should be rare). Prefer ctx.applyShare from battle.exp_award.
  local function makeApplyShare(battle, shareFn)
    if shareFn then
      return function(mon, split, announce)
        return shareFn(mon, split, announce)
      end
    end
    return function(mon, split, announce)
      local levels, gained = Experience.apply(
        battle.data, mon, battle.enemy.def,
        battle.enemy.mon.level, battle.kind == "trainer",
        split, mon.traded)

      if #levels > 0 then
        battle.leveledUp = battle.leveledUp or {}
        battle.leveledUp[mon] = true
      end
      Runtime.emit("battle.exp_gained", {
        battle = battle, mon = mon, gained = gained, levels = levels,
      })

      local name = mon.nickname or battle.data.pokemon[mon.species].name
      if announce then
        local text = Strings.source("%s gained\n%d EXP. Points!")
        if announce == "expAll" then
          text = Strings.source("%s gained\nwith EXP.ALL,\v%d EXP. Points!")
        elseif mon.traded then
          text = Strings.source("%s gained\na boosted\v%d EXP. Points!")
        end
        battle:sayNext(Strings(text, name, gained))
      end

      local game = battle.game
      for _, lv in ipairs(levels) do
        require("src.world.PikachuFollower")
          .modifyHappiness(game.save, "LEVELUP", mon)
        battle:sayNext(Strings("%s grew\nto level %d!", name, lv))
        battle:uiNext(function()
          require("src.core.Sound").play(game.data, "Level_Up")
          local BattleState = require("src.battle.BattleState")
          return BattleState.StatBox.new(game, mon)
        end)
        if battle.player and mon == battle.player.mon then
          battle:drainNext()
        end
        for _, moveId in ipairs(Experience.movesLearnedAt(
            battle.data.pokemon[mon.species], lv)) do
          battle:learnMove(mon, moveId)
        end
      end
    end
  end

  local function awardModern(battle, alive, shareFn)
    local apply = makeApplyShare(battle, shareFn)
    local fighters = participantSet(alive)
    for _, mon in ipairs(battle.game.save.party) do
      if mon.hp and mon.hp > 0 then
        local ann = shouldAnnounce(mon, fighters)
        apply(mon, 1, ann and true or false)
      end
    end
  end

  local function awardClassic(battle, participants, alive, shareFn)
    local apply = makeApplyShare(battle, shareFn)
    local fighters = participantSet(alive)
    local nPart = math.max(1, participants or 1)
    local party = battle.game.save.party

    for _, mon in ipairs(alive) do
      local ann = shouldAnnounce(mon, fighters)
      apply(mon, nPart * 2, ann and true or false)
    end
    for _, mon in ipairs(party) do
      if mon.hp and mon.hp > 0 then
        local ann = shouldAnnounce(mon, fighters)
        apply(mon, nPart * #party * 2, ann and "expAll" or false)
      end
    end
  end

  local function runAward(battle, shareFn, participants, alive)
    if not participants then
      participants, alive = countParticipants(battle)
    end
    if getMode() == "classic" then
      awardClassic(battle, participants, alive, shareFn)
    else
      awardModern(battle, alive, shareFn)
    end
  end

  -- Preferred path on current engines: awardExp always calls this hook.
  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    if getMode() == "off" or not ctx or not ctx.battle then
      return next(ctx)
    end
    runAward(ctx.battle, ctx.applyShare, ctx.participants, ctx.alive)
  end)

  local function withForcedExpAll(battle, fn)
    local inv = battle.game.save.inventory
    local had = inv.EXP_ALL
    inv.EXP_ALL = math.max(1, had or 0)
    local ok, err = pcall(fn)
    inv.EXP_ALL = had
    if not ok then error(err, 0) end
  end

  local function install()
    if installed then return end
    installed = true

    local BattleState = require("src.battle.BattleState")

    -- Engines with awardExp already invoke battle.exp_award above.
    -- Do not monkey-patch awardExp — that would bypass the engine's
    -- applyShare (level-up HUD / Cont text / catch-exp fixes).
    if BattleState.awardExp then
      mod.log:info("Exp Share ready (battle.exp_award) — mode=%s", getMode())
      return
    end

    -- Legacy path (0.1.38): always-on classic EXP.ALL via the bag check.
    local vanillaFainted = BattleState.enemyMonFainted
    BattleState.enemyMonFainted = function(self)
      if getMode() == "off" then
        return vanillaFainted(self)
      end
      withForcedExpAll(self, function()
        return vanillaFainted(self)
      end)
    end

    mod.log:info(
      "Exp Share ready (legacy EXP.ALL) — update gen1recomp for MODERN undivided EXP")
  end

  mod.events:on("game.ready", function()
    install()
  end)
end
