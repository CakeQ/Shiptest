/obj/item/gun/energy
	icon_state = "energy"
	name = "energy gun"
	desc = "A basic energy-based gun."
	icon = 'icons/obj/guns/energy.dmi'

	muzzleflash_iconstate = "muzzle_flash_laser"
	muzzle_flash_color = COLOR_SOFT_RED

	has_safety = TRUE
	safety = TRUE

	gun_firemodes = list(FIREMODE_SEMIAUTO)
	default_firemode = FIREMODE_SEMIAUTO

	fire_select_icon_state_prefix = "laser_"

	var/obj/item/stock_parts/cell/gun/cell //What type of power cell this uses
	var/cell_type = /obj/item/stock_parts/cell/gun
	var/modifystate = 0
	var/list/ammo_type = list(/obj/item/ammo_casing/energy)
	var/select = 1 //The state of the select fire switch. Determines from the ammo_type list what kind of shot is fired next.
	var/can_charge = TRUE //Can it be charged in a recharger?
	var/automatic_charge_overlays = TRUE	//Do we handle overlays with base update_appearance()?
	var/charge_sections = 4
	ammo_x_offset = 2
	var/shaded_charge = FALSE //if this gun uses a stateful charge bar for more detail
	var/selfcharge = 0
	var/charge_tick = 0
	var/charge_delay = 4
	var/use_cyborg_cell = FALSE //whether the gun's cell drains the cyborg user's cell to recharge
	var/dead_cell = FALSE //set to true so the gun is given an empty cell

	var/internal_cell = FALSE ///if the gun's cell cannot be replaced
	var/small_gun = FALSE ///if the gun is small and can only fit the small gun cell
	var/big_gun = FALSE ///if the gun is big and can fit the comically large gun cell
	var/unscrewing_time = 20 ///Time it takes to unscrew the cell

	///Whether the gun can be tacloaded by slapping a fresh magazine directly on it
	var/tac_reloads = FALSE
	///If we allow tacitcal reloads, how long should it take to reload?
	var/tactical_reload_delay  = 1.2 SECONDS

	var/load_sound = 'sound/weapons/gun/general/magazine_insert_full.ogg' //Sound when inserting magazine. UPDATE PLEASE
	var/eject_sound = 'sound/weapons/gun/general/magazine_remove_full.ogg' //Sound of ejecting a cell. UPDATE PLEASE
	var/sound_volume = 40 //Volume of loading/unloading sounds
	var/load_sound_vary = TRUE //Should the load/unload sounds vary?

/obj/item/gun/energy/emp_act(severity)
	. = ..()
	if(!(. & EMP_PROTECT_CONTENTS))
		cell.use(round(cell.charge / severity))
		chambered = null //we empty the chamber
		recharge_newshot() //and try to charge a new shot
		update_appearance()

/obj/item/gun/energy/get_cell()
	return cell

/obj/item/gun/energy/Initialize()
	. = ..()
	if(cell_type)
		cell = new cell_type(src)
	else
		cell = new(src)
	if(!dead_cell)
		cell.give(cell.maxcharge)
	update_ammo_types()
	recharge_newshot(TRUE)
	if(selfcharge)
		START_PROCESSING(SSobj, src)
	update_appearance()

/obj/item/gun/energy/ComponentInitialize()
	. = ..()
	AddElement(/datum/element/update_icon_updates_onmob)

/obj/item/gun/energy/proc/update_ammo_types()
	var/obj/item/ammo_casing/energy/shot
	for (var/i = 1, i <= ammo_type.len, i++)
		var/shottype = ammo_type[i]
		shot = new shottype(src)
		ammo_type[i] = shot
	shot = ammo_type[select]
	fire_sound = shot.fire_sound
	fire_delay = shot.delay

/obj/item/gun/energy/Destroy()
	if (cell)
		QDEL_NULL(cell)
	STOP_PROCESSING(SSobj, src)
	. = ..()
	ammo_type.Cut()

/obj/item/gun/energy/handle_atom_del(atom/A)
	if(A == cell)
		cell = null
		update_appearance()
	return ..()

/obj/item/gun/energy/process()
	if(selfcharge && cell && cell.percent() < 100)
		charge_tick++
		if(charge_tick < charge_delay)
			return
		charge_tick = 0
		cell.give(1000) //WS Edit - Egun energy cells
		if(!chambered) //if empty chamber we try to charge a new shot
			recharge_newshot(TRUE)
		update_appearance()

//ATTACK HAND IGNORING PARENT RETURN VALUE
/obj/item/gun/energy/attack_hand(mob/user)
	if(!internal_cell && loc == user && user.is_holding(src) && cell && tac_reloads)
		eject_cell(user)
		return
	return ..()

