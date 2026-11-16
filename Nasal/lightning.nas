################################
## Phantom FG1
## Master Nasal


###
# State

var initialized = 0;
var engines = nil;


###
# Main Initialise Function
#
# Note:
# generic-yasim-engine.nas defines Jet directly, not yasimengines.Jet.
# This file must be loaded in the same <nasal> module as generic-yasim-engine.nas,
# with generic-yasim-engine.nas listed first in the XML.

var init = func {
    if (initialized) return;
    initialized = 1;

    print("FGUK Phantom FG1 Initialised");

    engines = {
        # Args:
        # (number, running, idle_throttle, max_start_n1, start_threshold,
        #  spool_time, start_time, shutdown_time)
        engine1: Jet.new(0, 0, 0.005, 6, 5, 1.6, 1.2, 1),
        engine2: Jet.new(1, 0, 0.005, 6, 5, 1.6, 1.2, 1),
    };

    engines.engine1.init();
    engines.engine2.init();
};


###
# Doors (Canopy)

# Args: (property path, seconds, start position)
var canopy = aircraft.door.new("canopy", 5, 1);


###
# Lights

var lightpath = "sim/model/lights";
var lights = {
    anticoll: aircraft.light.new(
        lightpath ~ "/anti-coll",
        [0.05, 1.8],
        lightpath ~ "/anti-coll/powered"
    ),
};


###
# Go!

setlistener("sim/signals/fdm-initialized", func {
    settimer(init, 2);
});
