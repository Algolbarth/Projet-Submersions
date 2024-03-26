model Inondation

import "Road.gaml"

global {
	bool verbose <- true;
	map type_building <- ["house"::1, "office"::2, "school"::3, "refuge"::4, "shopping"::5];
	float seed <- 42.0;
	float lane_width <- 0.7;
	float traffic_light_interval parameter: 'Traffic light interval' init: 60#s;
    int nb_people <- 1;
    int nb_people_saved <- 0;
	int min_work_start <- 8;
	int max_work_start <- 9;
	int min_school_start <- 7;
	int max_school_start <- 8;
	int min_work_end <- 16; 
	int max_work_end <- 18; 
	int min_school_end <- 15; 
	int max_school_end <- 16;
	int alert_hour <- 10;
	bool alert <- false;
	float step <- 2 #m;
    
    file roads_shapefile <- file("../includes/batz/routes_batz.shp");
    file nodes_shapefile <- file("../includes/batz/nodes.shp");
    file buildings_shapefile <- file("../includes/batz/buildings.shp");
	geometry shape <- envelope(roads_shapefile) + 50;  
    
    graph the_graph;
	list<intersection> non_deadend_nodes;

	building refuge;

    init {
	    create road from: roads_shapefile with: [num_lanes::int(read("lanes"))] {
			num_lanes <- rnd(4, 6);
			create road {
				num_lanes <- myself.num_lanes;
				shape <- polyline(reverse(myself.shape.points));
				maxspeed <- myself.maxspeed;
				linked_road <- myself;
				myself.linked_road <- self;
			}
		}
		
		create intersection from: nodes_shapefile
			with: [is_traffic_signal::(read("type") = "traffic_signals")] {
			time_to_change <- traffic_light_interval;
		}
		
		map edge_weights <- road as_map (each::each.shape.perimeter);
		the_graph <- as_driving_graph(road, intersection) with_weights edge_weights;
		non_deadend_nodes <- intersection where !empty(each.roads_out);
		ask intersection {
			do initialize;
		}
		
		create building from: buildings_shapefile{
	    	type <- -1;
	    }
	    int number_of_buildings <- length(building);
	    ask round(0.66*number_of_buildings) among building{  // habitations
	    	type <- type_building["house"];
	    	color <- #white;
	    }
	    ask round(0.18*number_of_buildings) among building where (each.type=-1){  // bureaux
	    	type <- type_building["office"];
	    	color <- #blue;
	    }
	    ask round(0.02*number_of_buildings) among building where (each.type=-1){  // écoles
	    	type <- type_building["school"];
	    	color <- #yellow;
	    }
	    ask round(0.13*number_of_buildings) among building where (each.type=-1){  // magasins/lieux de loisirs
	    	type <- type_building["shopping"];
	    	color <- #orange;
	    }
	    list<building> remaining <- (building where (each.type=-1));
	    ask 1 among remaining {
	    	type <- type_building["refuge"];
	    	color <- #red;
	    }
	    refuge <- any(building where(each.type=type_building["refuge"]));
	    
	    list<float> distances <- [];
	   	loop b over: building {
	   		intersection node <- any(non_deadend_nodes);
			float best_distance <- 10000.0;
			loop n over: non_deadend_nodes {
				float distance <- sqrt(square(abs(b.location.x - n.location.x)).area + square(abs(b.location.y - n.location.y)).area);
				if distance < best_distance {
					best_distance <- distance;
					node <- n;
				}
			}
			b.node<- node;
			add item:best_distance to: distances;
	   	}
		
	    // nb_people <- 2*length(building where (each.type = type_building["house"]));  // Calibrer le nombre de personnes au nombre de maisons.
	    create people number: nb_people { // Taux d'enfants et de patients pour lesquels les symptômes seront sévères
	        //isAdult <- flip(0.25);
	    }
	    
	    loop p over: people where (each.isAdult){ // Création de couples
	    	if(empty(p.relatives) and length(people where (each.isAdult))!=1) {
	    		if flip(0.8){
	    			people mate <- any(people where (each.isAdult and empty(each.relatives)));
	    			ask p{
	    				add mate to:self.relatives;
	    			}
	    			ask mate{
	    				add p to:self.relatives;
	    			}
	    		}
	    	}
	    }
	    
	    loop p over: people where (!each.isAdult){  // Ajout des enfants; génération de cellules familiales
	    	if(empty(p.relatives)){
	    		people parent <- any(people where (each.isAdult));
	    		list<people> rels <- [p, parent];
	    		rels <<+ parent.relatives;
	    		ask p{
	    			self.relatives <- rels where (each != self);
	    		}
	    		ask parent{
	    			self.relatives <- rels where (each != self);
	    		}
	    		loop r over: parent.relatives{
	    			ask r{
		    			self.relatives <- rels where (each != self);
	    			}
	    		}
	    	}
		}
		
		list empty_houses <- building where (each.type=type_building["house"]);  // Attributions de maisons aux cellules familiales
		loop p over: people{
			if p.home = nil{
				if length(empty_houses) != 0{
					ask p{
						self.home <- any(empty_houses);
						self.the_current <- self.home;
						self.location <- self.home.location;
					}
					building chosen_home <- p.home;
					loop r over: p.relatives{
						ask r{
							self.home <- chosen_home;
							self.the_current <- self.home;
							self.location <- self.home.location;
						}
					}
					remove chosen_home from: empty_houses;
				}
			}
		}
	    
	    loop p over: people where (!each.isAdult){  // Attribution des écoles
	    	if p.school=nil{
		    	ask p{
		    		self.school <- any(building where (each.type=type_building["school"]));
		    		self.start_school <- min_school_start + rnd (max_school_start - min_school_start);
		    		self.end_school <- min_school_end + rnd (max_school_end - min_school_end);
		    	}
		    	loop r over: (p.relatives where (each!=p)){ // On considère que les deux parents amènent les enfants à l'école, et qu'ils sont tous à la même école, avec les mêmes horaires
		    		ask r{
			    		self.school <- p.school;
			    		self.start_school <- p.start_school;
			    		self.end_school <- p.end_school;
		    		}
		    	}
	    	}
	    }
	    
	    loop p over: people where (each.isAdult = true){  // attribution du travail & des magasins/lieux de loisirs
	    	ask p{
	    		self.work <- any(building where (each.type=type_building["office"]));
	    		self.start_work <- max([min_work_start, start_school]) +
					rnd (max_work_start - max([min_work_start, start_school]));
				int min_time;
				if end_school !=0{
					min_time <- min([min_work_end, end_school]);
					self.end_work <- min_time;
				}
				else{
					min_time <- min_work_end;
					int rand <- rnd (max_work_end - min_time);
		    		self.end_work <- min_time + rand;
				}
				self.shoppings <- [any(building where(each.type = type_building["shopping"]))];
				loop i from: 0 to: 4{
					self.shoppings << any(building where(each.type = type_building["shopping"])); 
				}
	    	}
	    }
    }
    
    reflex inondation when: cycle = 60*alert_hour { // Une inondation se déclenche au bout de 10h
    	alert <- true ;
    }

    reflex end_simulation when: false {  // Bloquer la simulation quand tout le monde a été contaminé. Ne pas hésiter à s'arrêter avant.
    	do pause;
    }
}

