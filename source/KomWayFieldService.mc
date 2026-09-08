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
    const RETRY_INTERVAL = 305;
    var debug_mode = false;

    // unique device ID
    var deviceSettings = System.getDeviceSettings();
    var deviceId = deviceSettings.uniqueIdentifier;


    function initialize() {
        ServiceDelegate.initialize();
    }

    // Function: The actual calling of the event from the watch
    function onTemporalEvent() as Void { 
        try {
            var coords = Storage.getValue(KEY_LATEST_COORDS);

            if (coords == null) {
                Background.exit({
                    "error" => "no_coords"
                });
            } else {
                var c = coords as Lang.Dictionary;
                var lat = c["lat"] as Lang.Float;
                var lon = c["lon"] as Lang.Float;

                if (deviceId == null) {
                    deviceId = -1;
                }
                var body = {
                    "lat" => lat,
                    "lon" => lon,
                    "device_id" => deviceId
                };
                System.print("Body of http request: " + body);

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
        catch (e) {
            System.println("Exception in onTemporalEvent: " + e);
            var nowEpoch = Time.now().value().toNumber();

            scheduleNextWeatherRefresh(nowEpoch, RETRY_INTERVAL);

            Background.exit({
                "error" => "background_exception"
            });
        }

    }

    // Function: Handling of the API response
    function onWeatherResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null ) as Void {
        try {
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
        } catch(e){
            System.println("Exception in onWeatherResponse: " + e);

            var nowEpoch = Time.now().value().toNumber();
            scheduleNextWeatherRefresh(nowEpoch, RETRY_INTERVAL);

            Background.exit({
                "error" => "response_exception"
            }); 
        } 
    }

    // Function: scheduler of when to make the next API call    
    function scheduleNextWeatherRefresh(t as Lang.Number, interval as Lang.Number) as Void {
        try{
            var nextEpoch = t + interval + 1;
            var nowEpoch = Time.now().value().toNumber();

            // Debug print
            if (debug_mode) {
                System.println("---- scheduleNextWeatherRefresh ----");
                System.println("input t: " + t);
                System.println("input interval: " + interval);
                System.println("computed nextEpoch: " + nextEpoch);
                System.println("current nowEpoch: " + nowEpoch);
            }

            var lastRun = Background.getLastTemporalEventTime();
            if (lastRun != null) {
                var lastRunEpoch = lastRun.value().toNumber();
                var minAllowedEpoch = lastRunEpoch + RETRY_INTERVAL + 1;

                // Debug print
                if (debug_mode) {
                    System.println("lastRunEpoch: " + lastRunEpoch);
                    System.println("minAllowedEpoch: " + minAllowedEpoch);
                }

                if (nextEpoch < minAllowedEpoch) {
                    System.println("nextEpoch too early, clamping to minAllowedEpoch");
                    nextEpoch = minAllowedEpoch;
                }
            } else {
                System.println("lastRunEpoch: null");
            }

            //var nextMoment = Gregorian.moment({ :seconds => nextEpoch });
            var nextMoment = new Time.Moment(nextEpoch);

            System.println("registering temporal event now...");
            Background.registerForTemporalEvent(nextMoment);
            System.println("registerForTemporalEvent succeeded");
        } catch(e) {
            System.println("scheduleNextWeatherRefresh failed: " + e);
        }
    }

}