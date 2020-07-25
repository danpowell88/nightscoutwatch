/*
 * NightscoutWatch Garmin Connect IQ watchface
 * Copyright (C) 2017-2018 tynbendad@gmail.com
 * #WeAreNotWaiting
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, version 3 of the License.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   A copy of the GNU General Public License is available at
 *   https://www.gnu.org/licenses/gpl-3.0.txt
 */

using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang as Lang;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Time.Gregorian as Calendar;

// keys to the object store data
var OSDATA="osdata-nsw";
var OSCHART="oschart-nsw";

var partialUpdatesAllowed = false;
var viewVersion = "0.2.4";
class bgbgView extends Ui.WatchFace {

    var width,height;
    var dndIcon, disconnIcon, hrIcon, stepIcon;
    var dirSwitch = {};
    var secondsX = 0;
    var secondsY = 0;
    var secondsClearY = 0;
    var secondsWidth = 0;
    var secondsHeight = 0;
    var secondsStr = "";
    var clockFgColorVal = Gfx.COLOR_WHITE;
    var clockBgColorVal = Gfx.COLOR_WHITE;
    var auxColorVal = Gfx.COLOR_WHITE;
    var screenShape;
    var graphHours = 2;
    var graphMaxBG = 440;
    var curFgCol, curBgCol;
    var shadowWidth = 2;
    var hrX=0, hrY=0, hrFont = null, hrStr="";
    var stepX=0, stepY=0, stepFont = null, stepStr="";

    // app settings
    var fetchMode = 0;
    var bgDisplay = 0;
    var fgColor = 0;
    var bgColor = 3;
    var displaySeconds = true;

	// alert thresholds - loaded from settings
	var watchBatThresh = 20;
	var loopTimeThresh = 15;
	var bgTimeThresh = 15;
	var bgLowThresh = 70;
	var bgHighThresh = 240;
	var pumpBatThreshPct = 25;
	var pumpBatThreshV = 1.25;
	var upBatThresh = 25;
	var reservoirThresh = 20;
	var cageThresh = 72;

    // info about whats happening with the background process
    var setupReqd = true;
    var canDoBG = false;
    var bgdata={};
    var saveLoopBasal=null;
    var chartBG = [];
    //var ctr = 0;

    // layout info
    var dateLine, timeLine, miscLine, elapsedLine, directionLine, bgLine;
    var dateFont = Gfx.FONT_SMALL;
    var elapsedFont = Gfx.FONT_XTINY;
    var directionFont = Gfx.FONT_SMALL;

    enum {
        bgDisplayNormal     = 0,
        bgDisplayMGDL       = 1,
        bgDisplayMMOL       = 2,
        bgDisplayRoman      = 3,
        bgDisplayHEX        = 4,
        bgDisplayHex        = 5,
        bgDisplaySCIENTIFIC = 6,
        bgDisplayScientific = 7,
        bgDisplayOctal      = 8,
        bgDisplayZeroPad    = 9,
        bgDisplayVersion    = 10 }

    enum {
        fetchModeNormal     = 0,
        fetchModeNormalMin  = 1,
        fetchModeDevice     = 2,
        fetchModeDeviceMin1 = 3,
        fetchModeDeviceMin2 = 4 }

    enum {
        col_WHITE = 0,
        col_LT_GRAY = 1,
        col_DK_GRAY = 2,
        col_BLACK = 3,
        col_RED = 4,
        col_DK_RED = 5,
        col_ORANGE = 6,
        col_YELLOW = 7,
        col_GREEN = 8,
        col_DK_GREEN = 9,
        col_BLUE = 10,
        col_DK_BLUE = 11,
        col_PURPLE = 12,
        col_PINK = 13,
        col_RANDOM = 14 }

//    function myPrintLn(x) {
//        System.println(x);
//    }

	function myHasKey(obj, k) {
        if ((obj != null) &&
            (obj instanceof Dictionary)) {
            return (obj.hasKey(k));
        }
        return false;
	}

	function removeWhitespace(url) {
		while(!url.equals("") &&
		      url.substring(0,1).equals(" ")) {
		    url = url.substring(1,url.length());
        }
		while(!url.equals("") &&
		      url.substring(url.length()-1,url.length()).equals(" ")) {
		    url = url.substring(0,url.length()-1);
        }
		return url;
	}

	function addChartBG(bgmgdl, mills) {
		// chartBG screams for a dictionary/hash, but we are very tight on memory in background process, and property memory affects it.
		//myPrintLn("addChartBG: before chartBG.size() = " + chartBG.size());
		var mins = (mills / 1000 / 60).toNumber();
		var added = false;
		for(var i = 0; i < chartBG.size(); i+=2 ) {
        	if (chartBG[i] == mins) {
        		//myPrintLn("addChartBG: replacing, mins=" + mins);
        		chartBG[i+1] = bgmgdl;
        		added = true;
        		break;
        	} else if (chartBG[i] > mins) {
        		//myPrintLn("addChartBG: inserting, mins=" + mins + ", i=" + i);
        		var firstSl = chartBG.slice(0, i);
        		var secondSl = [mins, bgmgdl];
        		var thirdSl = chartBG.slice(i, null);
        		chartBG = firstSl;
        		chartBG.addAll(secondSl);
        		chartBG.addAll(thirdSl);
        		added = true;
        		break;
        	}
    	}
    	if (!added) {
    		//myPrintLn("addChartBG: add to end, mins=" + mins);
    		chartBG.add(mins);
    		chartBG.add(bgmgdl);
    	}

        if ((chartBG.size() / 2) > (graphHours * 60 / 5)) {
			//myPrintLn("addChartBG: removing");
        	chartBG.remove(chartBG[0]);
        	chartBG.remove(chartBG[0]);
	    }
		//myPrintLn("addChartBG: after chartBG.size() = " + chartBG.size());
	}

	function updateChartBG() {
	    if (myHasKey(bgdata, "bgmgdl") &&
	    	myHasKey(bgdata, "elapsedMills")) {
	    	addChartBG(bgdata["bgmgdl"], bgdata["elapsedMills"]);
    	}
	}

    function setBgData(data) {
        //System.println("setBgData="+data);
        System.println("setBgData");
        if (myHasKey(data, "blefail")) {
        	bgdata["blefail"] = true;
        } else {
        	bgdata.remove("blefail");
        }
        if (myHasKey(data, "httpfail")) {
            // properties/SGV requests failed - don't update the saved data
        } else if (myHasKey(data, "httpfaildevice")) {
            // devicestatus request failed, only copy the new properties data over
            if (myHasKey(data, "prop")) {
	            setupReqd = false;
	            translateProperties(data["prop"]);
            }
            if (myHasKey(data, "sgv")) {
	            setupReqd = false;
	            translateSGV(data["sgv"]);
            }
	        App.getApp().setProperty(OSDATA,bgdata);
        } else if (data != null) {
            bgdata = {};
            if (myHasKey(data, "prop")) {
	            setupReqd = false;
	            translateProperties(data["prop"]);
            }
            if (myHasKey(data, "dev1")) {
	            translateDevice(data["dev1"]);
            }
            if (myHasKey(data, "dev2")) {
	            translateDevice(data["dev2"]);
            }
            if (myHasKey(data, "sgv")) {
	            setupReqd = false;
	            translateSGV(data["sgv"]);
            }
	        App.getApp().setProperty(OSDATA,bgdata);
        }
        updateChartBG();
        App.getApp().setProperty(OSCHART,chartBG);
    }

