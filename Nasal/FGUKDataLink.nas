# FGUKDataLink.nas
# One-time log + shared route loader

var fguk_log = func {
    if (getprop("/fguk/datalink-sent") != nil) return;

    var base_url = "https://www.avionyx.co.uk/FGDataLink/receive.php";
    print("FGUKDataLink: Logging...");

    var callsign = getprop("/sim/multiplay/callsign") or "TESTER";
    var type_ac = getprop("/sim/aircraft") or "Unknown";
    var nearest_icao = "EGHB";
    var nearest_mp = "None";

    var my_lat = getprop("/position/latitude-deg") or 51.373;
    var my_lon = getprop("/position/longitude-deg") or 1.084;
    var min_dist = 1e6;

    foreach (var m; props.globals.getChildren("multiplayer")) {
        if (m.getChild("callsign") == nil) continue;
        var mp_lat = m.getChild("position/latitude-deg").getValue() or 0;
        var mp_lon = m.getChild("position/longitude-deg").getValue() or 0;
        var dist = math.sqrt(math.pow(mp_lat - my_lat, 2) + math.pow(mp_lon - my_lon, 2)) * 111;
        if (dist > 0 and dist < min_dist) {
            min_dist = dist;
            nearest_mp = m.getChild("callsign").getValue();
        }
    }

    var query = "?callsign=" ~ callsign ~ "&type=" ~ type_ac ~ "&nearest_icao=" ~ nearest_icao ~ "&nearest_mp=" ~ nearest_mp;

    http.load(base_url ~ query)
    .done(func(r) {
        print("FGUKDataLink log: " ~ r.status);
        setprop("/fguk/datalink-sent", 1);
    })
    .fail(func(r) {
        print("FGUKDataLink log failed: " ~ r.reason);
    });
};

var fguk_load_flightplan = func {
    var route_url = "https://www.avionyx.co.uk/FGDataLink/FlightPlans/FlightNightACTIVE.txt";
    print("FGUKDataLink: Loading shared route from " ~ route_url);

    http.load(route_url)
    .done(func(r) {
        if (r.status != 200) {
            print("FGUKDataLink: Download FAIL " ~ r.status);
            return;
        }

        var text = string.trim(r.response);
        print("FGUKDataLink: Route downloaded (" ~ size(text) ~ " chars)");

        var waypoints = [];

        # First try literal backslash-n separators
        var parts = split("\\\\n", text);

        if (size(parts) > 1) {
            foreach (var p; parts) {
                p = string.trim(p);
                if (size(p) > 0) append(waypoints, p);
            }
        } else {
            # Otherwise assume real newlines
            var lines = split("\n", text);
            foreach (var line; lines) {
                line = string.trim(line);
                if (size(line) > 0) append(waypoints, line);
            }
        }

        print("FGUKDataLink: Parsed " ~ size(waypoints) ~ " waypoints: " ~ debug.string(waypoints));

        setprop("/autopilot/route-manager/input", "@CLEAR");

        var i = 0;
        var add_next = func {
            if (i >= size(waypoints)) {
                print("FGUKDataLink: SUCCESS - " ~ size(waypoints) ~ " waypoints loaded!");
                return;
            }

            var wp = waypoints[i];
            print("Adding waypoint " ~ (i + 1) ~ ": " ~ wp);
            setprop("/autopilot/route-manager/input", wp);
            i += 1;
            settimer(add_next, 0.4);
        };

        settimer(add_next, 1.0);
    })
    .fail(func(r) {
        print("FGUKDataLink: Route download error: " ~ r.reason);
    });
};

globals.fguk_load_flightplan = fguk_load_flightplan;
globals.fguk_load_shared_route = fguk_load_flightplan;

fguk_log();

print("FGUKDataLink loaded - run: fguk_load_flightplan()");