species car parent: vehicle {
	init {
		vehicle_length <- 0.5 #m;
		max_speed <- (60 + rnd(10)) #km / #h;
	}

	action move_to (building start_building, building finish_building) {		
		intersection start_node <- start_building.node;
		intersection finish_node <- finish_building.node;
		
		do compute_path graph: the_graph nodes: [start_node, finish_node];
		
		if verbose {
			write "Building : from [" + int(start_building.location.x) + ":" + int(start_building.location.y) + "] to [" + int(finish_building.location.x) + ":" + int(finish_building.location.y) + "]";
			write "Nodes : from [" + int(start_node.location.x) + ":" + int(start_node.location.y) + "] to [" + int(finish_node.location.x) + ":" + int(finish_node.location.y) + "]";
			write "Path : " + current_path;
			write "----------";
		}
	}
	
	reflex select_next_path when: current_path = nil {
		do move_to(any(building), refuge);
	}
	
	reflex commute when: current_path != nil {
		do drive;
	}
}

species vehicle skills: [driving] {
	rgb color <- rgb('green');
	graph road_graph;
	
	point compute_position {
		// Shifts the position of the vehicle perpendicularly to the road,
		// in order to visualize different lanes
		if (current_road != nil) {
			float dist <- (road(current_road).num_lanes - current_lane -
				mean(range(num_lanes_occupied - 1)) - 0.5) * lane_width;
			if violating_oneway {
				dist <- -dist;
			}
		 	point shift_pt <- {cos(heading + 90) * dist, sin(heading + 90) * dist};	
		
			return location + shift_pt;
		} else {
			return {0, 0};
		}
	}
	
	aspect base {
		if (current_road != nil) {
			point pos <- compute_position();
				
			draw rectangle(vehicle_length, lane_width * num_lanes_occupied) 
				at: pos color: color rotate: heading border: #black;
			draw triangle(lane_width * num_lanes_occupied) 
				at: pos color: #white rotate: heading + 90 border: #black;
		}
	}
}