	// translate from nightscout properties to generic bgdata used in display func.
    function translateProperties(data) {
        //Sys.println("in translateProperties");
        if ((data != null) &&
            (data instanceof Dictionary)) {
            if (myHasKey(data, "buckets") &&
            	(data["buckets"] != null) &&
            	(data["buckets"] instanceof Array) &&
            	(data["buckets"][0] != null) &&
            	(data["buckets"][0] instanceof Dictionary)) {
                if (myHasKey(data["buckets"][0], "last")) {
                    bgdata["bgmgdl"] = data["buckets"][0]["last"];
                }
                if (myHasKey(data["buckets"][0], "mills")) {
                    bgdata["elapsedMills"] = data["buckets"][0]["mills"] * 1000;
                }
                if (myHasKey(data["buckets"][0], "sgvs") &&
                    (data["buckets"][0]["sgvs"].size() > 0) &&
                    (data["buckets"][0]["sgvs"][0] != null) &&
                    myHasKey(data["buckets"][0]["sgvs"][0], "scaled")) {
                    bgdata["bg"] = data["buckets"][0]["sgvs"][0]["scaled"];
                } else if (myHasKey(data["buckets"][0], "sgvs") &&
                           (data["buckets"][0]["sgvs"].size() > 1) &&
                           (data["buckets"][0]["sgvs"][1] != null) &&
                           myHasKey(data["buckets"][0]["sgvs"][1], "scaled")) {
                    bgdata["bg"] = data["buckets"][0]["sgvs"][1]["scaled"];
                }

                if (myHasKey(data["buckets"][0], "sgvs") &&
                    (data["buckets"][0]["sgvs"].size() > 0) &&
                    (data["buckets"][0]["sgvs"][0] != null) &&
                    myHasKey(data["buckets"][0]["sgvs"][0], "direction")) {
                    bgdata["direction"] = data["buckets"][0]["sgvs"][0]["direction"];
                }

            	for (var i=1; i < data["buckets"].size(); i++) {
	                if ((data["buckets"][i] != null) &&
	            		(data["buckets"][i] instanceof Dictionary) &&
			            myHasKey(data["buckets"][i], "last") &&
			            myHasKey(data["buckets"][i], "mills")) {
	                    addChartBG(data["buckets"][i]["last"], data["buckets"][i]["mills"] * 1000);
	                }
                }

                data.remove("buckets");
            }
            if (myHasKey(data, "delta") &&
                myHasKey(data["delta"], "display")) {
                bgdata["delta"] = data["delta"]["display"];
                data.remove("delta");
            }

            if (myHasKey(data, "rawbg") &&
                myHasKey(data["rawbg"], "mgdl") &&
                (data["rawbg"]["mgdl"] > 0) &&
                myHasKey(data["rawbg"], "noiseLabel")) {
                bgdata["rawbg"] = data["rawbg"]["mgdl"].toString() + " " + data["rawbg"]["noiseLabel"];
                data.remove("rawbg");
            }

            if (myHasKey(data, "cage") &&
                myHasKey(data["cage"], "found") &&
                (data["cage"]["found"] == true) &&
                myHasKey(data["cage"], "age")) {
                bgdata["cage"] = data["cage"]["age"];
                data.remove("cage");
            }

            if (myHasKey(data, "basal") &&
                myHasKey(data["basal"], "display")) {
                var basal = data["basal"]["display"];
                //myPrintLn(basal);
                if (basal.find(":") != null) {
                    basal = basal.substring(basal.find(":")+1, basal.length());
                }
                if (basal.find(" ") != null) {
                    basal = basal.substring(basal.find(" ")+1, basal.length());
                }
                if (basal.find("0U") != null) {
                    basal = basal.substring(0, basal.find("0U"));
                }
                if (basal.find("U") != null) {
                    basal = basal.substring(0, basal.find("U"));
                }
                //myPrintLn("after:"+basal);
                bgdata["propbasal"] = basal;
                data.remove("basal");
            }
        }
        //Sys.println("out translateProperties");
    }

	// translate from nightscout devicestatus (diff. for loop, openaps) to generic bgdata used in display func
    function translateDevice(data) {
        //Sys.println("in translateDevice");
        if ((data != null) &&
            (data.size() > 0) &&
            (data[0] instanceof Dictionary)) {
            if (myHasKey(data[0], "loop")) {
            	if (myHasKey(data[0]["loop"], "failureReason")) {
	                bgdata["httpfaildevice"] = true;
            	}
                if (myHasKey(data[0]["loop"], "predicted") &&
                    myHasKey(data[0]["loop"]["predicted"], "startDate")) {
                    bgdata["loopTime"] = data[0]["loop"]["predicted"]["startDate"];

                    if (myHasKey(data[0]["loop"]["predicted"], "values") &&
                        (data[0]["loop"]["predicted"]["values"].size() > 0) &&
                        (data[0]["loop"]["predicted"]["values"][0] != null)) {
                        bgdata["eventual"] = data[0]["loop"]["predicted"]["values"][data[0]["loop"]["predicted"]["values"].size()-1];
                    }
                    data[0]["loop"].remove("predicted");
                }
                if (myHasKey(data[0]["loop"], "cob") &&
                    myHasKey(data[0]["loop"]["cob"], "cob")) {
                    bgdata["cob"] = data[0]["loop"]["cob"]["cob"];
                    data[0]["loop"].remove("cob");
                }
                if (myHasKey(data[0]["loop"], "iob") &&
                    myHasKey(data[0]["loop"]["iob"], "iob")) {
                    bgdata["iob"] = data[0]["loop"]["iob"]["iob"];
                    data[0]["loop"].remove("iob");
                }
                if (myHasKey(data[0]["loop"], "enacted") &&
                    myHasKey(data[0]["loop"]["enacted"], "rate") &&
                    myHasKey(data[0]["loop"]["enacted"], "duration")) {
                    if (data[0]["loop"]["enacted"]["duration"] != 0) {
	                    bgdata["basal"] = data[0]["loop"]["enacted"]["rate"];
	                    // not using this - just show when loop gives it to us, we miss some so can't make it sticky
	                    // saveLoopBasal = bgdata["basal"];
                    } else {
	                    saveLoopBasal = null;
                    }
                    data[0]["loop"].remove("enacted");
                } else {
                	if (saveLoopBasal != null) {
	                	bgdata["basal"] = saveLoopBasal;
                	}
                }
                data[0].remove("loop");
            }


            if (myHasKey(data[0], "pump")) {
                if (myHasKey(data[0]["pump"], "battery") &&
                    myHasKey(data[0]["pump"]["battery"], "voltage")) {
                    bgdata["pumpbat"] = data[0]["pump"]["battery"]["voltage"];
                } else if (myHasKey(data[0]["pump"], "battery") &&
                           myHasKey(data[0]["pump"]["battery"], "percent")) {
                    bgdata["pumpbat"] = data[0]["pump"]["battery"]["percent"];
                }

                if (myHasKey(data[0]["pump"], "reservoir")) {
                    bgdata["reservoir"] = data[0]["pump"]["reservoir"];
                }
                if (myHasKey(data[0]["pump"], "status") &&
                    myHasKey(data[0]["pump"]["status"], "suspended")) {
                    bgdata["suspended"] = data[0]["pump"]["status"]["suspended"];
                }
                if (myHasKey(data[0]["pump"], "iob") &&
                    myHasKey(data[0]["pump"]["iob"], "bolusiob")) {
                    bgdata["iob"] = data[0]["pump"]["iob"]["bolusiob"];	// medtronic 600 uploader iob
                    data[0]["pump"].remove("iob");
                }
                // remove "pump" in openaps case, below
            }

            if (myHasKey(data[0], "uploader") &&
                myHasKey(data[0]["uploader"], "battery")) {
                bgdata["upbat"] = data[0]["uploader"]["battery"];
                data[0].remove("uploader");
            } else if (myHasKey(data[0], "uploaderBattery")) {
                bgdata["upbat"] = data[0]["uploaderBattery"];
                data[0].remove("uploaderBattery");
            }

            if (myHasKey(data[0], "openaps")) {
                if (myHasKey(data[0]["openaps"], "suggested") &&
                    myHasKey(data[0]["openaps"]["suggested"], "timestamp")) {
                    bgdata["loopTime"] = data[0]["openaps"]["suggested"]["timestamp"];

                    if (myHasKey(data[0]["openaps"]["suggested"], "eventualBG")) {
                        bgdata["eventual"] = data[0]["openaps"]["suggested"]["eventualBG"];
                    }
                    if (myHasKey(data[0]["openaps"]["suggested"], "COB")) {
                        bgdata["cob"] = data[0]["openaps"]["suggested"]["COB"];
                    }
                    data[0]["openaps"].remove("suggested");
                }
                if (myHasKey(data[0]["openaps"], "iob") &&
                    myHasKey(data[0]["openaps"]["iob"], "iob")) {
                    bgdata["iob"] = data[0]["openaps"]["iob"]["iob"];
                    data[0]["openaps"].remove("iob");
                }
                if (myHasKey(data[0]["openaps"], "enacted") &&
                    myHasKey(data[0]["openaps"]["enacted"], "rate") &&
                    myHasKey(data[0]["openaps"]["enacted"], "duration")) {
                    bgdata["basal"] = data[0]["openaps"]["enacted"]["rate"];
                    data[0]["openaps"].remove("enacted");
                }
                data[0].remove("openaps");
                data[0].remove("pump");
            }
        }
        //Sys.println("out translateDevice");
    }

