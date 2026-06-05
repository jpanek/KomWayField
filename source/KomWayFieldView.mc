// source/KomWayFieldView.mc

import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

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

        // ################################### DEBUG ONLY: ###################################
        /*
        if (true){
            getApp().saveLatestCoords({
                "lat" => 50.103,
                "lon" => 14.403,
                "source" => "debug"
            });
            gpsReady = true;
        }
        */

        // ################################### DEBUG ONLY: ###################################

        if (!(info has :currentHeading) || info.currentHeading == null) {
            viewData["heading"] = null;
            viewData["WindAngleFrom"] = null;
            viewData["WindAngleTo"] = null;
            viewData["WindAngleToRounded"] = null;
            viewData["WindCompass"] = "-";
            return;
        }

        var headingDeg = normalizeDeg(Math.toDegrees(info.currentHeading));
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

        // ################################### DEBUG ONLY: ###################################
        //weatherReady = true;
        // ################################### DEBUG ONLY: ###################################

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

        /*
        var windStr = windCompass + " " + ws.format("%.0f");

        dc.drawText(
            centerX,
            (height * TOP_Y_RATIO).toNumber(),
            Graphics.FONT_MEDIUM,
            windStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        */

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



        if (viewData["WindAngleToRounded"] != null) {
            var relativeToRounded = viewData["WindAngleToRounded"] as Lang.Float;
            var angle = relativeFlowDegToScreenRad(relativeToRounded);

            drawChevron(
                dc,
                centerX,
                (height * CENTER_Y_RATIO).toNumber(),
                angle
            );
        }

        dc.drawText(
            centerX,
            (height * BOTTOM_Y_RATIO).toNumber(),
            Graphics.FONT_XTINY,
            detailStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

    }

    private function drawChevron(dc as Dc, cx as Lang.Number, cy as Lang.Number, angle as Lang.Float) as Void {
        var dirX = Math.cos(angle);
        var dirY = -Math.sin(angle);

        dc.setPenWidth(CHEVRON_PEN_WIDTH);

        for (var i = 0; i < 2; i++) {
            var shift = (i == 0) ? (-CHEVRON_SPACING / 2.0) : (CHEVRON_SPACING / 2.0);

            var chevronCenterX = cx.toFloat() + dirX * shift;
            var chevronCenterY = cy.toFloat() + dirY * shift;

            var tipX = chevronCenterX + dirX * (CHEVRON_SIZE / 2.0);
            var tipY = chevronCenterY + dirY * (CHEVRON_SIZE / 2.0);

            var leftX = tipX + Math.cos(angle + CHEVRON_HEAD_ANGLE) * CHEVRON_SIZE;
            var leftY = tipY - Math.sin(angle + CHEVRON_HEAD_ANGLE) * CHEVRON_SIZE;

            var rightX = tipX + Math.cos(angle - CHEVRON_HEAD_ANGLE) * CHEVRON_SIZE;
            var rightY = tipY - Math.sin(angle - CHEVRON_HEAD_ANGLE) * CHEVRON_SIZE;

            dc.drawLine(tipX.toNumber(), tipY.toNumber(), leftX.toNumber(), leftY.toNumber());
            dc.drawLine(tipX.toNumber(), tipY.toNumber(), rightX.toNumber(), rightY.toNumber());
        }
    }

}