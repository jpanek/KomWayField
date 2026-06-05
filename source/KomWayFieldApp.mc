// source/KomWayFieldApp.mc

import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Time;

class KomWayFieldApp extends Application.AppBase {

    const KEY_LATEST_COORDS = "latestCoords";

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
        WatchUi.requestUpdate();
    }

    function startWeatherRefreshNow() as Void {
        // Function: triggered from View.mc to fire off the background API call in Service.mc
        Background.registerForTemporalEvent(Time.now());
    }

    // Getter and Setter of latest weather data
    function getLatestWeather() as Lang.Dictionary {
        return latestWeather;
    }

    function setLatestWeather(data as Lang.Dictionary) as Void {
        latestWeather = data;
    }

    // Getter and Setter of latest GPS coordinates (they'll come from View.mc and Service.mc will take them)
    function getLatestCoords() as Lang.Dictionary {
        // get LatestCoords from memory (in-app)
        return latestCoords;
    }

    function saveLatestCoords(data as Lang.Dictionary) as Void {
        // SAVE latest coordinates to memory and persistent storage
        latestCoords = data;
        Storage.setValue(KEY_LATEST_COORDS, data);
    }

    function loadLatestCoords() as Lang.Dictionary {
        // LOAD latest coordinates from memory
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