	// translate from sgv.json to generic bgdata used in display func
    function translateSGV(data) {
        //Sys.println("in translateSGV");
        if ((data != null) &&
            (data.size() > 1) &&
            (data[0] != null) &&
            (data[1] != null) &&
            !data[0].isEmpty() &&
            !data[1].isEmpty()
            ) {
            var elapsedMills, bg, direction, delta, isMgdl, bgMgdl;
            elapsedMills = 0;
            bg = 0;
            bgMgdl = 0;
            direction = "";
            delta = "";
            isMgdl = true;
            if (myHasKey(data[0], "units_hint")) {
            	if (!data[0]["units_hint"].equals("mgdl")) {
            		isMgdl = false;
            	}
            }

            if (myHasKey(data[0], "sgv") &&
                myHasKey(data[0], "date") &&
                myHasKey(data[0], "direction")
                ) {
                elapsedMills = data[0]["date"];
                bg = data[0]["sgv"];
                bgMgdl = bg;
                if ((bg instanceof Number) &&
                	!isMgdl) {
	                bg = bg / 18.0;
		            bg = bg.format("%.1f");
                }
                direction = data[0]["direction"].toString();
                delta = "N/A";
                if (myHasKey(data[1], "sgv") &&
                    myHasKey(data[1], "date") &&
                    myHasKey(data[2], "sgv") &&
                    myHasKey(data[2], "date")) {
                    var deltaTime;
                    if (data[0]["date"] == data[1]["date"]) {
                        //myPrintLn("using data[2] for date");
                        delta = data[0]["sgv"] - data[2]["sgv"];
                        deltaTime = (data[0]["date"] - data[2]["date"]) / 1000 / 300.0;
                    } else {
                        delta = data[0]["sgv"] - data[1]["sgv"];
                        deltaTime = (data[0]["date"] - data[1]["date"]) / 1000 / 300.0;
                    }
                    //myPrintLn("delta=" + delta + ", deltaTIme=" + deltaTime);
                    if (deltaTime > 1.5) {
                        // convert >7.5 minute delta to to 5-minute delta
                        delta = (delta / deltaTime);
		                delta = delta.toNumber();
                    }
	                if (!isMgdl) {
		                delta = delta / 18.0;
		                delta = delta.format("%.1f");
	                }
                    if (deltaTime >= 0.25) {
                        if (delta.toFloat() >= 0) {
                            delta = "+" + delta;
                        }
                    } else {
                        delta = "N/A";
                    }
                    addChartBG(data[1]["sgv"], data[1]["date"]);
                    addChartBG(data[2]["sgv"], data[2]["date"]);
                }
            }
            //bgdata["str"]=bg.toString() + " " + direction + " " + delta;
            bgdata["elapsedMills"] = elapsedMills;
            bgdata["bg"] = bg;
            bgdata["bgmgdl"] = bgMgdl;
            bgdata["direction"] = direction;
            bgdata["delta"] = delta;
        }
        //Sys.println("out translateSGV");
    }

    function requestUpdate() {
        Ui.requestUpdate();
    }

    function readSettings() {
        //myPrintLn("view readSettings()");
        var thisApp = Application.getApp();
        var nsurl = thisApp.getProperty("nsurl");
        if (nsurl == null) { nsurl = ""; }
        var offlineUrl = thisApp.getProperty("offlineUrl");
        if (offlineUrl == null) { offlineUrl = ""; }

        fetchMode = thisApp.getProperty("fetchMode");
        if (fetchMode == null) { fetchMode = 3; }
        bgDisplay = thisApp.getProperty("bgDisplay");
        if (bgDisplay == null) { bgDisplay = 0; }
        fgColor = thisApp.getProperty("fgColor");
        if (fgColor == null) { fgColor = 0; }
        bgColor = thisApp.getProperty("bgColor");
        if (bgColor == null) { bgColor = 3; }

		watchBatThresh = thisApp.getProperty("watchBatThresh");
        if (watchBatThresh == null) { watchBatThresh = 20; }
        watchBatThresh = watchBatThresh.toNumber();
/*
		loopTimeThresh = thisApp.getProperty("loopTimeThresh").toNumber();
        if (loopTimeThresh == null) { loopTimeThresh = 15; }
		bgTimeThresh = thisApp.getProperty("bgTimeThresh").toNumber();
        if (bgTimeThresh == null) { bgTimeThresh = 15; }
*/
		bgLowThresh = thisApp.getProperty("bgLowThresh");
        if (bgLowThresh == null) { bgLowThresh = 70; }
        bgLowThresh = bgLowThresh.toNumber();
		bgHighThresh = thisApp.getProperty("bgHighThresh");
        if (bgHighThresh == null) { bgHighThresh = 240; }
        bgHighThresh = bgHighThresh.toNumber();
		pumpBatThreshPct = thisApp.getProperty("pumpBatThreshPct");
        if (pumpBatThreshPct == null) { pumpBatThreshPct = 25; }
        pumpBatThreshPct = pumpBatThreshPct.toNumber();
		pumpBatThreshV = thisApp.getProperty("pumpBatThreshV");
        if (pumpBatThreshV == null) { pumpBatThreshV = 1.25; }
        pumpBatThreshV = pumpBatThreshV.toFloat();
		upBatThresh = thisApp.getProperty("upBatThresh");
        if (upBatThresh == null) { upBatThresh = 25; }
        upBatThresh = upBatThresh.toNumber();
		reservoirThresh = thisApp.getProperty("reservoirThresh");
        if (reservoirThresh == null) { reservoirThresh = 20; }
        reservoirThresh = reservoirThresh.toNumber();
		cageThresh = thisApp.getProperty("cageThresh");
        if (cageThresh == null) { cageThresh = 72; }
		cageThresh = cageThresh.toNumber();

        if (((nsurl != null) &&
             !removeWhitespace(nsurl).equals("")) ||
            ((offlineUrl != null) &&
             !removeWhitespace(offlineUrl).equals(""))) {
            setupReqd = false;
        } else {
			// empty url's may still use xdrip or spike now...
            // setupReqd = true;
        }

        displaySeconds = thisApp.getProperty("displaySeconds");
        if (displaySeconds == null) { displaySeconds = true; }

        Ui.requestUpdate();
    }

//    function getStatus() {
//        return !setupReqd;
//    }

    function onSettingsChanged() {
    	//myPrintLn("view.onSettingsChanged(), ctr=" + ctr); ctr++;
        readSettings();

        chartBG = [];
        App.getApp().setProperty(OSCHART,chartBG);

		return true; // always register the event now, since we attempt xdrip or spike regardless of empty urls
//        return !setupReqd;
    }

    function initialize() {
    	//myPrintLn("view.initialize(), ctr=" + ctr); ctr++;

        screenShape = Sys.getDeviceSettings().screenShape;

        WatchFace.initialize();

        //read last values from the Object Store
        var temp=App.getApp().getProperty(OSDATA);
        if(temp!=null) {bgdata=temp; setupReqd=false;}
        App.getApp().deleteProperty("osdata");	// delete old property - can remove this at some point

        temp=App.getApp().getProperty(OSCHART);
        if((temp!=null)&&(temp instanceof Toybox.Lang.Array)) {chartBG=temp;}

        readSettings();

        if(Toybox.System has :ServiceDelegate) {
            canDoBG = true;
        }

        var now=Sys.getClockTime();
        var ts=now.hour+":"+now.min.format("%02d");
        //Sys.println("From OS: data="+bgdata+" at "+ts);
    }

