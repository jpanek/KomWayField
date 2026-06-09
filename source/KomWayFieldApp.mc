// source/KomWayFieldApp.mc

import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Time;

class KomWayFieldApp extends Application.AppBase {

    const KEY_LATEST_COORDS  = "latestCoords";
    const KEY_LATEST_WEATHER = "latestWeather";

    hidden var latestWeather as Lang.Dictionary;
    hidden var latestCoords as Lang.Dictionary;

    function initialize() {
        AppBase.initialize();

        latestWeather = {
            "t"    => 0,
            "int"  => 0,
            "ws"   => -1.0,
            "wg"   => -1.0,
            "wd"   => -1.0,
            "wdr"  => -1.0,
            "temp" => -999.0,
            "rain" => -1.0
        };

        latestCoords = {
            "lat" => 50.0755,
            "lon" => 14.4378,
            "source" => "fallback"
        };

        loadLatestCoords();
        loadLatestWeather();
    }

    function onStart(state as Lang.Dictionary or Null) as Void {
    }

    function onStop(state as Lang.Dictionary or Null) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new KomWayFieldView() ];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [ new KomWayFieldService() ];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        if (!(data instanceof Lang.Dictionary)) {
            System.println("onBackgroundData: null or non-dictionary payload");
            return;
        }

        var weather = data as Lang.Dictionary;
        var tempObj = weather["temp"];

        if (tempObj == null) {
            System.println("onBackgroundData: payload missing temp");
            return;
        }

        var temp = tempObj as Lang.Float;
        if (temp == null || temp <= -999.0) {
            System.println("onBackgroundData: ignoring invalid weather payload");
            return;
        }

        latestWeather = weather;
        saveLatestWeather(weather);
        WatchUi.requestUpdate();
    }

    function startWeatherRefreshNow() as Void {
        var lastRun = Background.getLastTemporalEventTime();

        try {
            if (lastRun == null) {
                Background.registerForTemporalEvent(Time.now());
                return;
            }

            var earliestAllowed = lastRun.add(new Time.Duration(5 * 60 + 1));
            var nowMoment = Time.now();

            if (nowMoment.value() >= earliestAllowed.value()) {
                Background.registerForTemporalEvent(nowMoment);
            } else {
                Background.registerForTemporalEvent(earliestAllowed);
            }

        } catch(e) {
            System.println("startWeatherRefreshNow failed: " + e.toString());
        }
    }

    function getLatestWeather() as Lang.Dictionary {
        return latestWeather;
    }

    function setLatestWeather(data as Lang.Dictionary) as Void {
        latestWeather = data;
    }

    function saveLatestWeather(data as Lang.Dictionary) as Void {
        latestWeather = data;

        try {
            Storage.setValue(KEY_LATEST_WEATHER, data);
        } catch(e) {
            System.println("saveLatestWeather failed: " + e.toString());
        }
    }

    function loadLatestWeather() as Lang.Dictionary {
        var stored = Storage.getValue(KEY_LATEST_WEATHER) as Lang.Dictionary;

        if (stored != null) {
            latestWeather = stored;
        }

        return latestWeather;
    }

    function getLatestCoords() as Lang.Dictionary {
        return latestCoords;
    }

    function saveLatestCoords(data as Lang.Dictionary) as Void {
        latestCoords = data;
        Storage.setValue(KEY_LATEST_COORDS, data);
    }

    function loadLatestCoords() as Lang.Dictionary {
        var stored = Storage.getValue(KEY_LATEST_COORDS) as Lang.Dictionary;

        if (stored != null) {
            latestCoords = stored;
        }

        return latestCoords;
    }
}

function getApp() as KomWayFieldApp {
    return Application.getApp() as KomWayFieldApp;
}