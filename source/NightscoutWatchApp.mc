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

using Toybox.Application as App;
using Toybox.Background;
using Toybox.Time;
using Toybox.System as Sys;

// NOTE: every object created here uses memory in the background process (as well as the watchface process.)
//       the background app is extremely limited in memory (32KB), so only define what is absolutely needed.

// cgm sync state
var nextEventSecs = 0;

(:background)
class NightscoutWatchApp extends App.AppBase {
    var myView = null;
    var bgdataPreView = null;

	// cgm sync state
	const defaultOffsetSeconds = 15;
	var offsetSeconds = defaultOffsetSeconds;
	var shiftingOffset = false;
	var syncAtSecond = -1;

    function initialize() {
		Sys.println("app initialize");
        //this gets called in both the foreground and background
        AppBase.initialize();
    }

    // onStart() is called on application start up
    //function onStart(state) {
    //}

    // onStop() is called when your application is exiting
    //function onStop(state) {
    //}

    function updateEvent(stat) {
		//Sys.println("updateEvent");
        if (stat) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        } else {
            System.println("updateEvent: invalid nsurl, not starting background process");
            Background.deleteTemporalEvent();
        }
    }

    function onSettingsChanged() {
		//Sys.println("onSettingsChanged");
        offsetSeconds = defaultOffsetSeconds;
        App.getApp().setProperty("offsetSeconds", offsetSeconds);
        if (myView != null) {
	        var stat = myView.onSettingsChanged();
	        updateEvent(stat);
        }
        var temp = Application.getApp().getProperty("syncAtSecond");
        if (temp!=null && temp instanceof Number) {
        	if (syncAtSecond != temp) {
	        	syncAtSecond=temp;
	        	//Sys.println("syncAtSecond="+syncAtSecond);
		        if ((syncAtSecond >= 0) && (syncAtSecond < (5*60))) {
		        	resync(0);
	        	}
        	}
    	}
    }

    // Return the initial view of your application here
    function getInitialView() {
		Sys.println("getInitialView");
        myView = new bgbgView(bgdataPreView);

        //register for temporal events if they are supported
        if(Toybox.System has :ServiceDelegate) {
            Background.deleteTemporalEvent();
            var thisApp = Application.getApp();
	        var temp = thisApp.getProperty("offsetSeconds");
            if (temp!=null && temp instanceof Number) {
            	offsetSeconds=temp;
            	//Sys.println("from OS: offsetSeconds="+offsetSeconds);
        	}
            updateEvent(true /*myView.getStatus()*/);
	        temp = thisApp.getProperty("syncAtSecond");
	        if (temp!=null && temp instanceof Number) {
	        	syncAtSecond=temp;
	        	//Sys.println("syncAtSecond="+syncAtSecond);
	    	}
        } else {
            System.println("****background not available on this device****");
        }
        if( Toybox.WatchUi has :WatchFaceDelegate ) {
            return [ myView, new bgbgDelegate()];
        } else {
            return [ myView ];
        }
    }

	function resync(elapsedMills) {
        var myMoment = new Time.Moment(elapsedMills / 1000);
        var nextEventSeconds;
        if ((syncAtSecond < 0) || (syncAtSecond >= (5*60))) {
        	// auto-sync:
            var elapsedSeconds = Time.now().subtract(myMoment).value();
            Sys.println("elapsedSeconds="+elapsedSeconds+", now="+Time.now().value()+", elapsedMills="+elapsedMills);
            if ((elapsedSeconds >= (5 * 60)) &&
            	(elapsedSeconds < (10 * 60))) {
            	if (shiftingOffset) {
            		offsetSeconds += 60;
            		offsetSeconds = offsetSeconds % (5 * 60);
            	} else {
            		// wait for a 2nd 5-9 minute elapsed, to confirm we are out of sync, not just a missed reading
            		shiftingOffset = true;
            	}
        	} else {
        		shiftingOffset = false;
        	}
            nextEventSeconds = 5 * 60 + (offsetSeconds - (elapsedSeconds % (5 * 60)));
            //Sys.println("onBackgroundData: elapsedSeconds="+elapsedSeconds+", offsetSeconds="+offsetSeconds+", shiftingOffset="+shiftingOffset);
        } else {
        	// manual sync:
            var curTime = Time.now().value();
        	var nextTime = curTime - (curTime % (5*60));
        	nextTime += syncAtSecond + 5*60;
        	nextEventSeconds = nextTime - curTime;
        	Sys.println("manual sync: syncAtSecond="+syncAtSecond+", now="+curTime+", nextTime="+nextTime);
        }
        while (nextEventSeconds < 5 * 60) {
        	if (nextEventSeconds > ((5 * 60) - 30)) {
        		nextEventSeconds = 5 * 60;
        	} else {
                nextEventSeconds += (5 * 60);
            }
        }
		Sys.println("nextEventSeconds="+nextEventSeconds);
        Background.registerForTemporalEvent(new Time.Duration(nextEventSeconds));
        if (nextEventSeconds >= 6*60) {
            nextEventSecs = Time.now().value() + nextEventSeconds;
        } else {
        	nextEventSecs = 0;
        }
	}

    function onBackgroundData(data) {
		//Sys.println("onBackgroundData data: " + data);

        if ((data != null) &&
            data.hasKey("elapsedMills") &&
            (data["elapsedMills"] > 0)) {
            var elapsedMills = data["elapsedMills"].toNumber();
            resync(elapsedMills);
        } else {
            //Sys.println("onBackgroundData invalid data: "+data);
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }

        //Sys.println("onBackgroundData update property");
        if (myView == null) {
	        bgdataPreView = data;
			Sys.println("onBackgroundData myView null - saving data");
        } else {
	        myView.setBgData(data);
	        myView.requestUpdate();
	        bgdataPreView = null;
        }

        App.getApp().setProperty("offsetSeconds", offsetSeconds);
    }

    function getServiceDelegate(){
		//Sys.println("getServiceDelegate");
        return [new BgbgServiceDelegate()];
    }
}