species people skills: [driving] {
	string mon_origine <- "home"; // Pour le verbose
	string ma_destination <- "home"; // Pour le verbose
	building the_current <- nil;
	building the_origin <- nil;
	building the_target <- nil;
	
	building school <- nil;
	building work <- nil;
	building home <- nil;
	bool isAdult <- true;
	list<building> shoppings ;
	int start_work ;
	int end_work  ;
	int start_school ;
	int end_school  ;
	list<people> relatives; // Cellule familiale
    bool goingToStore;  // Indique si l'agent compte se rendre à un magasin/Loisir ce jour-là
    int storeCtr <- -1;  // Variable d'état pour le magasin
	
	init {
		vehicle_length <- 0.5 #m;
		max_speed <- (60 + rnd(10)) #km / #h;
	}
	
	reflex move when: (
		the_target != nil
	) {
		if verbose{
			write(string(self) + " going from " + mon_origine + " to " + ma_destination +" at time: " + cycle mod 24);
		}
		if the_origin != the_target {
			do move_to (the_origin, the_target);
		}
		the_target <- nil;
	}
    
    action move_to (building start_building, building finish_building) {		
		intersection start_node <- start_building.node;
		intersection finish_node <- finish_building.node;
		
		do compute_path graph: the_graph nodes: [start_node, finish_node];
		
		if verbose {
			//write "Building : from [" + int(start_building.location.x) + ":" + int(start_building.location.y) + "] to [" + int(finish_building.location.x) + ":" + int(finish_building.location.y) + "]";
			write "Nodes : from [" + int(start_node.location.x) + ":" + int(start_node.location.y) + "] to [" + int(finish_node.location.x) + ":" + int(finish_node.location.y) + "]";
			write "Path : " + current_path;
			write "----------";
		}
	}
    
    reflex commute when: current_path != nil {
		do drive;
	}
	
	reflex finish when: (the_target != nil and the_target.node.location = self.location) {
		the_current <- the_target;
		self.location <- the_current.location;
		the_target <- nil;
		if verbose {
			write "Bien arrivé";
		}
	}
	
	reflex goToSchool when: (
		school!=nil
		and cycle mod 24 = start_school // Départ à l'école
		and self.location != refuge.location
	) {
		if verbose{
			write("Go to school:  " + cycle mod 24);
		}
		mon_origine <- ma_destination;
		ma_destination <- "school";
		the_origin <- the_target;
		the_target <- school;
	}
	
	reflex goToWork when:(
		(school=nil or location=school.location) // Départ au travail, après avoir déposé les enfants s'il y en a
		and isAdult
		and !alert
		and self.location != refuge.location
		and cycle mod 24 >= start_work and
		cycle mod 24 <= end_work and
		the_current != work
	){
		mon_origine <- ma_destination;
		ma_destination <- "work";
		if verbose{
			write("Go to work");
		}
		the_origin <- the_current;
		the_target <- work;
	}
	
	reflex goFromWork when:(
		isAdult
		and !alert
		and cycle mod 24 = end_work // Retour du travail, vers l'école ou la maison
		and self.location != refuge.location
	){
		the_origin <- work;
		mon_origine <- "work";
		if verbose{
			write("Go from work: " + end_work);
		}
		if school=nil{
			the_target <- home;
			ma_destination <- "home";
		}
		else{
			the_target <- school;
			ma_destination <- "school";
		}
	}
	
	bool checkRelativesSchool{ // Vérifier que les parents sont bien venus chercher les enfants
		bool b <- true;
		loop r over: relatives{
			if(r.location != school.location and r.location != refuge.location){
				b <- false;
			}
		}
		if location != school.location{
			b <- false;
		}
		return b;
	}
	
	bool isInShopping{ // Vérifier si l'agent est dans un shopping
		loop s over: shoppings{
			if (location=s.location){
				return true;
			}
		}
		return false;
	}
	
	reflex goFromSchool when:(
		(school!=nil)
		and !alert
		and (cycle mod 24 >= end_school)
		and checkRelativesSchool() // Revenir de l'école
		and self.location != refuge.location
	){
		if verbose{
			write(string(self) + " going from school at " + cycle mod 24);
		}
		mon_origine <- "school";
		ma_destination <- "home";
		the_origin <- school;
		the_target <- home;
	}
	
	reflex decideToGoToStore when: (
		isAdult
		and cycle mod 24 = 0 // Tous les jours, décider d'aller à un magasin/loisir ou non
	) {
		if verbose{
			write("Decide to go to store");
		}
		goingToStore <- flip(0.4);
	}
	
	reflex goToStore when: (
		isAdult
		and !alert
		and goingToStore
		and location = home.location
		and cycle mod 24 >=end_work // Aller à un magasin/loisir ou non
		and self.location != refuge.location
	) {
		mon_origine <- "home";
		ma_destination <- "store";
		if verbose{
			write("Go to store");
		}
		the_origin <- home;
		the_target <- any(shoppings);
	}

	reflex InStore when: (
		goingToStore
		and isInShopping()
		and storeCtr = -1 // Tous les jours, décider d'aller à un magasin/loisir ou non
	) {
		storeCtr <- cycle mod 24;
	}
	
	reflex goFromStore when: (
		isInShopping()
		and !alert
		and cycle mod 24 > (storeCtr+1) mod 24
	) { // Repartir
		if verbose{
			write("Go from store");
		}
		mon_origine <- "store";
		ma_destination <- "home";
		the_origin <- the_current;
		the_target <- home;
		storeCtr <- -1;
		goingToStore <- false;
	}
	
	reflex goToRefuge when : (
		alert
	) {
		if verbose{
			write("Go to refuge");
		}
		mon_origine <- "n'importe où";
		ma_destination <- "refuge";
		the_origin <- the_current;
		the_target <- refuge;
	}
	
	reflex inRefuge when : (
		location = refuge.location
	) {
		if verbose {
			write("Est parti dans un monde meilleur");
		}
		nb_people_saved <- nb_people_saved + 1;
		do die ;
	}
	
	point compute_position {
		// Shifts the position of the vehicle perpendicularly to the road,
		// in order to visualize different lanes
		if (current_road != nil) {
			float dist <- (road(current_road).num_lanes - current_lane -
				mean(range(num_lanes_occupied - 1)) - 0.5) * lane_width;
			if violating_oneway {
				dist <- -dist;
			}
		 	point shift_pt <- {cos(heading + 90) * dist, sin(heading + 90) * dist};	
		
			return location + shift_pt;
		} else {
			return {0, 0};
		}
	}

    aspect default {
    	if (current_road != nil) {
			point pos <- compute_position();
				
			draw rectangle(vehicle_length, lane_width * num_lanes_occupied) 
				at: pos color: #green rotate: heading border: #black;
			draw triangle(lane_width * num_lanes_occupied) 
				at: pos color: #white rotate: heading + 90 border: #black;
		}
		else {
			draw circle(15) color: #green;
		}
    }
}

experiment city type: gui {
	parameter "Heures avant inondation :" var: alert_hour ;
	parameter "Nombre d'habitants :" var: nb_people ;
	
    output synchronized: true {
	    monitor "Current hour" value: "hour: " + string(int(cycle/60)) + " minute: " + string(cycle mod 60);
	    monitor "Inondation" value: alert;
	    monitor "Personnes sauvées" value: nb_people_saved;
	    
	    display map type: 2d background: #gray {
	        species road;
	        species building;
	        species people;
	        species intersection aspect: base;
	        species car aspect: base;
	    }
    }
}