    // Load your resources here
    function onLayout(dc) {
    	//myPrintLn("view.onLayout(), ctr=" + ctr); ctr++;

        width=dc.getWidth();
        height=dc.getHeight();
        var mySettings = Sys.getDeviceSettings();

        //Sys.println("screenShape="+screenShape+", width:"+width+", height:"+height+", partNumber:"+mySettings.partNumber+
        //            ", fontHeights="+Gfx.getFontHeight(Gfx.FONT_XTINY)+"/"+Gfx.getFontHeight(Gfx.FONT_SMALL)+"/"+Gfx.getFontHeight(Gfx.FONT_MEDIUM)+"/"+Gfx.getFontHeight(Gfx.FONT_LARGE)+"/"+Gfx.getFontHeight(Gfx.FONT_NUMBER_HOT));

        dndIcon = Ui.loadResource(Rez.Drawables.DoNotDisturbIcon);
        if (Sys.getDeviceSettings() has :phoneConnected) {
            disconnIcon = Ui.loadResource(Rez.Drawables.DisconnectedIcon);
        } else {
            disconnIcon = null;
        }
        dirSwitch = { "SingleUp" => Ui.loadResource(Rez.Drawables.SingleUp),
                          "DoubleUp" => Ui.loadResource(Rez.Drawables.DoubleUp),
                          "FortyFiveUp" => Ui.loadResource(Rez.Drawables.FortyFiveUp),
                          "FortyFiveDown" => Ui.loadResource(Rez.Drawables.FortyFiveDown),
                          "SingleDown" => Ui.loadResource(Rez.Drawables.SingleDown),
                          "DoubleDown" => Ui.loadResource(Rez.Drawables.DoubleDown),
                          "Flat" => Ui.loadResource(Rez.Drawables.Flat),
                          "NONE" => Ui.loadResource(Rez.Drawables.NONE) };

		var hasHR = ((Toybox has :ActivityMonitor) && (ActivityMonitor has :HeartRateIterator)) ? true : false;
		if (hasHR) {
	        hrIcon = Ui.loadResource(Rez.Drawables.heartrate);
        } else {
        	hrIcon = null;
        }
		if (Toybox has :ActivityMonitor) {
	        stepIcon = Ui.loadResource(Rez.Drawables.steps);
        } else {
        	stepIcon = null;
        }

        if ((width == 148) && (height == 205)) {
            // vivoactiveHR
            dateLine = 3;
            timeLine = 20;
            miscLine = 85;
            elapsedLine = 110;
            directionLine = 135;
            bgLine = 154;

            dateFont = Gfx.FONT_MEDIUM;
            elapsedFont = Gfx.FONT_MEDIUM;
            directionFont = Gfx.FONT_MEDIUM;
        } else if ((width == 215) && (height == 180)) {
            // fr735xt
            dateLine = 1;
            timeLine = 20;
            miscLine = 75;
            elapsedLine = 90;
            directionLine = 109;
            bgLine = 124;
            dateFont = Gfx.FONT_MEDIUM;
            elapsedFont = Gfx.FONT_MEDIUM;
            directionFont = Gfx.FONT_MEDIUM;
        } else if ((width == 240) && (height == 240)) {
        	if (Gfx.getFontHeight(Gfx.FONT_NUMBER_HOT) < 55) {
	            // (240,240) d2 charlie, fenix 5/5x/5s plus, 645, fr935
	            dateLine = 10;
	            timeLine = 41;
	            miscLine = 94;
	            elapsedLine = 116;
	            directionLine = 138;
	            bgLine = 167;
	            elapsedFont = Gfx.FONT_SMALL;
        	} else if (Gfx.getFontHeight(Gfx.FONT_NUMBER_HOT) < 80) {
	            // (240,240) approach s60, vivoactive3
	            dateLine = 15;
	            timeLine = 33;
	            miscLine = 101;
	            elapsedLine = 121;
	            directionLine = 146;
	            bgLine = 162;
	            elapsedFont = Gfx.FONT_SMALL;
            } else {
	            // (240,240) fenix 6s, MARQ*
	            dateLine = 10;
	            timeLine = 28;
	            miscLine = 101;
	            elapsedLine = 121;
	            directionLine = 145;
	            bgLine = 155;
	            elapsedFont = Gfx.FONT_SMALL;
            }
        } else if ((width == 218) && (height == 218)) {
        	if (Gfx.getFontHeight(Gfx.FONT_NUMBER_HOT) < 55) {
	            // (218,218) fenix 5s/chronos
	            dateLine = 10;
	            timeLine = 38;
	            miscLine = 89;
	            elapsedLine = 113;
	            directionLine = 134;
	            bgLine = 162;
            } else {
	            // (218,218) marvel/va4s
	            dateLine = 10;
	            timeLine = 28;
	            miscLine = 95;
	            elapsedLine = 118;
	            directionLine = 134;
	            bgLine = 150;
            }
        } else if ((width == 260) && (height == 260)) {
            // fenix 6/avenger/va4
            dateLine = 10;
            timeLine = 29;
            miscLine = 109;
            elapsedLine = 133;
            directionLine = 151;
            bgLine = 165;
        } else if ((width == 280) && (height == 280)) {
            // fenix 6x pro*
            dateLine = 10;
            timeLine = 29;
            miscLine = 119;
            elapsedLine = 143;
            directionLine = 161;
            bgLine = 175;
        } else if ((width == 390) && (height == 390)) {
            // venu
            dateLine = 10;
            timeLine = 48;
            miscLine = 162;
            elapsedLine = 195;
            directionLine = 225;
            bgLine = 262;
        } else {
            // unknown
			//myPrintLn("UNKNOWN device!!!");
            dateLine = 10;
            timeLine = 38;
            miscLine = 89;
            elapsedLine = 113;
            directionLine = 134;
            bgLine = 162;
        }

        partialUpdatesAllowed = ( Toybox.WatchUi.WatchFace has :onPartialUpdate );
     }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
    	//myPrintLn("view.onShow(), ctr=" + ctr); ctr++;
    }

    function romanize(num) {
        if (!(num > 0)) {
            return "LOW";
        }
        var digits = num.toString().toCharArray();
        var romanKey = ["","C","CC","CCC","CD","D","DC","DCC","DCCC","CM",
	                    "","X","XX","XXX","XL","L","LX","LXX","LXXX","XC",
	                    "","I","II","III","IV","V","VI","VII","VIII","IX"];
        var roman = "",
            i = 0;
        if (digits.size() > 3) {
            return "HIGH";
        }
        while (i < digits.size()) {
            //myPrintLn("romanize: digit: " + digits[i]);
            //myPrintLn("romanize: digit number: " + digits[i].toString().toNumber());
            //myPrintLn("romanize: digit index: " + (digits[i].toString().toNumber() + (i*10)));
            roman = roman + romanKey[(digits[i].toString().toNumber() + ((3 - digits.size() + i) * 10) )];
            //myPrintLn("romanize: roman: " + roman);
            i++;
            //myPrintLn("romanize: i: " + i + " size: " + digits.size());
        }
        return roman;
    }

    function pickColor(inColor, now) {
        var outColor = Gfx.COLOR_WHITE;
        if (inColor == col_RANDOM) {
        	Math.srand(now);
        	inColor = Math.rand() % col_RANDOM;
        }
        if (inColor == col_WHITE) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == col_LT_GRAY) {
            outColor = Gfx.COLOR_LT_GRAY;
        } else if (inColor == col_DK_GRAY) {
            outColor = Gfx.COLOR_DK_GRAY;
        } else if (inColor == col_BLACK) {
            outColor = Gfx.COLOR_BLACK;
        } else if (inColor == col_RED) {
            outColor = Gfx.COLOR_RED;
        } else if (inColor == col_DK_RED) {
            outColor = Gfx.COLOR_DK_RED;
        } else if (inColor == col_ORANGE) {
            outColor = Gfx.COLOR_ORANGE;
        } else if (inColor == col_YELLOW) {
            outColor = Gfx.COLOR_YELLOW;
        } else if (inColor == col_GREEN) {
            outColor = Gfx.COLOR_GREEN;
        } else if (inColor == col_DK_GREEN) {
            outColor = Gfx.COLOR_DK_GREEN;
        } else if (inColor == col_BLUE) {
            outColor = Gfx.COLOR_BLUE;
        } else if (inColor == col_DK_BLUE) {
            outColor = Gfx.COLOR_DK_BLUE;
        } else if (inColor == col_PURPLE) {
            outColor = Gfx.COLOR_PURPLE;
        } else if (inColor == col_PINK) {
            outColor = Gfx.COLOR_PINK;
        }

        return outColor;
    }

    function shadowColor(inColor) {
        var outColor = Gfx.COLOR_BLACK;
    	var shadowMap = { Gfx.COLOR_WHITE => Gfx.COLOR_BLACK,
    						Gfx.COLOR_LT_GRAY => Gfx.COLOR_BLACK,
							Gfx.COLOR_DK_GRAY => Gfx.COLOR_WHITE,
							Gfx.COLOR_BLACK => Gfx.COLOR_WHITE,
							Gfx.COLOR_RED => Gfx.COLOR_WHITE,
							Gfx.COLOR_DK_RED => Gfx.COLOR_WHITE,
							Gfx.COLOR_ORANGE => Gfx.COLOR_BLACK,
							Gfx.COLOR_YELLOW => Gfx.COLOR_BLACK,
							Gfx.COLOR_GREEN => Gfx.COLOR_BLACK,
							Gfx.COLOR_DK_GREEN => Gfx.COLOR_WHITE,
							Gfx.COLOR_BLUE => Gfx.COLOR_BLACK,
							Gfx.COLOR_DK_BLUE => Gfx.COLOR_WHITE,
							Gfx.COLOR_PURPLE => Gfx.COLOR_WHITE,
							Gfx.COLOR_PINK => Gfx.COLOR_BLACK };
		outColor = shadowMap[inColor];
/*
        if (inColor == Gfx.COLOR_WHITE) {
            outColor = Gfx.COLOR_BLACK;
        } else if (inColor == Gfx.COLOR_LT_GRAY) {
            outColor = Gfx.COLOR_BLACK;
        } else if (inColor == Gfx.COLOR_DK_GRAY) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == Gfx.COLOR_BLACK) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == Gfx.COLOR_RED) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == Gfx.COLOR_DK_RED) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == Gfx.COLOR_ORANGE) {
            outColor = Gfx.COLOR_BLACK;
        } else if (inColor == Gfx.COLOR_YELLOW) {
            outColor = Gfx.COLOR_BLACK;
        } else if (inColor == Gfx.COLOR_GREEN) {
            outColor = Gfx.COLOR_BLACK;
        } else if (inColor == Gfx.COLOR_DK_GREEN) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == Gfx.COLOR_BLUE) {
            outColor = Gfx.COLOR_BLACK;
        } else if (inColor == Gfx.COLOR_DK_BLUE) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == Gfx.COLOR_PURPLE) {
            outColor = Gfx.COLOR_WHITE;
        } else if (inColor == Gfx.COLOR_PINK) {
            outColor = Gfx.COLOR_BLACK;
        }
*/

        return outColor;
    }

    function drawClock(dc, clockMode, info) {
        var timeString = "";
        if (clockMode) {
            timeString = Lang.format("$1$:$2$", [info.hour, info.min.format("%02d")]);
        } else {
            var hour = info.hour % 12;
            if (hour == 0) {
                hour = 12;
            }
            //var ampm = "PM";
            //if (info.hour < 12) {
            //  ampm = "AM";
            //}
            //timeString = Lang.format("$1$:$2$ $3$", [hour, info.min.format("%02d"), ampm]);
            timeString = Lang.format("$1$:$2$", [hour, info.min.format("%02d")]);
        }

        var timeX;
        if (partialUpdatesAllowed && displaySeconds) {
            secondsStr = info.sec.format("%02d");
            timeX = width/2 - dc.getTextWidthInPixels("00", Gfx.FONT_LARGE)/2;
            timeString = timeString;
        } else {
            secondsStr = "";
            timeX = width/2;
        }

        secondsX = width/2 +
                    dc.getTextWidthInPixels(timeString, Gfx.FONT_NUMBER_HOT)/2 -
                    dc.getTextWidthInPixels("0", Gfx.FONT_LARGE)/2;
//bottom:        secondsY = timeLine + Gfx.getFontHeight(Gfx.FONT_NUMBER_HOT) - Gfx.getFontDescent(Gfx.FONT_NUMBER_HOT) - Gfx.getFontHeight(Gfx.FONT_LARGE) + Gfx.getFontDescent(Gfx.FONT_LARGE);
        secondsY = timeLine + Gfx.getFontHeight(Gfx.FONT_NUMBER_HOT) / 2 - Gfx.getFontHeight(Gfx.FONT_LARGE) / 2;
        secondsClearY = timeLine + Gfx.getFontDescent(Gfx.FONT_NUMBER_HOT);
        secondsWidth = dc.getTextWidthInPixels("00", Gfx.FONT_NUMBER_HOT);
        secondsHeight = 2 + Gfx.getFontHeight(Gfx.FONT_NUMBER_HOT) - 2*Gfx.getFontDescent(Gfx.FONT_NUMBER_HOT);

        // we could draw the (reversed)date after the clock, but that wouldn't work for seconds, so clear here:
        mySetColor(dc, clockBgColorVal,clockBgColorVal);
        dc.fillRectangle(0, secondsClearY, width, secondsHeight);

        mySetColor(dc, clockFgColorVal,Gfx.COLOR_TRANSPARENT);
        shadowText(dc, timeX,timeLine,Gfx.FONT_NUMBER_HOT,timeString,Gfx.TEXT_JUSTIFY_CENTER);
        shadowText(dc, secondsX+shadowWidth,secondsY,Gfx.FONT_LARGE,secondsStr,Gfx.TEXT_JUSTIFY_LEFT);
    }

	function drawHR(dc) {
		if (hrFont != null) {
			clipText(dc, hrY, hrFont);
		}
        if (!hrStr.equals("") && (hrFont != null)) {
	        shadowText(dc, hrX, hrY, hrFont, hrStr, Gfx.TEXT_JUSTIFY_RIGHT);
        }
	}

	function drawSteps(dc) {
		if (stepFont != null) {
			clipText(dc, stepY, stepFont);
		}
        if (!stepStr.equals("") && (stepFont != null)) {
	        shadowText(dc, stepX, stepY, stepFont, stepStr, Gfx.TEXT_JUSTIFY_LEFT);
        }
	}

    function onPartialUpdate( dc ) {
        if (!displaySeconds) {
            return;
        }

        var info = Sys.getClockTime();

        dc.setClip(secondsX, secondsClearY, secondsWidth, secondsHeight);
        //// first, clear the old string with background color:
        //mySetColor(dc, clockBgColorVal,clockBgColorVal);
        //dc.clear();
        // draw/save new seconds:
        mySetColor(dc, clockFgColorVal, clockBgColorVal);
        secondsStr = info.sec.format("%02d");
        shadowText(dc, secondsX+shadowWidth,secondsY,Gfx.FONT_LARGE,secondsStr,Gfx.TEXT_JUSTIFY_LEFT);

		var partialMode = info.sec % 4;
		if ((partialMode == 0) && (hrFont != null)) {
			var newHRStr = getHR();
			if (!newHRStr.equals(hrStr)) {
				hrStr = newHRStr;
		        mySetColor(dc, auxColorVal, clockBgColorVal);
		        drawHR(dc);
	        }
		} else if ((partialMode == 2) && (stepFont != null)) {
			var newStepStr = getSteps();
			if (!newStepStr.equals(stepStr)) {
				stepStr = newStepStr;
		        mySetColor(dc, auxColorVal, clockBgColorVal);
		        drawSteps(dc);
	        }
		}
    }

	function clipText(dc, y, font) {
        var clipY = y + Gfx.getFontDescent(font) - shadowWidth - 2;
        var clipHeight = 4 + shadowWidth * 2 + Gfx.getFontHeight(font) - 2*Gfx.getFontDescent(font);
        dc.setClip(0, clipY, width, clipHeight);
	}

	function drawChart(dc, now) {
        if ((chartBG.size() == 0) ||
        	(secondsHeight == 0)) {
        	return;
    	}

        // Draw BG graph in the background
        var graphW = width;
        var graphOffsetX = 0;
        var graphOffsetY = secondsClearY + secondsHeight;
        var graphH = height - graphOffsetY;

        var graphCircleSize = (graphW / (1.5 * graphHours * 60 / 5)).toNumber();
        if ((Sys.SCREEN_SHAPE_ROUND == screenShape) ||
        	(Sys.SCREEN_SHAPE_SEMI_ROUND == screenShape)) {
        	graphW = (width / 1.9).toNumber();
        	graphOffsetX = ((width - graphW) / 2).toNumber();
        	graphCircleSize = (graphW / (1.5 * graphHours * 60 / 5)).toNumber();
        } else {
        	graphW = width - (graphCircleSize * 2);
		    graphOffsetX = graphCircleSize;
        }
        var startSec = now - (graphHours * 60 * 60);
        var markerWidth = 3 * graphCircleSize;
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_BLUE);
        dc.drawLine(graphOffsetX, graphOffsetY + graphH * (1.0 - (1.0 * bgHighThresh / graphMaxBG)), graphOffsetX+markerWidth, graphOffsetY + graphH * (1.0 - (1.0 * bgHighThresh / graphMaxBG)));
        dc.drawLine(graphOffsetX, graphOffsetY + graphH * (1.0 - (1.0 * bgLowThresh / graphMaxBG)), graphOffsetX+markerWidth, graphOffsetY + graphH * (1.0 - (1.0 * bgLowThresh / graphMaxBG)));
        dc.drawLine(graphOffsetX+graphW-markerWidth, graphOffsetY + graphH * (1.0 - (1.0 * bgHighThresh / graphMaxBG)), graphOffsetX+graphW, graphOffsetY + graphH * (1.0 - (1.0 * bgHighThresh / graphMaxBG)));
        dc.drawLine(graphOffsetX+graphW-markerWidth, graphOffsetY + graphH * (1.0 - (1.0 * bgLowThresh / graphMaxBG)), graphOffsetX+graphW, graphOffsetY + graphH * (1.0 - (1.0 * bgLowThresh / graphMaxBG)));
        for (var fgbg=0; fgbg<2; fgbg++) {
	        for (var i=0; i < chartBG.size(); i+=2) {
	        	var mins = chartBG[i];
	        	var bgmgdl = chartBG[i+1];
	        	if (bgmgdl > graphMaxBG) {
	        		bgmgdl = graphMaxBG;
	        	}
	        	if ((mins * 60) >= startSec) {
		            // chartBG are in mgDL, just below time=graphMaxBG mgdl, bottom of screen=0 mgdl;
		            var X1 = graphOffsetX + graphW * ((mins * 60) - startSec) / (graphHours * 60 * 60);
		            var Y1 = graphOffsetY + graphH * (1.0 - (1.0 * bgmgdl / graphMaxBG));
	//	            myPrintLn("i: " + i + ", bg: " + chartBG[i]["bgmgdl"] + ", mills: " + chartBG[i]["mills"]);
					if (fgbg == 0) {
				        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
			            dc.fillCircle(X1, Y1, graphCircleSize+1);
		            } else {
				        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_BLUE);
				        if ((bgmgdl > bgHighThresh) || (bgmgdl < bgLowThresh)) {
					        dc.setColor(Gfx.COLOR_DK_RED, Gfx.COLOR_RED);
				        }
			            dc.fillCircle(X1, Y1, graphCircleSize);
		            }
	            }
	        }
        }
	}

    function strikeThrough(dc, bgStr, theFont, textX, textY) {
    	var w = 1.1 * dc.getTextWidthInPixels(bgStr, theFont);
    	var h = Gfx.getFontHeight(theFont);
    	var x = textX - (w / 2);
    	var hOffset = h / 12;
    	var hSize = h / 16;
		var y = textY + (h / 2) - hOffset; // - (h / 8 / 2);
        dc.fillRectangle(x, y, w, hSize);
        dc.fillRectangle(x, y + (hOffset * 2), w, hSize);
    }

	function mySetColor(dc, fgCol, bgCol) {
		curFgCol = fgCol;
		curBgCol = bgCol;
        dc.setColor(fgCol, bgCol);
    }

	function shadowText(dc, x, y, font, str, attr) {
		var shadowColor = shadowColor(curFgCol);
		var largeShadow = (shadowWidth >= 2) &&
				          ((font == Gfx.FONT_NUMBER_HOT) ||
				           (font == Gfx.FONT_LARGE));
		// first, draw background:
        //dc.drawText(x, y, font, str, attr);
        if (curBgCol != Gfx.COLOR_TRANSPARENT) {
	        dc.setColor(curBgCol, curBgCol);
	        var strWidth = dc.getTextWidthInPixels(str.toString(), font) + 2*shadowWidth;
	        var strHeight = Gfx.getFontHeight(font) + 2*shadowWidth - 2*Gfx.getFontDescent(font) + 4;
	        var strX = x - shadowWidth;
	        var strY = y - shadowWidth + Gfx.getFontDescent(font) - 2;
	        if (attr == Gfx.TEXT_JUSTIFY_CENTER) {
	        	strX = x - strWidth / 2;
	        } else if (attr == Gfx.TEXT_JUSTIFY_RIGHT) {
	        	strX = x - strWidth + shadowWidth;
	        }
	        dc.fillRectangle(strX, strY, strWidth, strHeight);
        }
		//myPrintLn("shadowColor="+shadowColor+", bgColor="+bgColor+", curBgCol="+curBgCol+", curFgCol="+curFgCol+", transparent="+Gfx.COLOR_TRANSPARENT);
		// draw outlines:
        dc.setColor(shadowColor, Gfx.COLOR_TRANSPARENT);
/*
        dc.drawText(x-1, y-1, font, str, attr);
        dc.drawText(x-1, y+1, font, str, attr);
        dc.drawText(x+1, y-1, font, str, attr);
        dc.drawText(x+1, y+1, font, str, attr);
 */
        if (largeShadow) {
	        dc.drawText(x-2, y-2, font, str, attr);
/*	        dc.drawText(x-2, y+2, font, str, attr);
	        dc.drawText(x+2, y-2, font, str, attr);
*/
	        dc.drawText(x+2, y+2, font, str, attr);
/*neverused	        dc.drawText(x, y-1, font, str, attr);
	        dc.drawText(x, y+1, font, str, attr);
	        dc.drawText(x-1, y, font, str, attr);
	        dc.drawText(x+1, y, font, str, attr);
*/
/*
	        dc.drawText(x, y-2, font, str, attr);
	        dc.drawText(x, y+2, font, str, attr);
	        dc.drawText(x-2, y, font, str, attr);
	        dc.drawText(x+2, y, font, str, attr);
*/
	        dc.drawText(x-1, y+1, font, str, attr);
	        dc.drawText(x+1, y-1, font, str, attr);
        } else {
//	        dc.drawText(x-1, y-1, font, str, attr);
//	        dc.drawText(x-1, y+1, font, str, attr);
//	        dc.drawText(x+1, y-1, font, str, attr);
//	        dc.drawText(x+1, y+1, font, str, attr);
        }
		// draw text foreground:
        dc.setColor(curFgCol, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, str, attr);
        // restore colors:
        dc.setColor(curFgCol, curBgCol);
    }


	function getHR() {
		var hasHR = (hrIcon != null) && (((Toybox has :ActivityMonitor) && (ActivityMonitor has :HeartRateIterator)) ? true : false);
		var newHRStr = "";
		if (hasHR) {
			var hr=Activity.getActivityInfo().currentHeartRate;
			if( hr != null) {
			    newHRStr = hr.toString();
			} else {
				var heart = ActivityMonitor.getHeartRateHistory(1, true);
				var sample = heart.next();
				if (sample != null) {
					var rate = sample.heartRate;
					if (rate != ActivityMonitor.INVALID_HR_SAMPLE) {
						newHRStr = rate.toString();
					}
				}
			}
		}
		//myPrintLn("hr="+newHRStr);
		return newHRStr;
	}

	function getSteps() {
		var newStepStr = "";
		if ((stepIcon != null) && (Toybox has :ActivityMonitor)) {
			var activityInfo = ActivityMonitor.getInfo();
			var steps = activityInfo.steps;
			newStepStr = steps.toString();
		}
		//myPrintLn("steps="+newStepStr);
		return newStepStr;
	}

    // Update the view
    function onUpdate(dc) {
        // Get and show the current time
        var now = Time.now();
        var info = Calendar.info(now, Time.FORMAT_LONG);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]);
        var mySettings = Sys.getDeviceSettings();
        var clockMode = mySettings.is24Hour;
        var notificationCount = mySettings.notificationCount;

        dc.clearClip();

        var fgColorVal = pickColor(fgColor, (now.value() / 60) * 3);
        var bgColorVal = pickColor(bgColor, (now.value() / 60) * 7);
