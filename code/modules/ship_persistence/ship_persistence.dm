GLOBAL_LIST_EMPTY(ships_to_update)
GLOBAL_PROTECT(ships_to_update)

/datum
	var/load_contents = FALSE
	var/should_save = TRUE
	var/persistent_vars = "datum_components"
	var/safe_list_vars = ""

/datum/proc/after_load()
	return

/datum/proc/before_save()
	return

/datum/proc/get_saved_vars()
	var/list/to_save = list()
	to_save |= params2list(persistent_vars)
	var/A = src.type
	var/B = replacetext("[A]", "/", "-")
	var/savedvarparams = file2text("saved_vars/[B].txt")
	if(!savedvarparams)
		savedvarparams = ""
	var/list/savedvars = params2list(savedvarparams)
	if(savedvars && savedvars.len)
		for(var/v in savedvars)
			if(findtext(v, "\n"))
				var/list/split2 = splittext(v, "\n")
				to_save |= split2[1]
			else
				to_save |= v
	var/list/found_vars = list()
	var/list/split = splittext(B, "-")
	var/list/subtypes = list()
	if(split && split.len)
		for(var/x in split)
			if(x == "") continue
			var/subtypes_text = ""
			for(var/xa in subtypes)
				subtypes_text += "-[xa]"
			var/savedvarparamss = file2text("saved_vars/[subtypes_text]-[x].txt")
			var/list/saved_vars = params2list(savedvarparamss)
			for(var/v in saved_vars)
				if(findtext(v, "\n"))
					var/list/split2 = splittext(v, "\n")
					found_vars |= split2[1]
				else
					found_vars |= v
			subtypes += x
	if(found_vars && found_vars.len)
		to_save |= found_vars
	return to_save

/atom
	persistent_vars = "datum_components;density;icon_state;dir;name;pixel_x;pixel_y;id"
	load_contents = TRUE

/atom/movable
	var/load_datums = FALSE

/turf
	persistent_vars = "datum_components;density;icon_state;dir;name;loc;id;baseturfs"
	load_contents = TRUE

/area
	persistent_vars = "icon_state;name;requires_power;has_gravity;dynamic_lighting;id"
	load_contents = FALSE

/datum/controller/subsystem/blackbox/
	var/datum/ship_persistence/ship_persistence

/datum/controller/subsystem/blackbox/proc/update_ships()
	if(!SSdbcore.Connect())
		return -1

	if(!ship_persistence)
		ship_persistence = new()

	for(var/datum/overmap/ship/controlled/final_ship as anything in SSovermap.controlled_ships)
		var/savefile/ship_save_file = new()
		ship_persistence.save_ship(ship_save_file, final_ship.shuttle_port.shuttle_areas)
		LAZYINITLIST(GLOB.ships_to_update)
		GLOB.ships_to_update.Add(list(list(
			"ckey" = final_ship.owner_ckey,
			"name" = final_ship.name,
			"template" = "[final_ship.source_template]",
			"memo" = final_ship.memo,
			"funds" = final_ship.ship_account.account_balance,
			"savefile" = ship_save_file.ExportText())))

	addtimer(CALLBACK(SSblackbox, TYPE_PROC_REF(/datum/controller/subsystem/blackbox, update_ship_db)),20,TIMER_OVERRIDE|TIMER_UNIQUE)

/datum/controller/subsystem/blackbox/proc/update_ship_db()
	set waitfor = FALSE
	var/list/old_ships = GLOB.ships_to_update
	GLOB.ships_to_update = null
	SSdbcore.MassInsert(format_table_name("ship_persistence"), old_ships, duplicate_key = TRUE)

/client/proc/request_ships_from_db()
	if(!SSdbcore.Connect())
		return -1
	var/datum/DBQuery/ship_request = SSdbcore.NewQuery(
		"SELECT name, template, memo, funds, savefile FROM [format_table_name("ship_persistence")] WHERE ckey = :ckey",
		list("ckey" = ckey)
	)
	if(!ship_request.Execute(async = TRUE))
		qdel(ship_request)
		return -1
	var/list/loaded_ships = list()
	while(ship_request.NextRow())
		var/savefile/loaded_ship = new()
		loaded_ship.ImportText("/", ship_request.item[5])
		loaded_ships.Add(new /datum/ship_record(ship_request.item[1], ship_request.item[2], ship_request.item[3], ship_request.item[4], loaded_ship))
	qdel(ship_request)
	prefs.ships = loaded_ships

/datum/controller/subsystem/blackbox/proc/request_ship_savefile_from_db(var/ckey, var/shipname)
	if(!SSdbcore.Connect())
		return -1
	var/datum/DBQuery/ship_request = SSdbcore.NewQuery(
		"SELECT savefile FROM [format_table_name("ship_persistence")] WHERE ckey = :ckey, name = :name",
		list("ckey" = ckey, "name" = shipname)
	)
	if(!ship_request.Execute(async = TRUE))
		qdel(ship_request)
		return -1
	var/savefile/loaded_ship = new()
	ship_request.NextRow()
	loaded_ship.ImportText(ship_request.item[1])
	qdel(ship_request)
	return loaded_ship

