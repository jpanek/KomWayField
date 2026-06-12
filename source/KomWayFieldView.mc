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
    hidden var lastWeatherRefreshRequestEpoch as Lang.Number or Null;
    hidden var gpsReady as Lang.Boolean;
    var gpsMissCount = 0;
    var gpsMissCountMax = 5;

    // Layout
    const TOP_Y_RATIO = 0.17;
    const CENTER_Y_RATIO = 0.50;
    const BOTTOM_Y_RATIO = 0.90;

    var smoothedHeadingDeg = null;

    // variable to load and cache arrows
    var cachedArrowRes = null;
    var cachedArrowBmp = null;

    // 8-point compass labels
    const COMPASS_8 = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

    function initialize() {
        DataField.initialize();

        gpsReady = false;
        lastWeatherRefreshRequestEpoch = null;

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

    // 6. Loading dots 
    function getLoadingDots() as Lang.String {
        var sec = Time.now().value().toNumber() % 3;

        if (sec == 0) {
            return ".";
        } else if (sec == 1) {
            return "..";
        } else {
            return "...";
        }
    }

    /*======================================================================================================
                        Compute block
    ======================================================================================================*/

    function compute(info as Activity.Info) as Void {

        var weatherData = getApp().getLatestWeather();
        var nowEpoch = Time.now().value().toNumber();

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

                var weatherTime = weatherData["t"] as Lang.Number;
                var shouldRefresh = false;

                if (weatherTime == null || weatherTime <= 0) {
                    shouldRefresh = true;
                } else {
                    var ageMinutes = ((nowEpoch - weatherTime) / 60).toNumber();
                    if (ageMinutes > 15) {
                        shouldRefresh = true;
                    }
                }

                if (shouldRefresh) {
                    if (lastWeatherRefreshRequestEpoch == null ||
                        (nowEpoch - lastWeatherRefreshRequestEpoch) >= 305) {
                        getApp().startWeatherRefreshNow();
                        lastWeatherRefreshRequestEpoch = nowEpoch;
                    }
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

        var rawHeadingDeg = normalizeDeg(Math.toDegrees(info.currentHeading));
        var headingDeg = smoothHeadingDeg(rawHeadingDeg);

        var windDir = weatherData["wd"] as Lang.Float;

        viewData["heading"] = headingDeg;
        viewData["WindCompass"] = windDirToCompass8(windDir);

        var relativeFrom = normalizeDeg(windDir - headingDeg);
        var relativeTo = normalizeDeg(relativeFrom + 180.0);
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

        var weatherTime = weatherData["t"] as Lang.Number;
        var nowEpoch = Time.now().value().toNumber();
        var ageMinutes = 999999;

        if (weatherTime != null) {
            ageMinutes = ((nowEpoch - weatherTime) / 60).toNumber();
            if (ageMinutes < 0) {
                ageMinutes = 0;
            }
        }

        //var weatherStale = (ageMinutes > 2 * 60); // weather more than 2 hours old
        var weatherExpired = (ageMinutes > 24 * 60); // weather more than 1 day old

        // show when GPS is not ready
        if (!gpsReady) {
            dc.drawText(
                centerX,
                (height / 2 - 2).toNumber(),
                Graphics.FONT_TINY,
                "Waiting for GPS",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.drawText(
                centerX,
                ((height / 2) + 10).toNumber(),
                Graphics.FONT_TINY,
                getLoadingDots(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        // show when Weather is not ready at all
        if (!weatherReady || weatherExpired) {
            dc.drawText(
                centerX,
                (height / 2 - 2).toNumber(),
                Graphics.FONT_TINY,
                "Loading weather",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.drawText(
                centerX,
                ((height / 2) + 10).toNumber(),
                Graphics.FONT_TINY,
                getLoadingDots(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        // ------------------- Negative scenario: END ------------------------------


        // ------------- Drawing things on display: START --------------------------
        var useSmallArrow = (height < 90 || width < 140); // true if screen is smaller
        var useSmallFont = (height < 65) || (dc.getFontHeight(Graphics.FONT_TINY) > 19); // for small screens (830 or old versions with large tiny font)

        /*
        System.println("height " + height);
        System.println("width " + width);
        System.println("tiny font " + dc.getFontHeight(Graphics.FONT_TINY));
        System.println("xtiny font " + dc.getFontHeight(Graphics.FONT_XTINY));
        */


        /*
        10 field layout (h x w):
            1040:  92 x 140
            840:   66 x 122
            830:   63 x 122
            1030:  93 x 140
        */

        // -------------------- Top row: Wind direction, wind speed --------------------------------------------
        var windCompass = viewData["WindCompass"] as Lang.String;
        var ws = weatherData["ws"] as Lang.Float;

        var moveFromTop = useSmallArrow ? 6 : 3;

        var y = (height * TOP_Y_RATIO).toNumber();
        var padX = 2;

        // Use FONT_LARGE for text, FONT_NUMBER_MILD for numbers
        var compassFont = Graphics.FONT_MEDIUM;
        var speedFont = Graphics.FONT_NUMBER_MILD;
        var unitFont = Graphics.FONT_XTINY;

        // Top Left: Wind Direction
        dc.drawText(
            padX,
            y,
            compassFont,
            windCompass,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Top Right: Speed + Unit (Maintained Font Hierarchy)
        var speedStr = ws.format("%.0f");
        
        var speedW = dc.getTextWidthInPixels(speedStr, speedFont);
        var unitW = dc.getTextWidthInPixels("km", unitFont);
        var gap = 2;
        var totalBlockW = speedW + gap + unitW;
        
        // Calculate start position for right-aligned block
        var startX = width - padX - totalBlockW;
        var unitX = startX + speedW + gap;

        // Speed of wind
        dc.drawText(
            startX,
            y + moveFromTop,
            speedFont,
            speedStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Draw "km"
        dc.drawText(
            unitX,
            y - 6,
            unitFont,
            "km",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Draw "h"
        dc.drawText(
            unitX + (unitW / 3),
            y + 6, // Shift down
            unitFont,
            "h",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // -------------------- Center: Arrows --------------------------------------------
        if (viewData["WindAngleToRounded"] != null) {
            var angle = viewData["WindAngleToRounded"] as Lang.Float;
            var arrowRes = null;
            
            var moveArrowLeft = 0;
            if (useSmallFont){
                // on small tiny screens (*30 series) better to move the arrow a bit to the left
                moveArrowLeft = 4;
            }
            
            var arrowSize = useSmallArrow ? 48 : 60;

            if (bgColor == Graphics.COLOR_BLACK) {
                if (arrowSize == 48) {
                    if (angle == 0.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_0;
                    } else if (angle == 45.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_45;
                    } else if (angle == 90.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_90;
                    } else if (angle == 135.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_135;
                    } else if (angle == 180.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_180;
                    } else if (angle == 225.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_225;
                    } else if (angle == 270.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_270;
                    } else if (angle == 315.0) {
                        arrowRes = Rez.Drawables.Arrow_48_white_315;
                    }
                } else {
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
                }
            } else {
                if (arrowSize == 48) {
                    if (angle == 0.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_0;
                    } else if (angle == 45.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_45;
                    } else if (angle == 90.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_90;
                    } else if (angle == 135.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_135;
                    } else if (angle == 180.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_180;
                    } else if (angle == 225.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_225;
                    } else if (angle == 270.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_270;
                    } else if (angle == 315.0) {
                        arrowRes = Rez.Drawables.Arrow_48_black_315;
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
            }

            if (arrowRes != null) {
                if (cachedArrowRes != arrowRes || cachedArrowBmp == null) {
                    cachedArrowRes = arrowRes;
                    cachedArrowBmp = WatchUi.loadResource(arrowRes);
                }

                var arrowX = (centerX - (arrowSize / 2) - moveArrowLeft).toNumber();
                var arrowY = ((height * CENTER_Y_RATIO) - (arrowSize / 2) + 2).toNumber();

                dc.drawBitmap(arrowX, arrowY, cachedArrowBmp);
            }
        }

        // -------------------- Bottom row: Temperature, time, rain --------------------------------------------
        var temp = weatherData["temp"] as Lang.Float;
        var rain = weatherData["rain"] as Lang.Float;
        //rain = 1.1;

        var tempStr = temp.format("%.0f") + "°";
        var ageStr  = ageMinutes.format("%d") + "m";

        var bottomY = (height * BOTTOM_Y_RATIO).toNumber();

        var moveFromBottom = useSmallArrow ? 4 : 0;

        dc.drawText(
            padX,
            bottomY - moveFromBottom,
            Graphics.FONT_TINY,
            tempStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        if (rain > 0.0) {
            
            var rainFont = Graphics.FONT_TINY;
            if (useSmallFont) {
                rainFont = Graphics.FONT_XTINY;
            }

            var rainStr = rain.format("%.1f") + "mm";
            var textW = dc.getTextWidthInPixels(rainStr, rainFont);
            var textH = dc.getFontHeight(rainFont);

            var boxPadX = 4;
            var boxPadY = 2;
            var boxW = textW + (boxPadX * 2);
            var boxH = textH + (boxPadY * 2);
            var boxX = width - padX - boxW;
            var boxY = (bottomY - (boxH / 2)).toNumber();
            

            dc.setColor(textColor, bgColor);
            dc.fillRoundedRectangle(boxX, boxY - moveFromBottom, boxW, boxH, 4);

            dc.setColor(bgColor, textColor);
            dc.drawText(
                width - padX - boxPadX,
                bottomY - moveFromBottom,
                rainFont,
                rainStr,
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
            );

            dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);

            var ageFont = Graphics.FONT_XTINY;
            var ageW = dc.getTextWidthInPixels(ageStr, ageFont);

            //var ageLeft = centerX - (ageW / 2);
            var ageRight = centerX + (ageW / 2);

            var minGap = 6;
            var allowedRight = boxX - minGap;

            if (ageRight <= allowedRight) {
                dc.drawText(
                    centerX,
                    bottomY,
                    ageFont,
                    ageStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            } else {
                var shiftedCenterX = allowedRight - (ageW / 2);
                var minCenterX = padX + 20;

                if (shiftedCenterX > minCenterX) {
                    dc.drawText(
                        shiftedCenterX,
                        bottomY,
                        ageFont,
                        ageStr,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                    );
                }
                // else: skip ageStr on very small screens when rain badge is present
            }
        }
        else { //no rain
            dc.drawText(
                centerX,
                bottomY,
                Graphics.FONT_XTINY,
                ageStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }

}