/obj/item/gun/energy/unique_action(mob/living/user)
	if(ammo_type.len > 1)
		select_fire(user)
		update_appearance()

/obj/item/gun/energy/attackby(obj/item/A, mob/user, params)
	if (!internal_cell && istype(A, /obj/item/stock_parts/cell/gun))
		var/obj/item/stock_parts/cell/gun/C = A
		if (!cell)
			insert_cell(user, C)
		else
			if (tac_reloads)
				eject_cell(user, C)

	return ..()

/obj/item/gun/energy/proc/insert_cell(mob/user, obj/item/stock_parts/cell/gun/C)
	if(small_gun && !istype(C, /obj/item/stock_parts/cell/gun/mini))
		to_chat(user, "<span class='warning'>\The [C] doesn't seem to fit into \the [src]...</span>")
		return FALSE
	if(!big_gun && istype(C, /obj/item/stock_parts/cell/gun/large))
		to_chat(user, "<span class='warning'>\The [C] doesn't seem to fit into \the [src]...</span>")
		return FALSE
	if(user.transferItemToLoc(C, src))
		cell = C
		to_chat(user, "<span class='notice'>You load the [C] into \the [src].</span>")
		playsound(src, load_sound, sound_volume, load_sound_vary)
		update_appearance()
		return TRUE
	else
		to_chat(user, "<span class='warning'>You cannot seem to get \the [src] out of your hands!</span>")
		return FALSE

/obj/item/gun/energy/proc/eject_cell(mob/user, obj/item/stock_parts/cell/gun/tac_load = null)
	playsound(src, load_sound, sound_volume, load_sound_vary)
	cell.forceMove(drop_location())
	var/obj/item/stock_parts/cell/gun/old_cell = cell
	old_cell.update_appearance()
	cell = null
	to_chat(user, "<span class='notice'>You pull the cell out of \the [src].</span>")
	update_appearance()
	if(tac_load && tac_reloads)
		if(do_after(user, tactical_reload_delay, src, hidden = TRUE))
			if(insert_cell(user, tac_load))
				to_chat(user, "<span class='notice'>You perform a tactical reload on \the [src].</span>")
			else
				to_chat(user, "<span class='warning'>You dropped the old cell, but the new one doesn't fit. How embarassing.</span>")
		else
			to_chat(user, "<span class='warning'>Your reload was interupted!</span>")
			return

	user.put_in_hands(old_cell)
	update_appearance()

/obj/item/gun/energy/get_gun_attachments()
	if(cell && !internal_cell)
		attachment_options += list("Cell" = image(icon = cell.icon, icon_state = cell.icon_state))
	..()

/obj/item/gun/energy/remove_gun_attachments(mob/living/user, obj/item/I, picked_option)
	if(picked_option == "Cell")
		if(I.use_tool(src, user, unscrewing_time, volume=100))
			eject_cell(user, I)
			return TRUE
	..()

/obj/item/gun/energy/can_shoot(visuals)
	if(safety && !visuals)
		return FALSE
	var/obj/item/ammo_casing/energy/shot = ammo_type[select]
	return !QDELETED(cell) ? (cell.charge >= shot.e_cost) : FALSE

/obj/item/gun/energy/recharge_newshot(no_cyborg_drain)
	if (!ammo_type || !cell)
		return
	if(use_cyborg_cell && !no_cyborg_drain)
		if(!iscyborg(loc))
			return
		var/mob/living/silicon/robot/R = loc
		if(!R.cell)
			return
		var/obj/item/ammo_casing/energy/shot = ammo_type[select] //Necessary to find cost of shot
		if(!R.cell.use(shot.e_cost)) 		//Take power from the borg...
			shoot_with_empty_chamber(R)
			return
		cell.give(shot.e_cost)	//... to recharge the shot
	if(!chambered)
		var/obj/item/ammo_casing/energy/AC = ammo_type[select]
		if(cell.charge >= AC.e_cost) //if there's enough power in the cell cell...
			chambered = AC //...prepare a new shot based on the current ammo type selected
			if(!chambered.BB)
				chambered.newshot()

/obj/item/gun/energy/process_chamber(atom/shooter)
	if(chambered && !chambered.BB) //if BB is null, i.e the shot has been fired...
		var/obj/item/ammo_casing/energy/shot = chambered
		cell.use(shot.e_cost)//... drain the cell cell
	chambered = null //either way, released the prepared shot
	recharge_newshot() //try to charge a new shot
	SEND_SIGNAL(src, COMSIG_GUN_CHAMBER_PROCESSED)

/obj/item/gun/energy/process_fire(atom/target, mob/living/user, message = TRUE, params = null, zone_override = "", bonus_spread = 0)
	if(!chambered && can_shoot())
		process_chamber()	// If the gun was drained and then recharged, load a new shot.
	return ..()

