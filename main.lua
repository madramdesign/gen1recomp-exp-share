-- Exp Share: always-on party experience.
--
-- Current engines: BattleState.awardExp + optional battle.exp_award hook.
-- Older engines (0.1.38): EXP is inline in enemyMonFainted with no hook —
-- force the EXP.ALL inventory check (classic Gen 1 share math). True MODERN
-- undivided shares need a build that factors awardExp (0.1.39+ / recent).

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
      description = "MODERN: full EXP to every living party mon (needs newer gen1recomp). CLASSIC: Gen 1 EXP.ALL math. On older builds both use EXP.ALL. OFF: vanilla.",
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

  local function makeApplyShare(battle, shareFn)
    -- shareFn(mon, split, announce) — engine's ctx.applyShare when present
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
          -- StatBox is defined inside BattleState.lua (not a standalone module)
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
    battle.participants = {}
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
    battle.participants = {}
  end

  local function runAward(battle, shareFn)
    local participants, alive = countParticipants(battle)
    if getMode() == "classic" then
      awardClassic(battle, participants, alive, shareFn)
    else
      awardModern(battle, alive, shareFn)
    end
  end

  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    if getMode() == "off" or not ctx or not ctx.battle then
      return next(ctx)
    end
    runAward(ctx.battle, ctx.applyShare)
  end)

  local function withForcedExpAll(battle, fn)
    local inv = battle.game.save.inventory
    local had = inv.EXP_ALL
    inv.EXP_ALL = math.max(1, had or 0)
    local ok, err = pcall(fn)
    if not had or had == 0 then
      inv.EXP_ALL = had
    else
      inv.EXP_ALL = had
    end
    if not ok then error(err, 0) end
  end

  local function install()
    if installed then return end
    installed = true

    local BattleState = require("src.battle.BattleState")

    if BattleState.awardExp then
      local vanillaAward = BattleState.awardExp
      BattleState.awardExp = function(self)
        if getMode() == "off" then
          return vanillaAward(self)
        end
        runAward(self, nil)
      end
      mod.log:info("Exp Share ready (awardExp) — mode=%s", getMode())
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
