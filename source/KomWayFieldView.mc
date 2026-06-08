// source/KomWayFieldView.mc

import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Time;

class KomWayFieldView extends WatchUi.DataField {

    hidden var viewData as Lang.Dictionary;
    hidden var weatherKickoffRequested as Lang.Boolean;
    hidden var gpsReady as Lang.Boolean;
    var gpsMissCount = 0;
    var gpsMissCountMax = 5;

    // Layout
    const TOP_Y_RATIO = 0.17;
    const CENTER_Y_RATIO = 0.50;
    const BOTTOM_Y_RATIO = 0.90;

    // Chevron style
    //const CHEVRON_SIZE = 16.0; // 840
    const CHEVRON_SIZE = 21.0;
    const CHEVRON_SPACING = 12.0;
    //const CHEVRON_PEN_WIDTH = 5.0; // 840
    const CHEVRON_PEN_WIDTH = 6.0;
    const CHEVRON_HEAD_ANGLE = 2.35619;

    var smoothedHeadingDeg = null;

    // variable to load and cache arrows
    var cachedArrowRes = null;
    var cachedArrowBmp = null;

    // 8-point compass labels
    const COMPASS_8 = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

    function initialize() {
        DataField.initialize();

        gpsReady = false;
        weatherKickoffRequested = false;

        viewData = {
            "heading"            => null,
            "WindCompass"        => "-",
            "WindAngleFrom"      => null,
            "WindAngleTo"        => null,
            "WindAngleToRounded" => null
        };
    }

    function onLayout(dc as Dc) as Void {
    }

    /*======================================================================================================
                            Helper functions below
    ======================================================================================================*/

    // 1. Normalize degrees
    private function normalizeDeg(angle as Lang.Float) as Lang.Float {
        var a = angle;

        while (a < 0.0) {
            a += 360.0;
        }

        while (a >= 360.0) {
            a -= 360.0;
        }

        return a;
    }

    // 2. Round to nearest 45 degree angle
    private function roundToNearest45(angle as Lang.Float) as Lang.Float {
        var normalized = normalizeDeg(angle);
        var roundedStep = Math.round(normalized / 45.0);
        var roundedAngle = roundedStep.toFloat() * 45.0;
        return normalizeDeg(roundedAngle);
    }

    // 3. Return the nearest compass code name (N, NE, E, ....)
    private function windDirToCompass8(angle as Lang.Float) as Lang.String {
        var rounded = roundToNearest45(angle);
        var index = (rounded / 45.0).toNumber();

        if (index >= 8) {
            index = 0;
        }

        return COMPASS_8[index];
    }

    // 4. Convert rider-relative FLOW direction degrees to screen radians. 0 -> up, 90 -> right, 180 -> down, 270 -> left
    private function relativeFlowDegToScreenRad(relativeTo as Lang.Float) as Lang.Float {
        var screenDeg = 90.0 - relativeTo;
        return normalizeDeg(screenDeg) * (Math.PI / 180.0);
    }

    // 5. Smooth heading while handling 0/360 wrap correctly
    private function smoothHeadingDeg(newHeadingDeg as Lang.Float) as Lang.Float {
        var alpha = 0.25; // lower = smoother, higher = more responsive

        if (smoothedHeadingDeg == null) {
            smoothedHeadingDeg = newHeadingDeg;
            return smoothedHeadingDeg;
        }

        var delta = newHeadingDeg - smoothedHeadingDeg;

        if (delta > 180.0) {
            delta -= 360.0;
        } else if (delta < -180.0) {
            delta += 360.0;
        }

        smoothedHeadingDeg = normalizeDeg(smoothedHeadingDeg + (alpha * delta));
        return smoothedHeadingDeg;
    }

    /*======================================================================================================
                        Compute block
    ======================================================================================================*/

    function compute(info as Activity.Info) as Void {

        var weatherData = getApp().getLatestWeather();

        // Catching and saving GPS location
        if ((info has :currentLocation) && info.currentLocation != null) {
            var pos = info.currentLocation.toDegrees();

            if (pos != null && pos[0] != 0 && pos[1] != 0) {
                gpsMissCount = 0;
                gpsReady = true;

                getApp().saveLatestCoords({
                    "lat" => pos[0],
                    "lon" => pos[1],
                    "source" => "activity"
                });

                if (!weatherKickoffRequested) {
                    getApp().startWeatherRefreshNow();
                    weatherKickoffRequested = true;
                }
            } else {
                gpsMissCount += 1;
                if (gpsMissCount >= gpsMissCountMax) {
                    gpsReady = false;
                }
            }

        } else {
            gpsMissCount += 1;
            if (gpsMissCount >= gpsMissCountMax) {
                gpsReady = false;
            }
        }

        if (!(info has :currentHeading) || info.currentHeading == null) {
            viewData["heading"] = null;
            viewData["WindAngleFrom"] = null;
            viewData["WindAngleTo"] = null;
            viewData["WindAngleToRounded"] = null;
            viewData["WindCompass"] = "-";
            return;
        }

        // take the raw heading and smooth it out a bit (it can be noisy)
        var rawHeadingDeg = normalizeDeg(Math.toDegrees(info.currentHeading));
        var headingDeg = smoothHeadingDeg(rawHeadingDeg);


        var windDir = weatherData["wd"] as Lang.Float;

        viewData["heading"] = headingDeg;
        viewData["WindCompass"] = windDirToCompass8(windDir);

        // Relative source direction around rider:
        // 0 = from front, 90 = from right, 180 = from back, 270 = from left
        var relativeFrom = normalizeDeg(windDir - headingDeg);

        // Convert source direction to flow direction
        var relativeTo = normalizeDeg(relativeFrom + 180.0);

        // Snap flow direction to 8 sectors for cleaner chevrons
        var relativeToRounded = roundToNearest45(relativeTo);

        viewData["WindAngleFrom"] = relativeFrom;
        viewData["WindAngleTo"] = relativeTo;
        viewData["WindAngleToRounded"] = relativeToRounded;

        // ################################### DEBUG ONLY: ###################################        
        var riderHeadingCompass = windDirToCompass8(headingDeg);
        var windCompass = windDirToCompass8(windDir);
        var fromCompass = windDirToCompass8(relativeFrom);
        var toCompass = windDirToCompass8(relativeToRounded);

        System.println(
            "HEAD " + riderHeadingCompass +
            " | WIND " + windCompass +
            " | FROM rider=" + relativeFrom.format("%.0f") + " " + fromCompass +
            " | ARROW to=" + relativeToRounded.format("%.0f") + " " + toCompass
        );

    }


