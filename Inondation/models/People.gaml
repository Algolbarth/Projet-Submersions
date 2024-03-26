model People

import "Road.gaml"

species people skills: [driving] {
	string mon_origine <- "home"; // Pour le verbose
	string ma_destination <- "home"; // Pour le verbose
	building school <- nil;
	building work <- nil;
	building home <- nil;
	point the_target <- nil;
	bool isAdult <- true;
	list<building> shoppings ;
	int start_work ;
	int end_work  ;
	int start_school ;
	int end_school  ;
	list<people> relatives; // Cellule familiale
    bool goingToStore;  // Indique si l'agent compte se rendre à un magasin/Loisir ce jour-là
    int storeCtr<- -1;  // Variable d'état pour le magasin
    float mySpeed <- 20000.0;  // 20 km/h
    
    bool verbose;
    building refuge;
    bool alert;
    int nb_people_saved;
	
	reflex move when: (
		the_target != nil
	) {
		if verbose{
			write(string(self) + " going from " + mon_origine + " to " + ma_destination +" at time: " + cycle mod 24);
		}
		//Activer le on: the_graph pour forcer les agents à suivre les routes
		do goto target: the_target speed:mySpeed;// on: the_graph; 
		if location = the_target {
			the_target <- nil;
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
		the_target <- school.location;
	}
	
	reflex goToWork when:(
		(school=nil or location=school.location) // Départ au travail, après avoir déposé les enfants s'il y en a
		and isAdult
		and !alert
		and self.location != refuge.location
		and cycle mod 24 >= start_work and
		cycle mod 24 <= end_work and
		location != work.location
	){
		mon_origine <- ma_destination;
		ma_destination <- "work";
		if verbose{
			write("Go to work");
		}
		the_target <- work.location;
	}
	
	reflex goFromWork when:(
		isAdult
		and !alert
		and cycle mod 24 = end_work // Retour du travail, vers l'école ou la maison
		and self.location != refuge.location
	){
		mon_origine <- "work";
		if verbose{
			write("Go from work: " + end_work);
		}
		if school=nil{
			the_target <- home.location;
			ma_destination <- "home";
		}
		else{
			the_target <- school.location;
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
		the_target <- home.location;
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
		the_target <- any(shoppings).location;
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
		the_target <- home.location;
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
		the_target <- refuge.location;
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

    aspect default {
    	draw circle(15) color: #green;
    }
}