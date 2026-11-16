# instruments.nas
# Rewritten for safer init/listener handling

var UPDATE_PERIOD = 0.1;

var initialized = 0;
var instruments_running = 0;
var listeners = [];

var digit1 = 0;
var digit2 = 0;
var digit3 = 0;
var digit4 = 0;
var digit5 = 0;

var safe_get = func(path, fallback = 0) {
    var v = getprop(path);
    return v == nil ? fallback : v;
}

var add_listener = func(path, cb) {
    var id = setlistener(path, cb);
    append(listeners, id);
    return id;
}

var instrumenttimer = func {
    if (instruments_running) return;
    instruments_running = 1;

    var loop = nil;
    loop = func {
        radiodisplay();
        settimer(loop, UPDATE_PERIOD);
    };

    settimer(loop, UPDATE_PERIOD);
};

# ==================== Radio Frequency Display =========================

var displaysegments = func(radio, selected) {
    var freq = safe_get("/instrumentation/" ~ radio ~ "/frequencies/" ~ selected ~ "-mhz", 0);
    var formatted = sprintf("%.02f", freq);

    if (size(formatted) < 6) return;

    digit1 = substr(formatted, 0, 1);
    digit2 = substr(formatted, 1, 1);
    digit3 = substr(formatted, 2, 1);
    digit4 = substr(formatted, 4, 1);
    digit5 = substr(formatted, 5, 1);

    setprop("/instrumentation/" ~ radio ~ "/" ~ selected ~ "/digit1", digit1);
    setprop("/instrumentation/" ~ radio ~ "/" ~ selected ~ "/digit2", digit2);
    setprop("/instrumentation/" ~ radio ~ "/" ~ selected ~ "/digit3", digit3);
    setprop("/instrumentation/" ~ radio ~ "/" ~ selected ~ "/digit4", digit4);
    setprop("/instrumentation/" ~ radio ~ "/" ~ selected ~ "/digit5", digit5);
};

var radiodisplay = func {
    displaysegments("nav[0]", "selected");
    displaysegments("nav[0]", "standby");

    displaysegments("comm[0]", "selected");
    displaysegments("comm[0]", "standby");

    displaysegments("comm[1]", "selected");
    displaysegments("comm[1]", "standby");
};

# ==================== Fuel logic helpers =========================

var update_total_internal_fuel = func {
    var total =
        safe_get("/consumables/fuel/tank/level-lbs", 0) +
        safe_get("/consumables/fuel/tank[1]/level-lbs", 0) +
        safe_get("/consumables/fuel/tank[2]/level-lbs", 0) +
        safe_get("/consumables/fuel/tank[3]/level-lbs", 0) +
        safe_get("/consumables/fuel/tank[4]/level-lbs", 0);

    interpolate("/consumables/fuel/total-internal-fuel-lbs", total, 1);
};

var update_tank_selector = func {
    var sw = safe_get("/consumables/fuel/tank-selector", 0);

    var pos0 = sw * 7;
    var pos3 = sw * 2 + 3;
    var pos4 = sw * 2 + 4;

    setprop("/consumables/fuel/tank[" ~ pos0 ~ "]/selected", 1);
    setprop("/consumables/fuel/tank[" ~ pos3 ~ "]/selected", 1);
    setprop("/consumables/fuel/tank[" ~ pos4 ~ "]/selected", 1);
};

var update_feed_tanks = func {
    var tn = safe_get("/consumables/fuel/tank[0]/selected", 0);
    var selector = safe_get("/consumables/fuel/tank-selector", 0);

    var tnk1 = 1 - tn + selector * 6;
    var tnk2 = 2 - tn * 2 + selector * 5;

    setprop("/consumables/fuel/tank-lower1", tnk1);
    setprop("/consumables/fuel/tank-lower2", tnk2);
};

var update_lower1 = func {
    var pos1 = safe_get("/consumables/fuel/tank-lower1", 0);
    setprop("/consumables/fuel/tank[" ~ pos1 ~ "]/selected", 1);
};

var update_lower2 = func {
    var pos2 = safe_get("/consumables/fuel/tank-lower2", 0);
    setprop("/consumables/fuel/tank[" ~ pos2 ~ "]/selected", 1);
};

# ==================== Dynamic updates =========================

var update_apu_ready = func {
    interpolate("/controls/APU/ready", 1, 10);
};

var update_rpm_right = func {
    interpolate("/instrumentation/rpm/engine-rh", safe_get("/engines/engine[0]/n1", 0) / 2 + 50, 1);
};

var update_rpm_left = func {
    interpolate("/instrumentation/rpm/engine-lh", safe_get("/engines/engine[1]/n1", 0) / 2 + 50, 1);
};

var update_refuel_hatch = func {
    interpolate("/consumables/fuel/refuel-hatch-pos", safe_get("/consumables/fuel/slip-way-door", 0), 2);
};

var update_splash = func {
    interpolate("/environment/aircraft-effects/splash-vector-x", safe_get("/velocities/airspeed-kt", 0) * -0.005, 1);
};