//        if (fgColorVal == bgColorVal) {
//        	bgColorVal = shadowColor(fgColorVal);
//        }
        auxColorVal = shadowColor(bgColorVal);

        mySetColor(dc, bgColorVal,bgColorVal);
        clockBgColorVal = bgColorVal;
        dc.clear();

		if ((fetchMode == fetchModeNormal) ||
			(fetchMode == fetchModeDevice) ||
			(fetchMode == fetchModeDeviceMin1)) {
			drawChart(dc, now.value());
		}

        if (notificationCount > 0) {
            mySetColor(dc, bgColorVal,auxColorVal);
        } else {
            mySetColor(dc, auxColorVal,Gfx.COLOR_TRANSPARENT);
        }
        shadowText(dc, width/2,dateLine,dateFont,dateStr,Gfx.TEXT_JUSTIFY_CENTER);
        mySetColor(dc, fgColorVal,Gfx.COLOR_TRANSPARENT);

        clockFgColorVal = fgColorVal;
        drawClock(dc, clockMode, info);

		// heart rate, steps...
		hrStr = getHR();
		stepStr = getSteps();
		hrFont = null;
		stepFont = null;

/**********************
    Monitor status codes show which info is available and being monitored.
    Error status code and data is shown only when info is available and in error state, as noted.

    Monitor/Error status code key:
     * BT = bluetooth is not connected between Garmin device and phone
     * W = watch (Garmin device) battery status is 20% or lower
     * L = closed loop hasn't run in over 15 minutes
     * P = pump is suspended, or battery is 25% or lower, or 1.25v or lower
     * UP = loop uploader (iPhone or rig) battery is 25% or lower
     * R = pump reservoir is 20U or lower
     * CA = cannula age is over 72 hours

    In addition:
        - Elapsed time will be highlighted when BG is over 15 minutes old,
        - BG will be highlighted when out of range [70, 240] (mg/dL), or [3.9, 13.3] (mmol),
        - Date will be highlighted when any phone notifications are waiting, per Connect IQ.

    Loop and pump status is shown when info is available:
     * e = eventual outcome (bg) according to prediction from Loop or OpenAPS
     * i = IOB
     * c = COB
     * t = last enacted temp basal

    Connect IQ 2.0 Watches that do not support onPartialUpdate: Fenix Chronos, Forerunner 735xt, VivoactiveHR
**********************/

        var deviceStatus = " ";
        var errorStatus = " ";
        var monitorStatus = " ";
        var looping = false;

        if (nextEventSecs > 0) {
			var remainingMinutes = (nextEventSecs - Time.now().value()) / 60;
//			myPrintLn("nextEventSecs=" + nextEventSecs + ", now.value="+Time.now().value()+ ", remainingMinutes="+remainingMinutes);
            var syncStr = ".................";
            monitorStatus = monitorStatus + syncStr.substring(0,remainingMinutes) + " ";
        }

        if (!Sys.getDeviceSettings().phoneConnected) {
            errorStatus = errorStatus + "BT ";
        }

        if (myHasKey(bgdata, "blefail")) {
            errorStatus = errorStatus + "BLE ";
        }

        {
            var stats = Sys.getSystemStats();
            if (stats.battery <= watchBatThresh) {
                errorStatus = errorStatus + "W" + stats.battery.toNumber().toString() + "% ";
            }
        }

        var loopElapsedMinutes = 0;
        if (bgdata != null) {
            if (myHasKey(bgdata, "loopTime") &&
                !bgdata["loopTime"].equals("") &&
                myHasKey(bgdata, "eventual")) {
                var loopTime = bgdata["loopTime"];
                var options = { :year => loopTime.substring(0,4).toNumber(),
                                :month => loopTime.substring(5,7).toNumber(),
                                :day => loopTime.substring(8,10).toNumber(),
                                :hour => loopTime.substring(11,13).toNumber(),
                                :minute => loopTime.substring(14,16).toNumber(),
                                :second => loopTime.substring(17,19).toNumber() };
                var myMoment = Calendar.moment(options);
                loopElapsedMinutes = Math.floor(Time.now().subtract(myMoment).value() / 60);
                //myPrintLn("loopElapsedMinutes: " + loopElapsedMinutes);
                if (myHasKey(bgdata, "suspended") &&
                    (bgdata["suspended"] == true)) {
                    errorStatus = errorStatus + "Psusp ";
                } else if (loopElapsedMinutes > loopTimeThresh) {
                    errorStatus = errorStatus + "L" + loopElapsedMinutes + "m ";
                } else {
                    var eventual = bgdata["eventual"];
                    if (myHasKey(bgdata, "bgmgdl") &&
                        myHasKey(bgdata, "bg") &&
                        bgdata["bgmgdl"].toNumber() != bgdata["bg"].toNumber()) {
                        eventual = eventual / 18.018;
                        eventual = eventual.format("%.1f");
                    }
                    deviceStatus = deviceStatus + "e" + eventual + " ";
                    looping = true;
                }
                monitorStatus = monitorStatus + "L ";
            }

            if (myHasKey(bgdata, "iob")) {
                deviceStatus = deviceStatus + "i" + bgdata["iob"].format("%.1f") + " ";
            }

            if (myHasKey(bgdata, "cob")) {
                deviceStatus = deviceStatus + "c" + bgdata["cob"].format("%d") + " ";
            }

            if (looping &&
                myHasKey(bgdata, "basal") &&
                !bgdata["basal"].equals("")) {
                deviceStatus = deviceStatus + "t" + bgdata["basal"].format("%.1f") + " ";
            } else {
	            if ((fetchMode >= fetchModeDevice) &&
	            	myHasKey(bgdata, "propbasal") &&
	                !bgdata["propbasal"].equals("")) {
	                deviceStatus = deviceStatus + "t" + bgdata["propbasal"] + " ";
	            }
            }

            if (myHasKey(bgdata, "pumpbat")) {
                if (bgdata["pumpbat"] instanceof Toybox.Lang.Float ) {
                    if (bgdata["pumpbat"] < pumpBatThreshV) {
                        errorStatus = errorStatus + "P" + bgdata["pumpbat"].format("%.2f") + "v ";
                    }
                } else {
                    if (bgdata["pumpbat"] <= pumpBatThreshPct) {
                        errorStatus = errorStatus + "P" + bgdata["pumpbat"] + "% ";
                    }
                }
                monitorStatus = monitorStatus + "P ";
            }

            if (myHasKey(bgdata, "upbat")) {
                if (bgdata["upbat"] <= upBatThresh) {
                    errorStatus = errorStatus + "UP" + bgdata["upbat"] + "% ";
                }
                monitorStatus = monitorStatus + "UP ";
            }

            if (myHasKey(bgdata, "reservoir")) {
                if (bgdata["reservoir"] < reservoirThresh) {
                    errorStatus = errorStatus + "R" + bgdata["reservoir"].format("%d") + "u ";
                }
                monitorStatus = monitorStatus + "R ";
            }

            if (myHasKey(bgdata, "cage")) {
                if (bgdata["cage"] > cageThresh) {
                    errorStatus = errorStatus + "CA" + bgdata["cage"] + "hr ";
                }
                monitorStatus = monitorStatus + "CA ";
            }

            var elapsedMinutes = 0;
            if (myHasKey(bgdata, "elapsedMills")) {
                var elapsedMills = bgdata["elapsedMills"];
                var myMoment = new Time.Moment(elapsedMills / 1000);
                elapsedMinutes = Math.floor(Time.now().subtract(myMoment).value() / 60);
            }
            if ((elapsedMinutes == 0) &&
                (loopElapsedMinutes > 0) &&
                myHasKey(bgdata, "elapsedStamp")) {
                elapsedMinutes = loopElapsedMinutes;
            }

            var elapsed = "";
            if (elapsedMinutes >= 0) {
                elapsed = elapsedMinutes.format("%d") + "m";
                if ((elapsedMinutes > 9999) || (elapsedMinutes < -999)) {
                    elapsed = "";
                }
            }

            if ((myHasKey(bgdata, "bg") || myHasKey(bgdata, "bgmgdl"))) {
                var bg = "Settings";
                var forceNumber = false;
                if (myHasKey(bgdata, "bgmgdl") &&
                    ((bgdata["bgmgdl"].toNumber() < bgLowThresh) ||
                    (bgdata["bgmgdl"].toNumber() > bgHighThresh))) {
                    mySetColor(dc, Gfx.COLOR_RED ,Gfx.COLOR_WHITE);
                }
                if ((bgDisplay != bgDisplayNormal) && myHasKey(bgdata, "bgmgdl")) {
                    if (bgDisplay == bgDisplayMGDL) {
                        bg = bgdata["bgmgdl"].toNumber();
                        //myPrintLn("view: mgdl: " + bg);
                    } else if (bgDisplay == bgDisplayMMOL) {
                        bg = bgdata["bgmgdl"].toNumber() / 18.018;
                        bg = bg.format("%.1f");
                        forceNumber = true;
                        //myPrintLn("view: mmol: " + bg);
                    } else if (bgDisplay == bgDisplayRoman) {
                        bg = romanize(bgdata["bgmgdl"].toNumber());
                        //myPrintLn("view: roman: " + bg);
                    } else if (bgDisplay == bgDisplayHEX) {
                        bg = "0x" + bgdata["bgmgdl"].toNumber().format("%X");
                        //myPrintLn("view: HEX: " + bg);
                    } else if (bgDisplay == bgDisplayHex) {
                        bg = "0x" + bgdata["bgmgdl"].toNumber().format("%x");
                        //myPrintLn("view: hex: " + bg);
                    } else if (bgDisplay == bgDisplaySCIENTIFIC) {
                        bg = bgdata["bgmgdl"].toNumber().format("%1.2E");
                        //myPrintLn("view: SCIENTIFIC: " + bg);
                    } else if (bgDisplay == bgDisplayScientific) {
                        bg = bgdata["bgmgdl"].toNumber().format("%1.2e");
                        //myPrintLn("view: scientific: " + bg);
                    } else if (bgDisplay == bgDisplayOctal) {
                        bg = "0o" + bgdata["bgmgdl"].toNumber().format("%o");
                        //myPrintLn("view: octal: " + bg);
                    } else if (bgDisplay == bgDisplayZeroPad) {
                        forceNumber = true;
                        bg = bgdata["bgmgdl"].toNumber().format("%03d");
                        //myPrintLn("view: zero-padded: " + bg);
                    } else if (bgDisplay == bgDisplayVersion) {
                        bg = "V" + viewVersion; //bgdata["version"];
                        //myPrintLn("view: version: " + bg);
                    }
                } else {
                    if (myHasKey(bgdata, "bg")) {
                        bg = bgdata["bg"];
                        if (!myHasKey(bgdata, "elapsedMills")) {
		                    mySetColor(dc, Gfx.COLOR_RED ,Gfx.COLOR_WHITE);
	                    }
                    } else {
                        bg = bgdata["bgmgdl"];
                    }
                    forceNumber = true;
                }

                if (forceNumber || bg instanceof Number || bg instanceof Float) {
					clipText(dc, bgLine, Gfx.FONT_NUMBER_HOT);
                    shadowText(dc, width/2,bgLine,Gfx.FONT_NUMBER_HOT,bg,Gfx.TEXT_JUSTIFY_CENTER);
		            if (elapsedMinutes > bgTimeThresh) {
		            	strikeThrough(dc, bg.toString(), Gfx.FONT_NUMBER_HOT, width/2, bgLine);
		            }
                } else {
					clipText(dc, bgLine + 2 + Gfx.getFontDescent(Gfx.FONT_NUMBER_HOT), Gfx.FONT_LARGE);
                    shadowText(dc, width/2,bgLine + 2 + Gfx.getFontDescent(Gfx.FONT_NUMBER_HOT),Gfx.FONT_LARGE,bg,Gfx.TEXT_JUSTIFY_CENTER);
		            if (elapsedMinutes > bgTimeThresh) {
		            	strikeThrough(dc, bg.toString(), Gfx.FONT_LARGE, width/2, bgLine + 2 + Gfx.getFontDescent(Gfx.FONT_NUMBER_HOT));
		            }
                }
            }

            var delta = "";
            if (myHasKey(bgdata, "delta")) {
                delta = bgdata["delta"].toString();
            } else {
                // - log bg and calc. delta
            }

            var directionIcon = null;
            if (myHasKey(bgdata, "direction")) {
                if (myHasKey(dirSwitch, bgdata["direction"])) {
                    directionIcon = dirSwitch[bgdata["direction"]];
                }
            } else {
                // - pick direction based on delta (or further-back-in-time delta)
            }

            var bitmapDim = 24;
            var offset = ((dc.getTextWidthInPixels(elapsed, directionFont) + 5) -
                          (dc.getTextWidthInPixels(delta, directionFont) + 3)) / 2;
            var dirHorzOffset = -bitmapDim / 2;
            var dirVertOffset = (Gfx.getFontHeight(directionFont) - bitmapDim) / 2 + 2;
//            var maxLineHeight = Gfx.getFontHeight(directionFont) + 2;
//            if (bitmapDim > maxLineHeight) {
//                maxLineHeight = bitmapDim;
//            }
//            mySetColor(dc, bgColorVal,bgColorVal);
//            dc.fillRectangle(0, directionLine, width, maxLineHeight);
            if (elapsedMinutes > bgTimeThresh) {
                mySetColor(dc, Gfx.COLOR_RED ,Gfx.COLOR_WHITE);
            } else {
		        mySetColor(dc, auxColorVal,Gfx.COLOR_TRANSPARENT);
//                mySetColor(dc, auxColorVal,bgColorVal);
            }
			clipText(dc, directionLine,directionFont);
            shadowText(dc, offset + (width/2) - (bitmapDim/2) - 5,directionLine,directionFont,
                        elapsed,
                        Gfx.TEXT_JUSTIFY_RIGHT);
            shadowText(dc, offset + (width/2) + (bitmapDim/2) + 3,directionLine,directionFont,
                        delta,
                        Gfx.TEXT_JUSTIFY_LEFT);
            dc.clearClip();
            if (null != directionIcon) {
                dc.drawBitmap(offset + (width/2) + dirHorzOffset, directionLine + dirVertOffset, directionIcon);
            }
            mySetColor(dc, auxColorVal,Gfx.COLOR_TRANSPARENT);
        }   // bgdata != null

		clipText(dc, elapsedLine,elapsedFont);
        if (!errorStatus.equals(" ")) {
            mySetColor(dc, Gfx.COLOR_RED, Gfx.COLOR_WHITE);
            //myPrintLn("errorStatus: " + errorStatus);
            //myPrintLn("deviceStatus: " + deviceStatus);
            shadowText(dc, (width/2),elapsedLine,elapsedFont, errorStatus, Gfx.TEXT_JUSTIFY_CENTER);
            mySetColor(dc, auxColorVal,Gfx.COLOR_TRANSPARENT);
        } else if (!deviceStatus.equals(" ")) {
            //myPrintLn("deviceStatus: " + deviceStatus);
            mySetColor(dc, auxColorVal,Gfx.COLOR_TRANSPARENT);
            shadowText(dc, (width/2),elapsedLine,elapsedFont, deviceStatus, Gfx.TEXT_JUSTIFY_CENTER);
        } else if ((fetchMode == fetchModeNormal) ||
        		   (fetchMode == fetchModeDevice) ||
        		   (fetchMode == fetchModeDeviceMin1)) {
            //myPrintLn("no error or device status to report");
            var bitmapDim = 24;
            var iconVertOffset = (Gfx.getFontHeight(elapsedFont) - bitmapDim) / 2 + 2;
            var iconHorzOffset = (dc.getTextWidthInPixels(hrStr, elapsedFont) -
            					  dc.getTextWidthInPixels(stepStr, elapsedFont)) / 2;
            mySetColor(dc, auxColorVal,Gfx.COLOR_TRANSPARENT);
            hrX = iconHorzOffset + width / 2 - 28;
            hrY = elapsedLine;
	        stepX = iconHorzOffset + width / 2 + 24;
	        stepY = elapsedLine;
	        if (!hrStr.equals("")) {
	            hrFont = elapsedFont;
	            dc.drawBitmap(iconHorzOffset + width / 2 - 24, elapsedLine + iconVertOffset, hrIcon);
	        }
	        if (!stepStr.equals("")) {
		        stepFont = elapsedFont;
	            dc.drawBitmap(iconHorzOffset + width / 2, elapsedLine + iconVertOffset, stepIcon);
	        }
            drawHR(dc);
            drawSteps(dc);
	        dc.clearClip();
        }

        mySetColor(dc, auxColorVal,Gfx.COLOR_TRANSPARENT);
        if (!canDoBG) {
			clipText(dc, miscLine,Gfx.FONT_SMALL);
            shadowText(dc, width/2,miscLine,Gfx.FONT_SMALL,"Device unsupported",Gfx.TEXT_JUSTIFY_CENTER);
        } else if (setupReqd) {
			clipText(dc, miscLine,Gfx.FONT_SMALL);
            shadowText(dc, width/2,miscLine,Gfx.FONT_SMALL,"Setup required",Gfx.TEXT_JUSTIFY_CENTER);
        } else {
			clipText(dc, miscLine,Gfx.FONT_XTINY);
            if (!errorStatus.equals(" ")) {
                if (!deviceStatus.equals(" ")) {
                    shadowText(dc, width/2,miscLine,Gfx.FONT_XTINY,deviceStatus,Gfx.TEXT_JUSTIFY_CENTER);
                }
            } else {
                var statText = monitorStatus;
                if ((bgdata != null) &&
                    (bgdata instanceof Dictionary) &&
                    myHasKey(bgdata, "rawbg")) {
                    statText = bgdata["rawbg"] + statText;
                }
                if ((fetchMode == fetchModeNormal) ||
                	(fetchMode == fetchModeDevice)) {
					clipText(dc, miscLine,Gfx.FONT_XTINY);
	                shadowText(dc, width/2,miscLine,Gfx.FONT_XTINY,statText,Gfx.TEXT_JUSTIFY_CENTER);
                }
            }
            if ((!errorStatus.equals(" ") && deviceStatus.equals(" ")) ||
            	(errorStatus.equals(" ") && !deviceStatus.equals(" "))) {
            	if (((fetchMode == fetchModeNormal) && deviceStatus.equals(" ")) ||
            		(fetchMode == fetchModeDeviceMin1)) {
		            var bitmapDim = 24;
		            var iconVertOffset = (Gfx.getFontHeight(Gfx.FONT_XTINY) - bitmapDim) / 2 + 2;
		            var iconHorzOffset = (dc.getTextWidthInPixels(hrStr, Gfx.FONT_XTINY) -
		            					  dc.getTextWidthInPixels(stepStr, Gfx.FONT_XTINY)) / 2;
		            hrX = iconHorzOffset + width / 2 - 28;
		            hrY = miscLine;
			        stepX = iconHorzOffset + width / 2 + 24;
			        stepY = miscLine;
			        if (!hrStr.equals("")) {
			            hrFont = Gfx.FONT_XTINY;
			            dc.drawBitmap( iconHorzOffset + width / 2 - 24, miscLine + iconVertOffset, hrIcon);
			        }
			        if (!stepStr.equals("")) {
				        stepFont = Gfx.FONT_XTINY;
			            dc.drawBitmap(iconHorzOffset + width / 2, miscLine + iconVertOffset, stepIcon);
			        }
		            drawHR(dc);
		            drawSteps(dc);
			        dc.clearClip();
		        }
	        }
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
//    function onHide() {
    	//myPrintLn("view.onHide(), ctr=" + ctr); ctr++;
//        var now=Sys.getClockTime();
//        var ts=now.hour+":"+now.min.format("%02d");
//        Sys.println("onHide "+ts);
//    }

    // The user has just looked at their watch. Timers and animations may be started here.
//    function onExitSleep() {
//    	//myPrintLn("view.onExitSleep(), ctr=" + ctr); ctr++;
//    }

    // Terminate any active timers and prepare for slow updates.
//    function onEnterSleep() {
//    	//myPrintLn("view.onEnterSleep(), ctr=" + ctr); ctr++;
//    }

}

class bgbgDelegate extends Ui.WatchFaceDelegate {
    // The onPowerBudgetExceeded callback is called by the system if the
    // onPartialUpdate method exceeds the allowed power budget. If this occurs,
    // the system will stop invoking onPartialUpdate each second, so we set the
    // partialUpdatesAllowed flag here to let the rendering methods know they
    // should not be rendering a second hand.

    function onPowerBudgetExceeded(powerInfo) {
        //System.println( "Average execution time: " + powerInfo.executionTimeAverage );
        //System.println( "Allowed execution time: " + powerInfo.executionTimeLimit );
        partialUpdatesAllowed = false;
    }

//    function initialize() {
        //WatchFaceDelegate.initialize();
//    }
}