/datum/ship_record
	var/name
	var/template
	var/memo
	var/funds
	var/savefile/savefile

/datum/ship_record/New(name, template, memo, funds, savefile/savefile)
	src.name = name
	src.template = template
	src.memo = memo
	src.funds = funds
	src.savefile = savefile

/datum/ship_persistence
	var/list/ignore_types = list(/atom/movable/lighting_object)
	var/list/allowed_locs = list()
	var/list/object_reference = list()
	var/list/obj_references = list()
	var/list/saving_references = list()
	var/list/found_types = list()

/datum/ship_persistence/proc/save_ship(savefile/savefile, list/areas)
	if(!savefile)
		return 0
	var/min_x = 255
	var/min_y = 255
	var/max_x = 1
	var/max_y= 1
	for(var/area/A in areas)
		//var/a_ref = build_var_directory(savefile, A, 0)
		//	savefile.cd = "/areas"
		//	savefile["[area.name]"] = a_ref
		for(var/turf/turf in get_area_turfs(A))
			if(turf.x > max_x)
				max_x = turf.x
			if(turf.x < min_x)
				min_x = turf.x
			if(turf.y > max_y)
				max_y = turf.y
			if(turf.y < min_y)
				min_y = turf.y

			var/ref = build_var_directory(savefile, turf, 1)
			if(!ref)
				message_admins("[turf] failed to return a ref!")
			savefile.cd = "/map/[turf.y]"
			savefile["[turf.x]"] = ref
	savefile.cd = "/mapsize"
	savefile["max_x"] = max_x;
	savefile["max_y"] = max_y;
	savefile["min_x"] = min_x;
	savefile["min_y"] = min_y
	savefile.cd = ".."
	return 1

/datum/ship_persistence/proc/build_var_directory(savefile/savefile, atom/A, var/contents = 0)
	if(!A.should_save)
		return 0
	var/index = saving_references.Find(A)
	var/ref = 0
	if(index)
		return index
	saving_references += A
	ref = saving_references.len
	savefile.cd = "/entries/[ref]"
	savefile["type"] = A.type
	var/list/content_refs = list()
	if(A.load_contents && A.contents.len)
		var/atom/movable/Ad = A
		if(contents)
			for(var/obj/content in Ad.contents)
				if(content.loc != Ad) continue
				var/conparams = build_var_directory(savefile, content, 1)
				savefile.cd = "/entries/[ref]"
				if(!conparams)
					continue
				content_refs += "[conparams]"
		var/final_params = list2params(content_refs)
		savefile.cd = "/entries/[ref]"
		savefile["content"] = final_params
	var/list/changing_vars
	if(found_types.Find(A.type))
		changing_vars = found_types[A.type]
	else
		changing_vars = A.get_saved_vars()
		found_types["[A.type]"] = changing_vars

	var/list/old_vars = params2list(A.persistent_vars)
	var/list/safe_lists = params2list(A.safe_list_vars)
	if(istype(A, /atom/movable))
		var/atom/movable/AM = A
		if(contents && AM.load_datums)
			changing_vars += "reagents"
			changing_vars += "air_contents"
	for(var/v in changing_vars)
		if(!old_vars.Find(v))
			continue
		savefile.cd = "/entries/[ref]"
		if(A.vars.Find(v))
			if(istype(A.vars[v], /obj))
				var/atom/movable/varob = A.vars[v]
				var/conparams = build_var_directory(savefile, varob, 1)
				if(!conparams)
					continue
				savefile.cd = "/entries/[ref]"
				savefile["[v]"] = "**entry[conparams]"
			else if(istype(A.vars[v], /datum))
				var/atom/movable/varob = A.vars[v]
				var/conparams = build_var_directory(savefile, varob, 1)
				if(!conparams)
					continue
				savefile.cd = "/entries/[ref]"
				savefile["[v]"] = "**entry[conparams]"
			else if(istype(A.vars[v], /list))
				if(safe_lists.Find(v))
					savefile["[v]"] << A.vars[v]
				else
					var/list/lis = A.vars[v]
					if(lis.len)
						var/list/fixed_list = list()
						for(var/firstval in lis)
							if(istype(firstval, /obj))
								var/conparams = build_var_directory(savefile, firstval, 1)
								if(!conparams)
									continue
								fixed_list += "**entry[conparams]"
							else if(istype(firstval, /datum))
								var/conparams = build_var_directory(savefile, firstval, 1)
								if(!conparams)
									continue
								fixed_list += "**entry[conparams]"
							else
								fixed_list += firstval
						savefile.cd = "/entries/[ref]"
						savefile["[v]"] = "**list[list2params(fixed_list)]"
					else
						if(A.vars[v] != initial(A.vars[v]))
							savefile.cd = "/entries/[ref]"
							savefile["[v]"] = "**emptylist"
			else if(A.vars[v] != initial(A.vars[v]))
				savefile.cd = "/entries/[ref]"
				savefile["[v]"] = A.vars[v]
	savefile.cd = ".."
	return ref

