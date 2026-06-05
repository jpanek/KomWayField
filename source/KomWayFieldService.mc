// source/KomWayFieldService.mc

import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.PersistedContent;
import Toybox.Time;
import Toybox.Time.Gregorian;


(:background)
class KomWayFieldService extends System.ServiceDelegate {

    const KEY_LATEST_COORDS = "latestCoords";
    const WEATHER_URL = "https://kom-way.cyclingdatahub.com/api/v1/garmin-weather";
    const RETRY_INTERVAL = 300;


    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void { 
        var coords = Storage.getValue(KEY_LATEST_COORDS);

        if (coords == null) {
            Background.exit({
                "error" => "no_coords"
            });
        } else {
            var c = coords as Lang.Dictionary;
            var lat = c["lat"] as Lang.Float;
            var lon = c["lon"] as Lang.Float;

            var body = {
                "lat" => lat,
                "lon" => lon
            };

            var options = {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Accept" => "application/json"
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            };

            Communications.makeWebRequest(
                WEATHER_URL,
                body,
                options,
                method(:onWeatherResponse)
            );
        }
    }

    // Function: Handling of the API response
    function onWeatherResponse(
        responseCode as Lang.Number,
        data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null
    ) as Void {
        var payload = null;

        if (responseCode == 200 && data != null && data instanceof Lang.Dictionary) {
            var json = data as Lang.Dictionary;

            payload = {
                "t"    => json["t"],
                "int"  => json["int"],
                "ws"   => json["ws"],
                "wg"   => json["wg"],
                "wd"   => json["wd"],
                "wdr"  => json["wdr"],
                "temp" => json["temp"],
                "rain" => json["rain"]
            };

            System.println("onWeatherResponse success path");
            System.println("responseCode: " + responseCode);
            System.println("json[t]: " + json["t"]);
            System.println("json[int]: " + json["int"]);

            scheduleNextWeatherRefresh(json["t"], json["int"]);

        } else {
            payload = {
                "error" => "request_failed",
                "code"  => responseCode,
                "t"     => 0,
                "ws"    => -1.0,
                "wg"    => -1.0,
                "wd"    => -1.0,
                "wdr"   => -1.0,
                "temp"  => -999.0,
                "rain"  => -1.0
            };

            var nowEpoch = Time.now().value().toNumber();

            System.println("onWeatherResponse failure path");
            System.println("responseCode: " + responseCode);
            System.println("retry from nowEpoch: " + nowEpoch);
            System.println("RETRY_INTERVAL: " + RETRY_INTERVAL);

            scheduleNextWeatherRefresh(nowEpoch, RETRY_INTERVAL);

        }

        Background.exit(payload);
    }

    // Function: scheduler of when to make the next API call    
    function scheduleNextWeatherRefresh(t as Lang.Number, interval as Lang.Number) as Void {
        var nextEpoch = t + interval + 1;
        var nowEpoch = Time.now().value().toNumber();

        System.println("---- scheduleNextWeatherRefresh ----");
        System.println("input t: " + t);
        System.println("input interval: " + interval);
        System.println("computed nextEpoch: " + nextEpoch);
        System.println("current nowEpoch: " + nowEpoch);

        var lastRun = Background.getLastTemporalEventTime();
        if (lastRun != null) {
            var lastRunEpoch = lastRun.value().toNumber();
            var minAllowedEpoch = lastRunEpoch + RETRY_INTERVAL + 1;

            System.println("lastRunEpoch: " + lastRunEpoch);
            System.println("minAllowedEpoch: " + minAllowedEpoch);

            if (nextEpoch < minAllowedEpoch) {
                System.println("nextEpoch too early, clamping to minAllowedEpoch");
                nextEpoch = minAllowedEpoch;
            }
        } else {
            System.println("lastRunEpoch: null");
        }

        System.println("final nextEpoch: " + nextEpoch);
        System.println("final delta from now: " + (nextEpoch - nowEpoch));

        //var nextMoment = Gregorian.moment({ :seconds => nextEpoch });
        var nextMoment = new Time.Moment(nextEpoch);

        System.println("registering temporal event now...");
        Background.registerForTemporalEvent(nextMoment);
        System.println("registerForTemporalEvent succeeded");
    }

}