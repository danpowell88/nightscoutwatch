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

using Toybox.Background;
using Toybox.Communications;
using Toybox.System as Sys;

// The Service Delegate is the main entry point for background processes
// our onTemporalEvent() method will get run each time our periodic event
// is triggered by the system.

(:background)
class BgbgServiceDelegate extends Toybox.System.ServiceDelegate {
    var receiveCtr = 0;
    var bgdata = {};
    var reqNum = 0;
    var propReq = {};

    enum {
        fetchModeNormal     = 0,
        fetchModeNormalMin  = 1,
        fetchModeDevice     = 2,
        fetchModeDeviceMin1 = 3,
        fetchModeDeviceMin2 = 4 }

    function printMem() {
        ////var myStats = System.getSystemStats();
        ////Sys.println("memory: total: " + myStats.totalMemory + ", used: " + myStats.usedMemory + ", free: " + myStats.freeMemory);
        ////Sys.println("free memory: " + System.getSystemStats().freeMemory);
    }

    function initialize() {
        Sys.ServiceDelegate.initialize();
    }

	function myHasKey(obj, k) {
        if ((obj != null) &&
            (obj instanceof Dictionary)) {
            return (obj.hasKey(k));
        }
        return false;
	}

	function cleanHashZero(data, keyHash) {
        if ((data != null) &&
            (data instanceof Dictionary)) {
	    	var keys = data.keys();
	    	for (var i=0; i<keys.size(); i++) {
	    		if (!keyHash.hasKey(keys[i])) {
	    			data.remove(keys[i]);
	    		}
	    	}
    	}
	}

    function cleanHashMany(data, key1, keyHash) {
        if ((data != null) &&
            (data instanceof Dictionary) &&
            data.hasKey(key1)) {
    		cleanHashZero(data[key1], keyHash);
    	}
    }

    function cleanHashOne(data, key1, key2) {
    	var keyHash = { key2=>1 };
    	cleanHashMany(data, key1, keyHash);
    }

