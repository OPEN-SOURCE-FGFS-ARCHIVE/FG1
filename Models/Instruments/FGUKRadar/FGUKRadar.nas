# Radar instrument for aircraft cockpit (canvas on configurable screen object)
# GPL V3 but please give credit to FGUK for this script [www.fguk.me]
# Portable + optimised version based on the full-featured FGUK radar script.

var fgukradar_instance = nil;
var FGUK_RADAR_DEG2RAD = math.pi / 180;

var RadarInstrument = {
    new: func() {
        var me = { parents: [RadarInstrument] };

        me.canvas = canvas.new({
            "name": "RadarInstrument",
            "size": [512, 512],
            "view": [512, 512],
            "mipmapping": 1
        });

        me.screen_node_prop = props.globals.getNode("/instrumentation/FGUKRadar/screen-node", 1);
        if (me.screen_node_prop.getValue() == nil or me.screen_node_prop.getValue() == "") {
            me.screen_node_prop.setValue("RDRScreen");
        }
        me.canvas.addPlacement({ "node": me.screen_node_prop.getValue() });
        me.root = me.canvas.createGroup();

        me.segments = 32;
        me.radius = 256;
        me.center_x = 256;
        me.center_y = 256;
        me.update_interval = 0.10;
        me.dialog_refresh_interval = 0.5;
        me.ghost_timeout = 60;
        me.max_dialog_items = 10;

        me.background_group = me.root.createChild("group", "background-group");
        me.rings_group = me.root.createChild("group", "rings-group");
        me.contacts_group = me.root.createChild("group", "contacts-group");

        var background = me.background_group.createChild("path");
        for (var i = 0; i <= me.segments; i += 1) {
            var angle = i * 2 * math.pi / me.segments;
            var x = me.center_x + me.radius * math.cos(angle);
            var y = me.center_y + me.radius * math.sin(angle);
            if (i == 0) {
                background.moveTo(x, y);
            } else {
                background.lineTo(x, y);
            }
        }
        background.close()
            .setColorFill(0.2, 0, 0)
            .setColor(0.3, 0, 0)
            .setStrokeLineWidth(2);

        me.range_node = props.globals.getNode("/instrumentation/FGUKRadar/range-nm", 1);
        if (me.range_node.getValue() == nil or me.range_node.getValue() <= 0) {
            me.range_node.setDoubleValue(50);
        }

        me.highlight_callsign_node = props.globals.getNode("/instrumentation/FGUKRadar/highlight-callsign", 1);
        if (me.highlight_callsign_node.getValue() == nil) {
            me.highlight_callsign_node.setValue("");
        }

        me.up_north_node = props.globals.getNode("/instrumentation/FGUKRadar/up-north", 1);
        if (me.up_north_node.getValue() == nil) {
            me.up_north_node.setBoolValue(0);
        }

        me.target_callsign_node = props.globals.getNode("/instrumentation/FGUKRadar/hud/target-callsign", 1);
        me.target_range_node = props.globals.getNode("/instrumentation/FGUKRadar/hud/target-range-nm", 1);
        me.target_bearing_node = props.globals.getNode("/instrumentation/FGUKRadar/hud/target-bearing-deg", 1);
        me.target_alt_node = props.globals.getNode("/instrumentation/FGUKRadar/hud/target-altitude-ft", 1);
        me.target_hud_x_node = props.globals.getNode("/instrumentation/FGUKRadar/hud/target-reticule-x", 1);
        me.target_hud_y_node = props.globals.getNode("/instrumentation/FGUKRadar/hud/target-reticule-y", 1);

        me.dialog_selected_index_node = props.globals.getNode("/instrumentation/FGUKRadar/dialog/selected-index", 1);
        me.dialog_selected_index_node.setIntValue(0);
        me.dialog_count_node = props.globals.getNode("/instrumentation/FGUKRadar/dialog/count", 1);

        me.dialog_label_nodes = [];
        me.dialog_callsign_nodes = [];
        for (var di = 0; di < me.max_dialog_items; di += 1) {
            append(me.dialog_label_nodes,
                props.globals.getNode("/instrumentation/FGUKRadar/dialog/labels/label[" ~ di ~ "]", 1));
            append(me.dialog_callsign_nodes,
                props.globals.getNode("/instrumentation/FGUKRadar/dialog/callsigns/callsign[" ~ di ~ "]", 1));
        }

        me.position_alt_node = props.globals.getNode("/position/altitude-ft", 1);
        me.heading_node = props.globals.getNode("/orientation/heading-deg", 1);
        me.ai_models_node = props.globals.getNode("/ai/models", 1);

        me.target_callsign_node.setValue("");
        me.target_range_node.setDoubleValue(-1);
        me.target_bearing_node.setDoubleValue(0);
        me.target_alt_node.setDoubleValue(0);
        me.target_hud_x_node.setDoubleValue(0);
        me.target_hud_y_node.setDoubleValue(0);

        me.smoothed_hud_x = 0;
        me.smoothed_hud_y = 0;
        me.hud_smoothing_alpha = 0.18;

        me.dialog_callsigns = [];
        me.last_targets = [];
        me.last_dialog_refresh = 0;
        me.update_scheduled = 0;

        me.blips = {};
        me.callsign_labels = {};
        me.altitude_labels = {};
        me.distance_labels = {};
        me.tracked_callsigns = {};

        me.updateRangeRings();

        setlistener("/instrumentation/FGUKRadar/range-nm", func {
            me.updateRangeRings();
        }, 0, 0);

        setlistener("/instrumentation/FGUKRadar/highlight-callsign", func {
            me.recolorVisibleContacts();
            me.refreshDialogCallsignsFromTargets(me.last_targets);
        }, 0, 0);

        setlistener("/instrumentation/FGUKRadar/up-north", func {
        }, 0, 0);

        setlistener("/instrumentation/FGUKRadar/dialog/selected-index", func {
            var idx = me.dialog_selected_index_node.getValue();
            if (idx == nil) idx = 0;
            me.selectDialogIndex(idx);
        }, 0, 0);

        settimer(func { me.initializeMultiplayerData(); }, 5);
        me.refreshDialogCallsignsFromTargets([]);
        me.update();

        return me;
    },

    createBlipSymbol: func() {
        return me.contacts_group.createChild("path")
            .moveTo(0, -10)
            .lineTo(10, 0)
            .lineTo(0, 10)
            .lineTo(-10, 0)
            .lineTo(0, -10)
            .setStrokeLineWidth(2);
    },

    ensureContactVisual: func(callsign) {
        if (!contains(me.blips, callsign) or me.blips[callsign] == nil) {
            me.blips[callsign] = me.createBlipSymbol();
        }

        if (!contains(me.callsign_labels, callsign) or me.callsign_labels[callsign] == nil) {
            me.callsign_labels[callsign] = me.contacts_group.createChild("text")
                .setAlignment("left-center")
                .setFont("Helvetica.txf")
                .setFontSize(24, 1.0);
        }

        if (!contains(me.altitude_labels, callsign) or me.altitude_labels[callsign] == nil) {
            me.altitude_labels[callsign] = me.contacts_group.createChild("text")
                .setAlignment("left-center")
                .setFont("Helvetica.txf")
                .setFontSize(20, 1.0);
        }

        if (!contains(me.distance_labels, callsign) or me.distance_labels[callsign] == nil) {
            me.distance_labels[callsign] = me.contacts_group.createChild("text")
                .setAlignment("left-center")
                .setFont("Helvetica.txf")
                .setFontSize(16, 1.0);
        }
    },

    updateContactVisual: func(callsign, x, y, blip_color, alt_text, dist_text) {
        me.ensureContactVisual(callsign);

        me.blips[callsign]
            .setColor(blip_color[0], blip_color[1], blip_color[2], blip_color[3])
            .setTranslation(x, y);

        me.callsign_labels[callsign]
            .setTranslation(x + 20, y)
            .setColor(blip_color[0], blip_color[1], blip_color[2], blip_color[3])
            .setText(callsign);

        me.altitude_labels[callsign]
            .setTranslation(x + 20, y + 24)
            .setColor(blip_color[0], blip_color[1], blip_color[2], blip_color[3])
            .setText(alt_text);

        me.distance_labels[callsign]
            .setTranslation(x + 20, y + 44)
            .setColor(blip_color[0], blip_color[1], blip_color[2], blip_color[3])
            .setText(dist_text);
    },

    recolorVisibleContacts: func() {
        var highlight_callsign = me.highlight_callsign_node.getValue() or "";
        foreach (var callsign; keys(me.blips)) {
            var color = (callsign == highlight_callsign) ? [0, 0, 1, 1] : [1, 1, 1, 1];
            if (contains(me.tracked_callsigns, callsign) and me.tracked_callsigns[callsign] != nil) {
                if (me.tracked_callsigns[callsign].ghost == 1) {
                    color = [1, 1, 0, 1];
                }
            }
            me.blips[callsign].setColor(color[0], color[1], color[2], color[3]);
            if (contains(me.callsign_labels, callsign) and me.callsign_labels[callsign] != nil) {
                me.callsign_labels[callsign].setColor(color[0], color[1], color[2], color[3]);
            }
            if (contains(me.altitude_labels, callsign) and me.altitude_labels[callsign] != nil) {
                me.altitude_labels[callsign].setColor(color[0], color[1], color[2], color[3]);
            }
            if (contains(me.distance_labels, callsign) and me.distance_labels[callsign] != nil) {
                me.distance_labels[callsign].setColor(color[0], color[1], color[2], color[3]);
            }
        }
    },

    deleteContactVisual: func(callsign) {
        if (contains(me.blips, callsign) and me.blips[callsign] != nil) {
            me.blips[callsign].del();
            delete(me.blips, callsign);
        }
        if (contains(me.callsign_labels, callsign) and me.callsign_labels[callsign] != nil) {
            me.callsign_labels[callsign].del();
            delete(me.callsign_labels, callsign);
        }
        if (contains(me.altitude_labels, callsign) and me.altitude_labels[callsign] != nil) {
            me.altitude_labels[callsign].del();
            delete(me.altitude_labels, callsign);
        }
        if (contains(me.distance_labels, callsign) and me.distance_labels[callsign] != nil) {
            me.distance_labels[callsign].del();
            delete(me.distance_labels, callsign);
        }
    },

    getMultiplayerTargets: func() {
        var ai_models = me.ai_models_node;
        if (ai_models == nil) return [];

        var mp_nodes = ai_models.getChildren("multiplayer");
        var targets = [];

        foreach (var mp; mp_nodes) {
            var cs_node = mp.getNode("callsign");
            var dist_node = mp.getNode("distance-to-nm");
            var brg_node = mp.getNode("bearing-to");
            var alt_node = mp.getNode("position/altitude-ft");

            var callsign = cs_node != nil ? cs_node.getValue() : nil;
            var distance = dist_node != nil ? dist_node.getValue() : -1;
            var bearing = brg_node != nil ? brg_node.getValue() : -1;
            var alt = alt_node != nil ? alt_node.getValue() : 0;

            if (callsign != nil and callsign != "" and distance >= 0 and bearing >= 0) {
                append(targets, {
                    callsign: callsign,
                    distance: distance,
                    bearing: bearing,
                    alt: alt
                });
            }
        }

        targets = sort(targets, func(a, b) { return a.distance < b.distance; });
        me.last_targets = targets;
        return targets;
    },

    refreshDialogCallsigns: func() {
        me.refreshDialogCallsignsFromTargets(me.getMultiplayerTargets());
    },

    refreshDialogCallsignsFromTargets: func(targets) {
        if (targets == nil) targets = [];
        me.dialog_callsigns = [];

        var selected_callsign = me.highlight_callsign_node.getValue() or "";
        var selected_index = 0;
        var i = 0;

        for (i = 0; i < me.max_dialog_items; i += 1) {
            me.dialog_label_nodes[i].setValue("--");
            me.dialog_callsign_nodes[i].setValue("");
        }

        i = 0;
        foreach (var t; targets) {
            if (i >= me.max_dialog_items) break;

            append(me.dialog_callsigns, t.callsign);
            me.dialog_callsign_nodes[i].setValue(t.callsign);

            var prefix = (t.callsign == selected_callsign) ? ">> " : "   ";
            me.dialog_label_nodes[i]
                .setValue(sprintf("%s%d. %s (%.1f nm)", prefix, i + 1, t.callsign, t.distance));

            if (t.callsign == selected_callsign) {
                selected_index = i;
            }

            i += 1;
        }

        me.dialog_selected_index_node.setIntValue(selected_index);
        me.dialog_count_node.setIntValue(size(me.dialog_callsigns));
    },

    selectDialogIndex: func(index) {
        me.refreshDialogCallsigns();

        if (size(me.dialog_callsigns) == 0) {
            me.highlight_callsign_node.setValue("");
            return;
        }

        if (index < 0) index = 0;
        if (index >= size(me.dialog_callsigns)) index = size(me.dialog_callsigns) - 1;

        me.dialog_selected_index_node.setIntValue(index);
        me.highlight_callsign_node.setValue(me.dialog_callsigns[index]);
        gui.popupTip("Radar target: " ~ me.dialog_callsigns[index]);
    },

    selectCurrentDialogTarget: func() {
        me.refreshDialogCallsigns();

        if (size(me.dialog_callsigns) == 0) {
            me.highlight_callsign_node.setValue("");
            gui.popupTip("No multiplayer pilots found.");
            return;
        }

        var index = me.dialog_selected_index_node.getValue();
        if (index == nil) index = 0;
        if (index < 0) index = 0;
        if (index >= size(me.dialog_callsigns)) index = size(me.dialog_callsigns) - 1;

        var callsign = me.dialog_callsigns[index];
        me.highlight_callsign_node.setValue(callsign);
        gui.popupTip("Radar target: " ~ callsign);
    },

    clearCurrentDialogTarget: func() {
        me.highlight_callsign_node.setValue("");
        gui.popupTip("Radar target cleared.");
    },

    updateRangeRings: func() {
        me.rings_group.removeAllChildren();

        var range = me.range_node.getValue();
        if (range == nil or range <= 0) range = 50;

        var scale = me.radius / range;

        for (var r = 10; r <= range; r += 10) {
            var ring_radius = r * scale;
            var ring = me.rings_group.createChild("path");

            for (var i = 0; i <= me.segments; i += 1) {
                var angle = i * 2 * math.pi / me.segments;
                var x = me.center_x + ring_radius * math.cos(angle);
                var y = me.center_y + ring_radius * math.sin(angle);

                if (i == 0) {
                    ring.moveTo(x, y);
                } else {
                    ring.lineTo(x, y);
                }
            }

            ring.close()
                .setColor(0, 0.5, 0)
                .setStrokeLineWidth(1);
        }
    },

    updateHudTarget: func(current_callsign, current_info, heading, your_alt) {
        if (current_callsign != nil and current_info != nil) {
            me.target_callsign_node.setValue(current_callsign);
            me.target_range_node.setDoubleValue(current_info.distance);
            me.target_bearing_node.setDoubleValue(current_info.bearing);
            me.target_alt_node.setDoubleValue(current_info.alt);

            var rel_brg = current_info.bearing - heading;
            while (rel_brg > 180) rel_brg -= 360;
            while (rel_brg < -180) rel_brg += 360;

            var dz = current_info.alt - your_alt;
            var rng_ft = current_info.distance * 6076.0;
            var elev_deg = 0;
            if (rng_ft > 1) elev_deg = math.atan2(dz, rng_ft) * 180 / math.pi;

            var max_az = 30.0;
            var max_elev = 20.0;
            var hud_x = (rel_brg / max_az) * 80.0;
            var hud_y = (elev_deg / max_elev) * 40.0;

            if (hud_x > 80) hud_x = 80;
            if (hud_x < -80) hud_x = -80;
            if (hud_y > 40) hud_y = 40;
            if (hud_y < -40) hud_y = -40;

            var alpha = me.hud_smoothing_alpha;
            me.smoothed_hud_x = me.smoothed_hud_x + alpha * (hud_x - me.smoothed_hud_x);
            me.smoothed_hud_y = me.smoothed_hud_y + alpha * (hud_y - me.smoothed_hud_y);

            me.target_hud_x_node.setDoubleValue(me.smoothed_hud_x);
            me.target_hud_y_node.setDoubleValue(me.smoothed_hud_y);
        } else {
            me.target_callsign_node.setValue("");
            me.target_range_node.setDoubleValue(-1);
            me.target_bearing_node.setDoubleValue(0);
            me.target_alt_node.setDoubleValue(0);
            me.smoothed_hud_x = 0;
            me.smoothed_hud_y = 0;
            me.target_hud_x_node.setDoubleValue(0);
            me.target_hud_y_node.setDoubleValue(0);
        }
    },

    scheduleNextUpdate: func() {
        if (me.update_scheduled) return;
        me.update_scheduled = 1;
        settimer(func {
            me.update_scheduled = 0;
            me.update();
        }, me.update_interval);
    },

    update: func() {
        var current_time = systime();

        var your_alt = me.position_alt_node != nil ? (me.position_alt_node.getValue() or 0) : 0;
        var heading = me.heading_node != nil ? (me.heading_node.getValue() or 0) : 0;

        var range = me.range_node.getValue();
        if (range == nil or range <= 0) range = 50;

        var highlight_callsign = me.highlight_callsign_node.getValue() or "";
        var up_north = me.up_north_node.getValue();
        var scale = me.radius / range;

        var targets = me.getMultiplayerTargets();
        var active_callsigns = {};
        var target_info_map = {};

        var nearest_callsign = nil;
        var nearest_distance = nil;
        var nearest_info = nil;

        foreach (var t; targets) {
            target_info_map[t.callsign] = t;

            var callsign = t.callsign;
            var distance = t.distance;
            var bearing = t.bearing;
            var mp_alt = t.alt;

            if (callsign != nil and callsign != "" and distance >= 0 and bearing >= 0 and bearing <= 360 and distance > 0) {
                if (nearest_distance == nil or distance < nearest_distance) {
                    nearest_distance = distance;
                    nearest_callsign = callsign;
                    nearest_info = {
                        distance: distance,
                        bearing: bearing,
                        alt: mp_alt
                    };
                }

                if (distance <= range) {
                    active_callsigns[callsign] = 1;

                    var display_bearing = bearing;
                    if (!up_north) {
                        display_bearing = bearing - heading;
                        if (display_bearing < 0) display_bearing += 360;
                        if (display_bearing > 360) display_bearing -= 360;
                    }

                    var rad = display_bearing * FGUK_RADAR_DEG2RAD;
                    var x = me.center_x + (distance * scale * math.sin(rad));
                    var y = me.center_y - (distance * scale * math.cos(rad));

                    me.tracked_callsigns[callsign] = {
                        last_seen: current_time,
                        x: x,
                        y: y,
                        distance: distance,
                        ghost: 0
                    };

                    var blip_color = (callsign == highlight_callsign) ? [0, 0, 1, 1] : [1, 1, 1, 1];
                    var alt_diff = mp_alt - your_alt;
                    var alt_text = sprintf("%+d ft", alt_diff);
                    var dist_text = sprintf("%.1f nm", distance);

                    me.updateContactVisual(callsign, x, y, blip_color, alt_text, dist_text);
                } else {
                    if (contains(me.tracked_callsigns, callsign)) {
                        delete(me.tracked_callsigns, callsign);
                    }
                    me.deleteContactVisual(callsign);
                }
            }
        }

        var stale_callsigns = [];
        foreach (var callsign; keys(me.tracked_callsigns)) {
            if (!contains(active_callsigns, callsign)) {
                var tracked = me.tracked_callsigns[callsign];
                var time_since_last_seen = current_time - tracked.last_seen;

                if (time_since_last_seen < me.ghost_timeout) {
                    tracked.ghost = 1;
                    me.updateContactVisual(callsign, tracked.x, tracked.y, [1, 1, 0, 1], "N/A", sprintf("%.1f nm", tracked.distance));
                } else {
                    append(stale_callsigns, callsign);
                }
            }
        }

        foreach (var stale; stale_callsigns) {
            me.deleteContactVisual(stale);
            delete(me.tracked_callsigns, stale);
        }

        var current_callsign = highlight_callsign;
        var current_info = nil;

        if (current_callsign == nil or current_callsign == "" or !contains(active_callsigns, current_callsign)) {
            current_callsign = nearest_callsign;
            current_info = nearest_info;
        } else if (contains(target_info_map, current_callsign)) {
            current_info = target_info_map[current_callsign];
        }

        me.updateHudTarget(current_callsign, current_info, heading, your_alt);

        if (current_time - me.last_dialog_refresh >= me.dialog_refresh_interval) {
            me.last_dialog_refresh = current_time;
            me.refreshDialogCallsignsFromTargets(targets);
        }

        me.scheduleNextUpdate();
    },

    initializeMultiplayerData: func() {
        settimer(func {
            props.globals.getNode("/sim/multiplay/generic/string[0]", 1).setValue("refresh");
            var retryCount = 0;
            var maxRetries = 10;
            var retryInterval = 5;

            var checkAndOpenPilotList = func {
                retryCount += 1;
                var ai_models = me.ai_models_node;
                var mp_nodes = ai_models != nil ? ai_models.getChildren("multiplayer") : [];

                if (size(mp_nodes) > 0 or retryCount >= maxRetries) {
                    if (size(mp_nodes) > 0) {
                        multiplayer.dialog.show();
                        settimer(func {
                            fgcommand("dialog-close", props.Node.new({ "dialog-name": "MultiplayerPilots" }));
                        }, 5);
                    }
                } else {
                    settimer(checkAndOpenPilotList, retryInterval);
                }
            };

            checkAndOpenPilotList();
        }, 5);
    }
};

