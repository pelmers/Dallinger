// load essential variables
var getUrlParameter = function getUrlParameter(sParam) {
    var sPageURL = decodeURIComponent(window.location.search.substring(1)),
        sURLVariables = sPageURL.split("&"),
        sParameterName,
        i;

    for (i = 0; i < sURLVariables.length; i++) {
        sParameterName = sURLVariables[i].split("=");

        if (sParameterName[0] === sParam) {
            return sParameterName[1] === undefined ? true : sParameterName[1];
        }
    }
};
hit_id = getUrlParameter("hit_id");
worker_id = getUrlParameter("worker_id");
assignment_id = getUrlParameter("assignment_id");
mode = getUrlParameter("mode");
participant_id = getUrlParameter("participant_id");

// stop people leaving the page
window.onbeforeunload = function() {
    return "Warning: the study is not yet finished. " +
    "Closing the window, refreshing the page or navigating elsewhere " +
    "might prevent you from finishing the experiment.";
};

// allow actions to leave the page
allow_exit = function() {
    window.onbeforeunload = function() {};
};

// advance the participant to a given html page
go_to_page = function(page) {
    window.location = "/" + page + "?participant_id=" + participant_id;
};

// report assignment complete
submitAssignment = function() {
    reqwest({
        url: "/participant/" + participant_id,
        method: "get",
        type: "json",
        success: function (resp) {
            mode = resp.participant.mode;
            hit_id = resp.participant.hit_id;
            assignment_id = resp.participant.assignment_id;
            worker_id = resp.participant.worker_id;
            worker_complete = '/worker_complete';
            reqwest({
                url: worker_complete,
                method: "get",
                type: "json",
                data: {
                    "uniqueId": worker_id + ":" + assignment_id
                },
                success: function (resp) {
                    allow_exit();
                    window.location = "/complete";
                },
                error: function (err) {
                    console.log(err);
                    errorResponse = JSON.parse(err.response);
                    $("body").html(errorResponse.html);
                }
            });
        }
    });
};

submit_assignment = function () {
    submitAssignment();
};

// make a new participant
create_participant = function() {

    // check if the local store is available, and if so, use it.
    if (typeof store != "undefined") {
        url = "/participant/" +
            store.get("worker_id") + "/" +
            store.get("hit_id") + "/" +
            store.get("assignment_id") + "/" +
            store.get("mode");
    } else {
        url = "/participant/" +
            worker_id + "/" +
            hit_id + "/" +
            assignment_id + "/" +
            mode;
    }

    var deferred = $.Deferred();
    if (participant_id !== undefined && participant_id !== 'undefined') {
        deferred.resolve();
    } else {
        reqwest({
            url: url,
            method: "post",
            type: "json",
            success: function(resp) {
                console.log(resp);
                participant_id = resp.participant.id;
                deferred.resolve();
            },
            error: function (err) {
                errorResponse = JSON.parse(err.response);
                $("body").html(errorResponse.html);
            }
        });
    }
    return deferred;
};

lock = false;

submitResponses = function () {
    submitNextResponse(0);
    submitAssignment();
};

submit_responses = function () {
    submitResponses();
    submitAssignment();
};

submitNextResponse = function (n) {

    // Get all the ids.
    ids = $("form .question select, input, textarea").map(
        function () {
            return $(this).attr("id");
        }
    );

    reqwest({
        url: "/question/" + participant_id,
        method: "post",
        type: "json",
        data: {
            question: $("#" + ids[n]).attr("name"),
            number: n + 1,
            response: $("#" + ids[n]).val()
        },
        success: function() {
            if (n <= ids.length) {
                submitNextResponse(n + 1);
            }
        },
        error: function (err) {
            errorResponse = JSON.parse(err.response);
            if (errorResponse.hasOwnProperty("html")) {
                $("body").html(errorResponse.html);
            }
        }
    });
};

waitForQuorum = function () {
    var ws_scheme = (window.location.protocol === "https:") ? 'wss://' : 'ws://';
    var inbox = new ReconnectingWebSocket(ws_scheme + location.host + "/receive_chat");
    var deferred = $.Deferred();
    inbox.onmessage = function (msg) {
        if (msg.data.indexOf('quorum:') !== 0) { return; }
        var data = JSON.parse(msg.data.substring(7));
        var n = data.n;
        var quorum = data.q;
        var percent = Math.round((n / quorum) * 100.0) + '%';
        $("#waiting-progress-bar").css("width", percent);
        $("#progress-percentage").text(percent);
        if (n >= quorum) {
            deferred.resolve();
        }
    };
    return deferred;
};

numReady = function(summary) {
    for (var i = 0; i < summary.length; i++) {
        if (summary[i][0] == "working") {
            return summary[i][1];
        }
    }
};
