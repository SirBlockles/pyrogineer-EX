
# pyrogineer EX
pyrogineer EX is a redux of [a redux](https://forums.alliedmods.net/showthread.php?p=2708112) of [a plugin](https://forums.alliedmods.net/showthread.php?t=282110) that allows pyro to maintain engineer buildings with the homewrecker as if it were a wrench. extra focus was placed on making sure the mechanics behind the wrench features were as accurate to engineer's as possible, to create a consistent gameplay experience.

usually my gameplay plugins revolve around tweaking and improving game balance, and while the default settings make the homewrecker weaker than wrench (but can be easily changed to be just as good ;D), the entire concept of pyro being able to maintain engineer buildings is already fundamentally broken. this was primarily made for the hell of it and programming practice, simply because i wanted to have this functionality on my server. i'd imagine it could find a legitimate use in VSH or other "powered up" custom modes, though.
## features
* pyro can upgrade buildings. by default, pyro only contributes 20 metal per upgrade swing. this number is doubled during setup time and mannpower mode, just like the wrench.
* pyro can level up buildings by default, but this can be disabled. if disabled, the building will still be increased to 200/200 upgrade progress, but will require an engineer to hit it for it to actually level up.
* pyro can repair and heal buildings. it has the same metal cost as the wrench - 3 HP per metal when healing sentries and dispensers, and 5:1 when healing teleporters. it also rounds the same way and calculates cost the same way, so it should "feel right" to engineer players messing with it. it also correctly reduces incoming health to wrangled sentries and fires the heal event which displays the heal numbers.
* pyro can boost construction speed of buildings with the homewrecker. it has a -33% boost speed compared to the wrench by default (faster than the eureka effect still lol)
* order of operations is 1:1 with the default wrench - if a building is missing health, it will only be repaired. upgrading/leveling/reloading will only take place if the building is full health on hit.
* when a building takes damage from full health, the alert sound is played out loud from it that can only be heard by friendly pyros with the homewrecker.
### note about metal
every class besides engineer has **100 metal** by default - including pyro. the old versions of this plugin increased the metal capacity, but this one doesn't. [TF2Items](https://forums.alliedmods.net/showthread.php?t=115100)'s default item manager, combined with the vanilla [metal capacity attribute](https://csrd.science/misc/econ-tf/attributes.html#80) will Just Work<sup>TM</sup> with this plugin and allow you to increase/decrease pyro's metal capacity. i also recommend adding the [melee range multiplier](https://csrd.science/misc/econ-tf/attributes.html#264) attribute with a value of 1.2-1.25 or so, so that pyros can work on teleporters without having to stand on them and crouch to the side. engineer's wrench seems to have a range of about 1.3 when working on buildings, probably for the same reason.
## dependencies
* [DHooks](https://github.com/peace-maker/DHooks2) (comes installed by default in SM 1.11)
* nosoop's [CustomStatusHUD](https://github.com/nosoop/SM-CustomStatusHUD) for metal HUD
## cvars & configuration
values in `[brackets]` are the default for the CVAR
##### upgrading & leveling
`sm_pyrogineer_allow_upgrade <0/[1]>` - whether or not pyros should be allowed to contribute upgrade progress to buildings.

`sm_pyrogineer_allow_levelup <0/[1]>` - if this is set to 0 but allow upgrade is set to 1, pyros can only upgrade buildings to 200/200 and an engineer must hit the building to upgrade it. if a building is at 200/200, engineers can upgrade it with a single hit even with 0 metal.

`sm_pyrogineer_upgrade_rate <20>` - how much metal to contribute to a building every swing. note that just like engineer, this is doubled during setup time and mannpower mode.
##### repairing
`sm_pyrogineer_allow_repair <0/[1]>` - allows pyro to heal buildings. sentries and dispensers cost 1 metal per 3 HP, and teleporters cost 1 metal per 5 HP.

`sm_pyrogineer_repair_rate <45>` - target HP to contribute to buildings. engineer's value is 100, for comparison. note that this rounds up - a value of 100 heals 102 for sentries/dispensers, just like engineer.
##### construction boosting
`sm_pyrogineer_allow_buildspeed <0/[1]>` - allows pyro to construction-boost buildings to build them faster.

`sm_pyrogineer_build_speed_mult <1.0>` - how much construction boost to add to constructing buildings. engineer's value is 1.5. note that build speed is ADDITIVE, not multiplicative. a value of 1.0 essentially is a -33% build speed penalty from stock wrench. for comparison, eureka effect is 0.75, and jag is 1.95.
##### restocking sentries
`sm_pyrogineer_allow_restock <0/1/[2]>` - whether or not pyros should be allowed to restock ammo to sentryguns. 0 = not at all, 1 = bullets only, 2 = bullets + rockets

`sm_pyrogineer_restock_bullets <30>` - how many shells (bullets) to restock per swing. engineer's value is 40, lv.1/mini sentries have a capacity of 150, lv.2/lv.3 have 200. 1 shell costs 1 metal. (same as engineer)

`sm_pyrogineer_restock_rockets <4>` - how many rockets to restock per swing. engineer's value is 8. lv.3 sentries hold up to 20 rockets. rockets cost 2 metal each. (same as engineer)
##### misc
`sm_pyrogineer_neon_annihilator <[0]/1>` - if enabled, the neon annihilator will also be given wrench capability. otherwise, it's only granted to the homewrecker/maul.

`sm_pyrogineer_alertsound <0/[1]>` - if enabled, when a building takes damage for the first time after being at full health, it'll play the HUD alert sound that can be heard by nearby pyros wielding a homewrecker.