    /*======================================================================================================
                        onUpdate block
    ======================================================================================================*/
    function onUpdate(dc as Dc) as Void {
        var weatherData = getApp().getLatestWeather();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = (width / 2).toNumber();

        var bgColor = getBackgroundColor();
        var textColor = (bgColor == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;

        dc.setColor(bgColor, bgColor);
        dc.clear();

        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);

        // ------------------- Negative scenario: START ------------------------------
        var tempObj = weatherData["temp"];
        var weatherReady = false;

        if (tempObj != null) {
            var tempVal = tempObj as Lang.Float;
            if (tempVal != null && tempVal > -999.0) {
                weatherReady = true;
            }
        }

        // show when GPS is not ready
        if (!gpsReady) {
            dc.drawText(
                centerX,
                (height / 2).toNumber(),
                Graphics.FONT_TINY,
                "Waiting for GPS",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        // show when Weather is not ready
        if (!weatherReady) {
            dc.drawText(
                centerX,
                (height / 2 ).toNumber(),
                Graphics.FONT_TINY,
                "Loading weather",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        // ------------------- Negative scenario: END ------------------------------



        // ------------- Drawing things on display: START --------------------------
        var windCompass = viewData["WindCompass"] as Lang.String;
        var ws = weatherData["ws"] as Lang.Float;
        var wg = weatherData["wg"] as Lang.Float;
        var temp = weatherData["temp"] as Lang.Float;
        var rain = weatherData["rain"] as Lang.Float;
        var weatherTime = weatherData["t"] as Lang.Number;

        var mainStr = windCompass + " " + ws.format("%.0f");
        var unitStr = "kmh";

        var mainFont = Graphics.FONT_MEDIUM;
        var unitFont = Graphics.FONT_XTINY;

        var gap = 4;

        var mainW = dc.getTextWidthInPixels(mainStr, mainFont);
        var unitW = dc.getTextWidthInPixels(unitStr, unitFont);
        var totalW = mainW + gap + unitW;

        var baseX = centerX - (totalW / 2);
        var y = (height * TOP_Y_RATIO).toNumber();
        var unitY = y - 2;

        // ----------------------------------------------------------------------------
        // [Section 1]: Large wind direction + wind speed
        // large NW + number
        dc.drawText(
            baseX,
            y,
            mainFont,
            mainStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
        // tiny kmh
        dc.drawText(
            baseX + mainW + gap,
            unitY,
            unitFont,
            unitStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );


        // ----------------------------------------------------------------------------
        // [Section 2]: Drawing the arrow bitmap instead of chevrons
        if (viewData["WindAngleToRounded"] != null) {
            var angle = viewData["WindAngleToRounded"] as Lang.Float;
            var arrowRes = null;

            // pick the file name
            if (bgColor == Graphics.COLOR_BLACK) {
                if (angle == 0.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_0;
                } else if (angle == 45.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_45;
                } else if (angle == 90.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_90;
                } else if (angle == 135.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_135;
                } else if (angle == 180.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_180;
                } else if (angle == 225.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_225;
                } else if (angle == 270.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_270;
                } else if (angle == 315.0) {
                    arrowRes = Rez.Drawables.Arrow_60_white_315;
                }
            } else {
                if (angle == 0.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_0;
                } else if (angle == 45.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_45;
                } else if (angle == 90.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_90;
                } else if (angle == 135.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_135;
                } else if (angle == 180.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_180;
                } else if (angle == 225.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_225;
                } else if (angle == 270.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_270;
                } else if (angle == 315.0) {
                    arrowRes = Rez.Drawables.Arrow_60_black_315;
                }
            }

            if (arrowRes != null) {
                if (cachedArrowRes != arrowRes || cachedArrowBmp == null) {
                    cachedArrowRes = arrowRes;
                    cachedArrowBmp = WatchUi.loadResource(arrowRes);
                }

                var arrowSize = 60;
                var arrowX = (centerX - (arrowSize / 2)).toNumber();
                var arrowY = ((height * CENTER_Y_RATIO) - (arrowSize / 2) + 6).toNumber();

                dc.drawBitmap(arrowX, arrowY, cachedArrowBmp);
            }
        }

        // ----------------------------------------------------------------------------
        // [Section 3]: Bottom line with gusts, temperature, rain and minutes since update
        var nowEpoch = Time.now().value().toNumber();
        var ageMinutes = ((nowEpoch - weatherTime) / 60).toNumber();
        if (ageMinutes < 0) {
            ageMinutes = 0;
        }

        var detailStr =
            "G" + wg.format("%.0f") +
            "  " + temp.format("%.0f") + "°" +
            "  R" + rain.format("%.1f") +
            "  " + ageMinutes.format("%d") + "m";
        dc.drawText(
            centerX,
            (height * BOTTOM_Y_RATIO).toNumber(),
            Graphics.FONT_TINY,
            detailStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

    }

}