/datum/controller/subsystem/shuttle/proc/load_ship(var/turf/T ,savefile/savefile)
	var/list/all_loaded = list()
	var/list/existing_references = list()
	if(!savefile)
		return

	savefile.cd = "/mapsize"

	var/min_x = savefile["min_x"]
	var/min_y = savefile["min_y"]

	savefile.cd = ".."
	savefile.cd = "/map"
	for(var/y in savefile.dir)
		savefile.cd = "/map/[y]"
		for(var/x in savefile.dir)
			var/turf_ref = savefile["[x]"]
			if(!turf_ref)
				message_admins("turf_ref not found, x: [x]")
				continue
			var/turf/old_turf = locate(T.x + (text2num(x) - min_x), T.y + (text2num(y) - min_y), T.z)
			load_entry(savefile, turf_ref, old_turf, null, all_loaded, existing_references)
			savefile.cd = "/map/[y]"
	for(var/datum/datum in all_loaded)
		datum.after_load()
	for(var/atom/movable/movable in all_loaded)
		// movable.Initialize(TRUE)
		movable.after_load()
		if(movable.load_datums && movable.reagents)
			movable.reagents.my_atom = movable
	return 1

/datum/controller/subsystem/shuttle/proc/load_entry(savefile/savefile, var/index, var/turf/old_turf, var/atom/starting_loc, all_loaded, existing_references)
	if(existing_references["[index]"])
		if(starting_loc)
			var/atom/movable/A = existing_references["[index]"]
			A.loc = starting_loc
		return existing_references["[index]"]
	savefile.cd = "/entries/[index]"
	var/type = savefile["type"]
	var/atom/movable/object
	if(!type)
		return
	if(old_turf)
		var/finished = 0
		while(!finished)
			finished = 1
		var/xa = old_turf.x
		var/ya = old_turf.y
		var/za = old_turf.z
		old_turf.ChangeTurf(type, FALSE, FALSE)
		object = locate(xa,ya,za)
	else
		object = new type(starting_loc)
	if(!object)
		message_admins("object not created, index: [index] type:[type]")
		return
	all_loaded += object
	existing_references["[index]"] = object

	for(var/v in savefile.dir)
		savefile.cd = "/entries/[index]"
		if(v == "type")
			continue
		else if(v == "content")
			var/list/refs = params2list(savefile[v])
			var/finished = 0
			while(!finished)
				finished = 1
				for(var/obj/ob in object.contents)
					if(ob.loc != object) continue
					finished = 0
					// ob.forceMove(locate(200, 100, 2))
					ob.Destroy()
			for(var/x in refs)
				load_entry(savefile, x, null, object, all_loaded, existing_references)
		else if(v == "loc")
			var/x = savefile[v]
			var/list/fixed = splittext(x, "entry")
			x = fixed[2]

			var/area/ship/new_loc
			if(existing_references["[x]"])
				new_loc = existing_references["[x]"]
			else
				savefile.cd = "/entries/[x]"
				var/area_type = savefile["type"]
				new_loc = new area_type
				new_loc.setup(savefile["name"])
				new_loc.set_dynamic_lighting()
				new_loc.has_gravity = TRUE
				new_loc.requires_power = TRUE
				existing_references["[x]"] = new_loc
				all_loaded += new_loc
			if(old_turf)
				var/area/old_area = old_turf.loc
				old_turf.change_area(old_area, new_loc)
				if(old_area)
					old_area.contents -= old_turf
				new_loc.contents += old_turf
		else if(findtext(savefile[v], "**list"))
			var/x = savefile[v]
			var/list/fixed = splittext(x, "list")
			x = fixed[2]
			var/list/lis = splittext(x, "&")
			var/list/final_list = list()
			if(lis.len)
				for(var/xa in lis)
					xa = url_decode(xa)
					if(findtext(xa, "**entry"))
						var/list/fixed2 = splittext(xa, "entry")
						var/y = fixed2[2]
						var/atom/movable/A = load_entry(savefile, y, null, null, all_loaded, existing_references)
						final_list += A
					if(ispath(text2path(xa)))
						final_list += "**unique**"
						final_list[final_list.len] = text2path(xa)
					else
						final_list += "**unique**"
						final_list[final_list.len] = text2num(xa)
			object.vars[v] = final_list
		else if(findtext(savefile[v], "**entry"))
			var/x = savefile[v]
			var/list/fixed = splittext(x, "entry")
			x = fixed[2]
			var/atom/movable/A = load_entry(savefile, x, null, null, all_loaded, existing_references)
			object.vars[v] = A
		else if(savefile[v] == "**null")
			object.vars[v] = null
		else if(v == "req_access_txt")
			object.vars[v] = savefile[v]
		else if(savefile[v] == "**emptylist")
			object.vars[v] = list()
		else
			savefile.cd = "/entries/[index]"
			object.vars[v] = savefile[v]
		savefile.cd = "/entries/[index]"
	savefile.cd = ".."
	return object
