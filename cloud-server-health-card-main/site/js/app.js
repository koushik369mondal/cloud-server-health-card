/* Server health card — reads the JSON file the collector writes to disk.
   No build step, no framework, no cloud SDK. Served as a static file by IIS. */

(function () {
  "use strict";

  var DATA_URL = "data/status.json";
  var REFRESH_MS = 15000;
  var STALE_AFTER_S = 180; // collector runs every 60 s; 3 misses = stale

  function byPath(obj, path) {
    return path.split(".").reduce(function (a, k) {
      return a === null || a === undefined ? undefined : a[k];
    }, obj);
  }

  function pct(used, total) {
    if (!total) return 0;
    return Math.max(0, Math.min(100, Math.round((used / total) * 100)));
  }

  function setGauge(name, percent, label) {
    var g = document.querySelector('[data-gauge="' + name + '"]');
    if (!g) return;
    var bar = g.querySelector(".bar i");
    bar.style.width = percent + "%";
    bar.setAttribute("data-level", percent >= 90 ? "high" : percent >= 75 ? "warn" : "ok");
    g.querySelector("b").textContent = label;
  }

  function humanAge(s) {
    if (s < 60) return s + " s ago";
    var m = Math.floor(s / 60);
    return m < 60 ? m + " min ago" : Math.floor(m / 60) + " h " + (m % 60) + " min ago";
  }

  /* Signature element: a timing diagram. Each run is a step up, each gap a low run. */
  function drawPulse(pulses) {
    var svg = document.getElementById("pulse-wave");
    svg.innerHTML = "";
    var W = 600, HI = 14, LO = 40;
    var list = (pulses || []).slice(-40);
    if (!list.length) return;

    var step = W / list.length, d = "", x = 0;
    list.forEach(function (p, i) {
      var y = p.ok ? HI : LO;
      d += "M" + x + " " + y + " H" + (x + step * 0.62);
      if (i < list.length - 1) d += " M" + (x + step * 0.62) + " " + y + " V" + LO;
      x += step;
    });

    function path(cls, dAttr) {
      var el = document.createElementNS("http://www.w3.org/2000/svg", "path");
      el.setAttribute("class", cls);
      el.setAttribute("d", dAttr);
      svg.appendChild(el);
    }
    path("tick", "M0 " + LO + " H" + W);
    path("trace", d);
  }

  function render(data) {
    document.getElementById("error-line").hidden = true;

    document.querySelectorAll("[data-field]").forEach(function (el) {
      var v = byPath(data, el.getAttribute("data-field"));
      el.textContent = v === undefined || v === null || v === "" ? "not available" : v;
    });

    var name = byPath(data, "host.computerName");
    document.getElementById("computer-name").textContent = name || "unknown machine";
    document.title = (name || "server") + " — health card";

    var cloud = byPath(data, "deployment.cloud");
    document.getElementById("cloud-badge").textContent =
      (cloud || "cloud unset") + " · server health card";

    document.getElementById("served-host").textContent =
      window.location.host + " (" + window.location.protocol.replace(":", "") + ")";

    var h = data.host || {};
    setGauge("cpu", h.cpuLoadPercent || 0, (h.cpuLoadPercent || 0) + "%");
    setGauge("mem", pct(h.memoryUsedGb, h.memoryTotalGb), h.memoryLabel || "—");
    setGauge("disk", pct((h.diskCTotalGb || 0) - (h.diskCFreeGb || 0), h.diskCTotalGb), h.diskLabel || "—");

    drawPulse(data.pulses);

    var when = new Date(data.generatedAtUtc);
    var age = Math.max(0, Math.round((Date.now() - when.getTime()) / 1000));
    var dot = document.getElementById("pulse-dot");
    var status = document.getElementById("pulse-status");

    if (isNaN(when.getTime())) {
      dot.setAttribute("data-state", "stale");
      status.textContent = "Timestamp missing from the data file.";
    } else if (age > STALE_AFTER_S) {
      dot.setAttribute("data-state", "stale");
      status.textContent = "Collector has stopped. Check the scheduled task.";
    } else if (age > 90) {
      dot.setAttribute("data-state", "late");
      status.textContent = "Collector is running late.";
    } else {
      dot.setAttribute("data-state", "live");
      status.textContent = "Collector is running.";
    }
    document.getElementById("pulse-age").textContent = isNaN(when.getTime())
      ? "" : "Last write " + humanAge(age) + " · " + when.toLocaleString();
  }

  function load() {
    fetch(DATA_URL + "?t=" + Date.now(), { cache: "no-store" })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status + " requesting " + DATA_URL);
        return r.json();
      })
      .then(render)
      .catch(function (e) {
        var line = document.getElementById("error-line");
        line.hidden = false;
        line.textContent =
          e.message + " — run scripts\\2-Collect-Status.ps1 on the server, then reload.";
        document.getElementById("pulse-dot").setAttribute("data-state", "stale");
        document.getElementById("pulse-status").textContent = "Collector data unavailable.";
      });
  }

  load();
  setInterval(load, REFRESH_MS);
})();