    function onReceiveProperties(responseCode, data) {
        //Sys.println("in OnReceiveProperties");
        if ((responseCode == 200) &&
            (data != null) &&
            (data instanceof Dictionary)) {
            if (data.hasKey("buckets")) {
            	var buckets = data["buckets"];
            	if ((buckets != null) &&
	            	(buckets instanceof Array)) {
	            	for (var i=0; i < buckets.size(); i++) {
	            		if ((buckets[i] != null) &&
	            			(buckets[i] instanceof Dictionary)) {
			                if (buckets[i].hasKey("mills")) {
			                	if (i == 0) {
				                    bgdata["elapsedMills"] = buckets[i]["mills"];
			                    }
			                	buckets[i]["mills"] = buckets[i]["mills"] / 1000;
			                }
			                if (buckets[i].hasKey("sgvs")) {
			                	var sgvs = buckets[i]["sgvs"];
					            var cleanBgnowSgvs = {"direction"=>1, "scaled"=>1};
			                	if (sgvs.size() > 0) {
				                    cleanHashZero(sgvs[0], cleanBgnowSgvs);
			                    }
			                	if (sgvs.size() > 1) {
				                    cleanHashZero(sgvs[1], cleanBgnowSgvs);
			                    }
			                }
				            var cleanBgnow = {"last"=>1, "mills"=>1};
				            if (i == 0) {
				                cleanBgnow["sgvs"] = 1;
				            }
			                cleanHashZero(buckets[i], cleanBgnow);
		                }
	                }
                }
            }
            // Clean (i.e., prune) the incoming data, instead of interpreting or copying it
            // in this way we can use as little memory/instructions as possible in the background process
            cleanHashOne(data, "basal", "display");
            cleanHashOne(data, "delta", "display");
            var cleanRawbg = {"mgdl"=>1, "noiseLabel"=>1};
            cleanHashMany(data, "rawbg", cleanRawbg);
            var cleanCage = {"age"=>1, "found"=>1};
            cleanHashMany(data, "cage", cleanCage);

	    	for (var i=0; i<data.keys().size(); i++) {
				var key1 = data.keys()[i];
	            bgdata["prop"][key1] = data[key1];
			}
            //Sys.println("propReq: " + propReq);
            printMem();
            if (propReq.size() > 0) {
	            myWebRequest(true, 0, false);
            }
        } else {
            Sys.println("Prop resp: " + responseCode);
            if (!myWebRequest(false, 0, false)) {
	            bgdata["httpfail"] = true;
	            if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE) {
		            bgdata["blefail"] = true;
	            }
            }
        }
        receiveCtr--;
        if (receiveCtr == 0) {
            printMem();
	        Sys.println("out OnReceiveProperties - exit");
        	//Sys.println("pr bgdata="+bgdata);
            Background.exit(bgdata);
        }
        //Sys.println("out OnReceiveProperties");
    }

    function onReceiveDevice(responseCode, data) {
        //Sys.println("in OnReceiveDevice");
        if ((responseCode == 200) &&
            (data != null) &&
            (data.size() > 0) &&
            (data[0] instanceof Dictionary)) {

            var cleanDevice = {"loop"=>1, "pump"=>1, "uploader"=>1, "uploaderBattery"=>1, "openaps"=>1};
            cleanHashZero(data[0], cleanDevice);

            // Clean (i.e., prune) the incoming data, instead of interpreting or copying it
            // in this way we can use as little memory/instructions as possible in the background process
            if (data[0].hasKey("loop")) {
            	var cleanDev2 = {"loop"=>1, "uploader"=>1, "pump"=>1};
            	cleanHashZero(data[0], cleanDev2);
            	cleanHashOne(data[0], "uploader", "battery");
            	var cleanLoop = {"failureReason"=>1, "predicted"=>1, "cob"=>1, "iob"=>1, "enacted"=>1};
            	cleanHashMany(data[0], "loop", cleanLoop);
            	if (data[0]["loop"].hasKey("failureReason")) {
            		data[0]["loop"]["failureReason"] = 1;
	                bgdata["httpfaildevice"] = true;
            	}
            	if (data[0]["loop"].hasKey("predicted") &&
                    myHasKey(data[0]["loop"]["predicted"], "values") &&
                    (data[0]["loop"]["predicted"]["values"].size() > 0)) {
                    data[0]["loop"]["predicted"]["values"] = [ data[0]["loop"]["predicted"]["values"][data[0]["loop"]["predicted"]["values"].size()-1] ];
                }
	            var cleanEnacted = {"rate"=>1, "duration"=>1};
	            cleanHashMany(data[0]["loop"], "enacted", cleanEnacted);
            	cleanHashOne(data[0]["loop"], "iob", "iob");
        	}
			if (data[0].hasKey("pump")) {
            	var cleanPump = {"battery"=>1, "reservoir"=>1, "status"=>1, "iob"=>1};
	            cleanHashMany(data[0], "pump", cleanPump);
	            cleanHashOne(data[0]["pump"], "iob", "bolusiob");
            }
            if (data[0].hasKey("openaps")) {
	            cleanHashOne(data[0]["openaps"], "iob", "iob");
	            var cleanEnacted = {"rate"=>1, "duration"=>1};
	            cleanHashMany(data[0]["openaps"], "enacted", cleanEnacted);
	            var cleanSuggested = {"timestamp"=>1, "eventualBG"=>1, "COB"=>1};
	            cleanHashMany(data[0]["openaps"], "suggested", cleanSuggested);

	            bgdata["dev1"] = data;
            } else {
				if (data[0].hasKey("pump") && !data[0].hasKey("loop")) {
		            bgdata["dev1"] = data;
	                // load additional loop devicestatus:
	                myWebRequest(true, fetchModeDevice, true);
	            } else {
		            bgdata["dev2"] = data;
	            }
            }
        } else {
            Sys.println("Dev resp: " + responseCode + ", data=" + data);
            if (bgdata.hasKey("dev1") ||
                bgdata.hasKey("dev2")) {
                // we're good - no loop or openaps data is available, but we did get device data.
            } else {
                bgdata["httpfaildevice"] = true;
            }
        }
        receiveCtr--;
        if (receiveCtr == 0) {
            data = null;	// free memory for next fetch
            myWebRequest(true, 0, false);
        }
        //Sys.println("dev bgdata="+bgdata);
        //Sys.println("out OnReceiveDevice");
    }

    function onReceiveSGV(responseCode, data) {
        //Sys.println("in OnReceiveSGV");
        //myPrintLn("response: " + responseCode.toString());
        if ((responseCode == 200) &&
            (data != null) &&
        	(data instanceof Array) &&
            (data.size() > 1) &&
            (data[0] != null) &&
            (data[1] != null) &&
            !data[0].isEmpty() &&
            !data[1].isEmpty()
            ) {
            bgdata["sgv"] = data;
            var elapsedMills;
            elapsedMills = 0;
            if (data[0].hasKey("sgv") &&
                data[0].hasKey("date") &&
                data[0].hasKey("direction")
                ) {
                elapsedMills = data[0]["date"];
	            //Sys.println("valid data: " + data);
            //} else {
	            //Sys.println("invalid data: " + data);
            }
            bgdata["elapsedMills"] = elapsedMills;
        } else {
            Sys.println("SGV resp: " + responseCode.toString());
            //Sys.println("data: " + data);
            if ((reqNum >= 4 /*maxRequests*/) || !myWebRequest(false, 0, false)) {
	            bgdata["httpfail"] = true;
	            if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE) {
		            bgdata["blefail"] = true;
	            }
            }
        }
		receiveCtr--;
        if (receiveCtr == 0) {
            printMem();
            Sys.println("out OnReceiveSGV - exit, bgdata="+bgdata);
	        Background.exit(bgdata);
        }
        //Sys.println("out OnReceiveSGV");
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
        while(url.substring(url.length()-1,url.length()).equals("/")) {
		    url = url.substring(0,url.length()-1);
        }
        if (url.substring(url.length()-9,url.length()).equals("/sgv.json")) {
		    url = url.substring(0,url.length()-9);
        }
		return url;
	}

    function makeNSURL(fetchMode, loop) {
        var thisApp = Application.getApp();
        var url = thisApp.getProperty("nsurl");
		if (url == null) { url = ""; }

		url = removeWhitespace(url);

        if (!url.equals("")) {
	        if (url.find("://") == null) {
    	        url = "https://" + url;
        	}
	        if ((propReq.size() == 0) && (fetchMode >= fetchModeDevice)) {
	        	if (!loop) {
		            url = url +
		                    "/api/v1/devicestatus.json?count=1&find[pump][$exists]";  // loop and openaps info available here is more compact
		            // Note: Loop deviceStatus is requested separately if we don't find openaps key along with pump key.
	            } else {
	                url = url +
	                        "/api/v1/devicestatus.json?count=1&find[loop][$exists]";  // loop and openaps info available here is more compact
                }
	        } else {
	            url = url +
//	                    "/api/v2/properties/buckets,rawbg,delta,cage"; // pump returns too much for tiny background process
//	                    "/api/v2/properties/buckets,delta,cage,basal"; // pump returns too much for tiny background process
	                    "/api/v2/properties/"; // pump returns too much for tiny background process
	            if (propReq.size() == 0) {
		            propReq = {"buckets"=>1,"rawbg,delta,cage"=>1,"basal"=>1};
		            //propReq = {"buckets,rawbg,delta,cage"=>1};
		            bgdata["prop"] = {};
	            }
	            var key1 = propReq.keys()[0];
	            propReq.remove(key1);
	            url = url + key1;
	        }
    	}
        return url;
	}

    function makeOfflineURL() {
        var thisApp = Application.getApp();
		var url = thisApp.getProperty("offlineUrl");
		if (url == null) { url = ""; }

		url = removeWhitespace(url);

        if (url.equals("")) {
        	if ((reqNum % 2) == 0) {
        		url = "X";
        	} else {
        		url = "S";
        	}
        }

        if (url.substring(0,1).toUpper().equals("X")) {
            url = "http://127.0.0.1:17580"; // xdrip+ local web server
        } else if (url.substring(0,1).toUpper().equals("S")) {
            url = "http://127.0.0.1:1979"; // Spike web server
        }

        if (!url.equals("")) {
	        if (url.find("://") == null) {
	            url = "http://" + url;
	        }
	        url = url + "/sgv.json?count=3";
        }
        //url = "https://tynbendad.github.io/pumptest/api/v1/xdrip-other-sgv.json";
        //url = "https://tynbendad.github.io/pumptest/api/v1/xdrip-g4-sgv.json";
        //url = "https://tynbendad.github.io/pumptest/api/v1/nightscout-sgv.json";
        //url = "https://tynbendad.github.io/pumptest/api/v1/tomato1.json";
        return url;
    }

    function myWebRequest(ns, fetchMode, loop) {
        var url = makeNSURL(fetchMode, loop);
        //    url = "https://tynbendad.github.io/pumptest/api/v1/test3.json";    // for testing
        //    url = "https://tynbendad.github.io/pumptest/api/v2/properties/simpletest2.json";   // for testing
        //Sys.println("fetching url: " + url);
        if (ns && !url.equals("")) {
	        //Sys.println("ns url: " + url);
            receiveCtr++;
    		reqNum++;
            if (fetchMode >= fetchModeDevice) {
	            printMem();
	            //Sys.println("initial Device request");
	            Communications.makeWebRequest(url, {"format" => "json"}, {}, method(:onReceiveDevice));
            } else {
	            //Sys.println("initial Properties request");
	            Communications.makeWebRequest(url, {"format" => "json"}, {}, method(:onReceiveProperties));
            }
            return true;
        } else {
	        url = makeOfflineURL();
            if (!url.equals("")) {
                //Sys.println("ol url: " + url.toString());
	            receiveCtr++;
	    		reqNum++;
	            //Sys.println("initial SGV request");
                Communications.makeWebRequest(url, {}, { :method => Communications.HTTP_REQUEST_METHOD_GET,
                                                         :headers => {                                           // set headers
                                                                   "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED},
                                                         :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
                                                       }, method(:onReceiveSGV));
	            return true;
            }
        }
        return false;
	}

    function onTemporalEvent() {
        Sys.println("in onTemporalEvent");
		var fetchMode = Application.getApp().getProperty("fetchMode");
		if (fetchMode == null) { fetchMode = 3; }
        receiveCtr = 0;
        reqNum = 0;
        myWebRequest(true, fetchMode, false);
        Sys.println("out onTemporalEvent");
    }
}