var update_tat = func {
    var oat = safe_get("/environment/temperature-degc", 0);
    var mach = safe_get("/velocities/mach", 0);
    var tat = oat + ((oat + 273) * 0.2 * (mach * mach));
    interpolate("/environment/total-air-temperature-degc", tat, 5);
};

var update_frost = func {
    var tat = safe_get("/environment/total-air-temperature-degc", 0);
    var heat = safe_get("/environment/windowheat-level", 1);
    interpolate("/environment/aircraft-effects/frost-level", (tat + 10) * heat * -0.03, 1);
};

var update_windowheat = func {
    interpolate("/environment/windowheat-level", 1 - safe_get("/controls/anti-ice/window-heat", 0) * 0.9, 10);
};

var update_nav_bearing = func {
    interpolate(
        "/instrumentation/nav/nav-needle-error-deg",
        safe_get("/instrumentation/nav/heading-deg", 0) - safe_get("/orientation/heading-deg", 0),
        0.01
    );
};

var update_tacan_bearing = func {
    interpolate(
        "/instrumentation/tacan/tacan-needle-error-deg",
        safe_get("/instrumentation/tacan/indicated-bearing-true-deg", 0) - safe_get("/orientation/heading-deg", 0),
        0.01
    );
};

# ==================== Initialise =========================

var initialize = func {
    if (initialized) return;
    initialized = 1;

    props.globals.getNode("/instrumentation/uhf/commvol-norm", 1).setDoubleValue(0.0);
    props.globals.getNode("/instrumentation/kns80/navvol-norm", 1).setDoubleValue(0.0);
    props.globals.getNode("/instrumentation/kx155a/commvol-norm", 1).setDoubleValue(0.0);
    props.globals.getNode("/instrumentation/kx155a/navvol-norm", 1).setDoubleValue(0.0);
    props.globals.getNode("/instrumentation/kt-70/inputs/func-knob", 1).setDoubleValue(0);
    props.globals.getNode("/instrumentation/dme/switch-position", 1).setDoubleValue(0);

    props.globals.getNode("/controls/APU/ready", 1).setDoubleValue(0.0);
    props.globals.getNode("/consumables/fuel/slip-way-door", 1).setIntValue(0);
    props.globals.getNode("/consumables/fuel/refuel-hatch-pos", 1).setDoubleValue(0.0);

    setprop("/controls/switches/taxi-lights", 0);
    props.globals.getNode("/instrumentation/fuelgauge/selector", 1).setIntValue(1);
    setprop("/instrumentation/fric-knob", 0.01);

    props.globals.getNode("/consumables/fuel/ext-tank-ctr-selected", 1).setIntValue(1);
    props.globals.getNode("/consumables/fuel/ext-tank-wing-selected", 1).setIntValue(1);

    setprop("/consumables/fuel/tank[0]/selected", 0);
    setprop("/consumables/fuel/tank[1]/selected", 0);
    setprop("/consumables/fuel/tank[2]/selected", 0);
    setprop("/consumables/fuel/tank[3]/selected", 0);
    setprop("/consumables/fuel/tank[4]/selected", 0);

    props.globals.getNode("/environment/aircraft-effects/splash-vector-y", 1).setDoubleValue(0.01);
    props.globals.getNode("/environment/aircraft-effects/splash-vector-z", 1).setDoubleValue(-1);
    props.globals.getNode("/instrumentation/nav/nav-needle-error-deg", 1).setDoubleValue(0.0);
    props.globals.getNode("/instrumentation/tacan/tacan-needle-error-deg", 1).setDoubleValue(0.0);
    setprop("/environment/windowheat-level", 1);

    add_listener("/controls/APU/fire-switch", func { update_apu_ready(); });

    add_listener("/engines/engine[0]/n1", func {
        update_rpm_right();
        update_splash();
        update_tat();
        update_frost();
        update_nav_bearing();
        update_tacan_bearing();
    });

    add_listener("/engines/engine[1]/n1", func {
        update_rpm_left();
    });

    add_listener("/consumables/fuel/slip-way-door", func { update_refuel_hatch(); });
    add_listener("/consumables/fuel/tank/level-lbs", func { update_total_internal_fuel(); });

    add_listener("/consumables/fuel/tank[5]/selected", func {
        setprop("/consumables/fuel/tank-selector", safe_get("/consumables/fuel/tank[5]/selected", 0));
    });

    add_listener("/consumables/fuel/tank-selector", func { update_tank_selector(); });
    add_listener("/consumables/fuel/tank[0]/selected", func { update_feed_tanks(); });
    add_listener("/consumables/fuel/tank-lower1", func { update_lower1(); });
    add_listener("/consumables/fuel/tank-lower2", func { update_lower2(); });
    add_listener("/controls/anti-ice/window-heat", func { update_windowheat(); });

    instrumenttimer();

    update_total_internal_fuel();
    update_refuel_hatch();
    update_rpm_right();
    update_rpm_left();
    update_splash();
    update_tat();
    update_frost();
    update_nav_bearing();
    update_tacan_bearing();

    print("Instruments : initialised");
};

setlistener("/sim/signals/fdm-initialized", func { initialize(); });
