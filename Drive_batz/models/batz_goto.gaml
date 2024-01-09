/**
* Name: Following Paths
* Description: Vehicles moving between two intersection using the same path.
			   Note that all vehicles slow down when reaching the end of the path, because at that point they don't know which road to choose next,
			   and thus cannot determine their leading vehicle.
* Author: Duc Pham
* Tags: driving skill, graph, agent_movement, skill, transport
*/

model FollowingPaths

import "Traffic.gaml"

global {
	float step <- 0.1 #s;
	
	string map_name <- "batz";
	file shp_roads <- file("../includes/" + map_name + "/routes_batz.shp");
	file shp_nodes <- file("../includes/" + map_name + "/nodes.shp");

	geometry shape <- envelope(shp_roads) + 50; 
	
	graph road_network;
	list<intersection> non_deadend_nodes;
	
	
	init {
		create road from: shp_roads with: [num_lanes::int(read("lanes"))] {
//			num_lanes <- rnd(4, 6);
			// Create another road in the opposite direction
			create road {
				num_lanes <- myself.num_lanes;
				shape <- polyline(reverse(myself.shape.points));
				maxspeed <- myself.maxspeed;
				linked_road <- myself;
				myself.linked_road <- self;
			}
			if self=road(0){
				write self.source_node;
			}
			
		}
		
		create intersection from: shp_nodes
				with: [is_traffic_signal::(read("type") = "traffic_signals")] {
			time_to_change <- 30#s;
		}
		
		// Create a graph representing the road network, with road lengths as weights
		map edge_weights <- road as_map (each::each.shape.perimeter);
		road_network <- as_driving_graph(road, intersection) with_weights edge_weights;
		write road(0).source_node;
		write intersection where !empty(each.roads_out);
		non_deadend_nodes <- intersection where !empty(each.roads_out);
		
		// Initialize the traffic lights
		ask intersection {
			do initialize;
		}
		create vehicle_following_path number: 1000;
	}
}

species vehicle_following_path parent: base_vehicle {
	init {
		vehicle_length <- 1.9 #m;
		max_speed <- 100 #km / #h;
		max_acceleration <- 3.5;
		write self.location;
	}

	reflex select_next_path when: current_path = nil {
		// A path that forms a cycle
//		list<intersection> dst_nodes <- [intersection[98], intersection[100], intersection[137], intersection[98]];
		list<intersection> dst_nodes <- [any(non_deadend_nodes), intersection[2354]];
		do compute_path graph: road_network nodes: dst_nodes;
		write current_path;
	}
	
	reflex commute when: current_path != nil {
		do drive;
	}
}

experiment city type: gui {
	output synchronized: true {
		display map type: 2d background: #gray {
			species road aspect: base;
			species vehicle_following_path aspect: base;
			species intersection aspect: base;
		}
	}
}