setlistener("/sim/signals/fdm-initialized", func {
    fgukradar_instance = RadarInstrument.new();
});

var fgukradar_dialog_ok = func {
    var range = props.globals.getNode("/instrumentation/FGUKRadar/range-nm").getValue();
    if (range != nil and range > 0) {
        props.globals.getNode("/instrumentation/FGUKRadar/range-nm").setDoubleValue(range);
    } else {
        props.globals.getNode("/instrumentation/FGUKRadar/range-nm").setDoubleValue(50);
    }

    var callsign = props.globals.getNode("/instrumentation/FGUKRadar/highlight-callsign").getValue() or "";
    props.globals.getNode("/instrumentation/FGUKRadar/highlight-callsign").setValue(callsign);

    gui.popupTip("Radar settings saved.");
    fgcommand("dialog-close", props.Node.new({ "dialog-name": "FGUKRadarSettings" }));
};

var fgukradar_dialog_refresh = func {
    if (fgukradar_instance != nil) {
        fgukradar_instance.refreshDialogCallsigns();
        gui.popupTip("Radar target list refreshed.");
    }
};

var fgukradar_show_dialog = func {
    if (fgukradar_instance == nil) {
        gui.popupTip("Radar not initialized yet.");
        return;
    }

    fgukradar_dialog_refresh();
    fgcommand("dialog-show", props.Node.new({ "dialog-name": "radar-target" }));
};

var fgukradar_dialog_select = func {
    if (fgukradar_instance != nil)
        fgukradar_instance.selectCurrentDialogTarget();
};

var fgukradar_dialog_clear = func {
    if (fgukradar_instance != nil)
        fgukradar_instance.clearCurrentDialogTarget();
};

var fgukradar_dialog_select_index = func(index) {
    if (fgukradar_instance != nil)
        fgukradar_instance.selectDialogIndex(index);
};