/obj/item/gun/energy/proc/select_fire(mob/living/user)
	select++
	if (select > ammo_type.len)
		select = 1
	var/obj/item/ammo_casing/energy/shot = ammo_type[select]
	fire_sound = shot.fire_sound
	fire_delay = shot.delay
	if (shot.select_name)
		to_chat(user, "<span class='notice'>[src] is now set to [shot.select_name].</span>")
	chambered = null
	playsound(user, 'sound/weapons/gun/general/selector.ogg', 100, TRUE)
	recharge_newshot(TRUE)
	update_appearance()
	return

/obj/item/gun/energy/update_icon_state()
	if(initial(item_state))
		return ..()
	var/ratio = get_charge_ratio()
	var/new_item_state = ""
	new_item_state = initial(icon_state)
	if(modifystate)
		var/obj/item/ammo_casing/energy/shot = ammo_type[select]
		new_item_state += "[shot.select_name]"
	new_item_state += "[ratio]"
	item_state = new_item_state
	return ..()

/obj/item/gun/energy/update_overlays()
	. = ..()
	if(!automatic_charge_overlays || QDELETED(src))
		return
	// Every time I see code this "flexible", a kitten fucking dies //it got worse
	//todo: refactor this a bit to allow showing of charge on a gun's cell
	var/overlay_icon_state = "[icon_state]_charge"
	var/obj/item/ammo_casing/energy/shot = ammo_type[modifystate ? select : 1]
	var/ratio = get_charge_ratio()
	if(cell)
		. += "[icon_state]_cell"
		if(ratio == 0)
			. += "[icon_state]_cellempty"
	if(ratio == 0)
		if(modifystate)
			. += "[icon_state]_[shot.select_name]"
		. += "[icon_state]_empty"
	else
		if(!shaded_charge)
			if(modifystate)
				. += "[icon_state]_[shot.select_name]"
				overlay_icon_state += "_[shot.select_name]"
			var/mutable_appearance/charge_overlay = mutable_appearance(icon, overlay_icon_state)
			for(var/i = ratio, i >= 1, i--)
				charge_overlay.pixel_x = ammo_x_offset * (i - 1)
				charge_overlay.pixel_y = ammo_y_offset * (i - 1)
				. += new /mutable_appearance(charge_overlay)
		else
			if(modifystate)
				. += "[icon_state]_charge[ratio]_[shot.select_name]" //:drooling_face:
			else
				. += "[icon_state]_charge[ratio]"

///Used by update_icon_state() and update_overlays()
/obj/item/gun/energy/proc/get_charge_ratio()
	return can_shoot(visuals = TRUE) ? CEILING(clamp(cell.charge / cell.maxcharge, 0, 1) * charge_sections, 1) : 0
	// Sets the ratio to 0 if the gun doesn't have enough charge to fire, or if its power cell is removed.

/obj/item/gun/energy/vv_edit_var(var_name, var_value)
	switch(var_name)
		if(NAMEOF(src, selfcharge))
			if(var_value)
				START_PROCESSING(SSobj, src)
			else
				STOP_PROCESSING(SSobj, src)
	. = ..()


/obj/item/gun/energy/ignition_effect(atom/A, mob/living/user)
	if(!can_shoot() || !ammo_type[select])
		shoot_with_empty_chamber()
		. = ""
	else
		var/obj/item/ammo_casing/energy/E = ammo_type[select]
		var/obj/projectile/energy/BB = E.BB
		if(!BB)
			. = ""
		else if(BB.nodamage || !BB.damage || BB.damage_type == STAMINA)
			user.visible_message("<span class='danger'>[user] tries to light [user.p_their()] [A.name] with [src], but it doesn't do anything. Dumbass.</span>")
			playsound(user, E.fire_sound, 50, TRUE)
			playsound(user, BB.hitsound_non_living, 50, TRUE)
			cell.use(E.e_cost)
			. = ""
		else if(BB.damage_type != BURN)
			user.visible_message("<span class='danger'>[user] tries to light [user.p_their()] [A.name] with [src], but only succeeds in utterly destroying it. Dumbass.</span>")
			playsound(user, E.fire_sound, 50, TRUE)
			playsound(user, BB.hitsound_non_living, 50, TRUE)
			cell.use(E.e_cost)
			qdel(A)
			. = ""
		else
			playsound(user, E.fire_sound, 50, TRUE)
			playsound(user, BB.hitsound_non_living, 50, TRUE)
			cell.use(E.e_cost)
			. = "<span class='danger'>[user] casually lights their [A.name] with [src]. Damn.</span>"


/obj/item/gun/energy/examine(mob/user)
	. = ..()
	if(ammo_type.len > 1)
		. += "You can switch firemodes by pressing the <b>unqiue action</b> key. By default, this is <b>space</b>"
