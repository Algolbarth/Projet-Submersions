model Building

species building {
	int type;
    aspect default {
    	draw shape color: type=1?#grey:(type=2?#blue:(type=3?#yellow:(type=4?#red:#cyan))) border: #black;
    }
}